import { createHmac, randomUUID, timingSafeEqual } from "node:crypto";
import { createReadStream, existsSync, readFileSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
loadEnv();

const config = {
  port: Number(process.env.PORT || 3000),
  host: process.env.HOST || "127.0.0.1",
  supabaseUrl: process.env.SUPABASE_URL,
  serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY,
  adminUsername: process.env.ADMIN_USERNAME || "admin",
  adminPassword: process.env.ADMIN_PASSWORD || "admin",
  sessionSecret: process.env.ADMIN_SESSION_SECRET || randomUUID(),
};

const requiredEnv = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "ADMIN_SESSION_SECRET"];
const missingEnv = requiredEnv.filter((key) => !process.env[key]);

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host}`);

    if (url.pathname.startsWith("/assets/")) {
      return serveStatic(req, res, url.pathname);
    }

    if (url.pathname === "/api/login" && req.method === "POST") {
      return handleLogin(req, res);
    }

    if (url.pathname === "/api/logout" && req.method === "POST") {
      return sendJson(res, 200, { ok: true }, { "Set-Cookie": expiredCookie() });
    }

    if (url.pathname === "/api/submissions" && req.method === "GET") {
      if (!isAuthenticated(req)) return sendJson(res, 401, { error: "Not signed in." });
      return await handleListSubmissions(res);
    }

    const actionMatch = url.pathname.match(/^\/api\/submissions\/([^/]+)\/(approve|reject)$/);
    if (actionMatch && req.method === "POST") {
      if (!isAuthenticated(req)) return sendJson(res, 401, { error: "Not signed in." });
      return await handleReviewAction(req, res, actionMatch[1], actionMatch[2]);
    }

    if (url.pathname === "/" || url.pathname === "/login") {
      return serveHtml(res, isAuthenticated(req) ? "dashboard.html" : "login.html");
    }

    return sendJson(res, 404, { error: "Not found." });
  } catch (error) {
    console.error(error);
    return sendJson(res, 500, { error: "Server error. Check the admin dashboard logs." });
  }
});

server.listen(config.port, config.host, () => {
  console.log(`VeriDate admin dashboard running at http://${config.host}:${config.port}`);
  if (missingEnv.length > 0) {
    console.warn(`Missing env values: ${missingEnv.join(", ")}`);
  }
});

async function handleLogin(req, res) {
  const body = await readJson(req);
  const username = String(body.username || "");
  const password = String(body.password || "");

  if (username !== config.adminUsername || password !== config.adminPassword) {
    return sendJson(res, 401, { error: "Incorrect admin username or password." });
  }

  return sendJson(res, 200, { ok: true }, { "Set-Cookie": sessionCookie(username) });
}

async function handleListSubmissions(res) {
  ensureSupabaseConfig();

  const submissions = await supabaseRequest(
    `/rest/v1/verification_submissions?status=eq.pending&select=*&order=submitted_at.asc`
  );
  const userIds = [...new Set(submissions.map((submission) => submission.user_id).filter(Boolean))];
  const profilesById = await fetchProfilesById(userIds);

  const enriched = await Promise.all(
    submissions.map(async (submission) => {
      const profile = profilesById.get(submission.user_id) || {};
      const files = await signedFileLinks(submission);

      return {
        id: submission.id,
        userId: submission.user_id,
        submittedAt: submission.submitted_at || submission.created_at || null,
        profile,
        files,
      };
    })
  );

  return sendJson(res, 200, { submissions: enriched });
}

async function handleReviewAction(req, res, submissionId, action) {
  ensureSupabaseConfig();

  const body = await readJson(req);
  const rejectionReason = String(body.rejectionReason || "").trim();

  if (action === "reject" && rejectionReason.length === 0) {
    return sendJson(res, 400, { error: "Enter a rejection reason." });
  }

  const [submission] = await supabaseRequest(
    `/rest/v1/verification_submissions?id=eq.${encodeURIComponent(submissionId)}&select=*`
  );

  if (!submission) {
    return sendJson(res, 404, { error: "Submission not found." });
  }

  const status = action === "approve" ? "verified" : "rejected";
  const now = new Date().toISOString();

  await supabaseRequest(
    `/rest/v1/verification_submissions?id=eq.${encodeURIComponent(submissionId)}`,
    {
      method: "PATCH",
      body: {
        status,
        rejection_reason: action === "reject" ? rejectionReason : null,
        reviewed_at: now,
      },
    }
  );

  await supabaseRequest(
    `/rest/v1/profiles?id=eq.${encodeURIComponent(submission.user_id)}`,
    {
      method: "PATCH",
      body: {
        verification_status: status,
      },
    }
  );

  return sendJson(res, 200, { ok: true, status });
}

async function fetchProfilesById(userIds) {
  if (userIds.length === 0) return new Map();

  const encodedIds = userIds.join(",");
  const profiles = await supabaseRequest(
    `/rest/v1/profiles?id=in.(${encodedIds})&select=id,full_name,date_of_birth,job_title,company_name,education_level,school_name`
  );

  return new Map(profiles.map((profile) => [profile.id, profile]));
}

async function signedFileLinks(submission) {
  const fileFields = {
    selfie: ["selfie_file_path", "selfie_path", "selfie_file"],
    idDocument: ["id_document_file_path", "id_document_path", "id_document_file"],
    jobProof: ["job_proof_file_path", "job_proof_path", "job_proof_file"],
    educationProof: ["education_proof_file_path", "education_proof_path", "education_proof_file"],
  };

  const entries = await Promise.all(
    Object.entries(fileFields).map(async ([key, fieldNames]) => {
      const path = fieldNames.map((field) => submission[field]).find(Boolean);
      return [key, await signedStorageLink(path)];
    })
  );

  return Object.fromEntries(entries);
}

async function signedStorageLink(path) {
  if (!path) return null;
  if (/^https?:\/\//i.test(path)) return { path, url: path };

  const safePath = path
    .split("/")
    .map((part) => encodeURIComponent(part))
    .join("/");

  const response = await supabaseRequest(
    `/storage/v1/object/sign/verification-documents/${safePath}`,
    {
      method: "POST",
      body: { expiresIn: 600 },
    }
  );

  return {
    path,
    url: `${config.supabaseUrl}${response.signedURL}`,
  };
}

async function supabaseRequest(path, options = {}) {
  const response = await fetch(`${config.supabaseUrl}${path}`, {
    method: options.method || "GET",
    headers: {
      apikey: config.serviceRoleKey,
      Authorization: `Bearer ${config.serviceRoleKey}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Supabase request failed (${response.status}): ${text}`);
  }

  if (response.status === 204) return null;
  return response.json();
}

function isAuthenticated(req) {
  const cookie = parseCookies(req.headers.cookie || "").admin_session;
  if (!cookie) return false;

  const [payload, signature] = cookie.split(".");
  if (!payload || !signature) return false;

  const expected = sign(payload);
  if (!safeEqual(signature, expected)) return false;

  try {
    const session = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
    return session.username === config.adminUsername && session.expiresAt > Date.now();
  } catch {
    return false;
  }
}

function sessionCookie(username) {
  const payload = Buffer.from(
    JSON.stringify({
      username,
      expiresAt: Date.now() + 1000 * 60 * 60 * 8,
    })
  ).toString("base64url");

  return [
    `admin_session=${payload}.${sign(payload)}`,
    "HttpOnly",
    "SameSite=Lax",
    "Path=/",
    "Max-Age=28800",
  ].join("; ");
}

function expiredCookie() {
  return "admin_session=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0";
}

function sign(value) {
  return createHmac("sha256", config.sessionSecret).update(value).digest("base64url");
}

function safeEqual(left, right) {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);

  if (leftBuffer.length !== rightBuffer.length) return false;
  return timingSafeEqual(leftBuffer, rightBuffer);
}

function parseCookies(header) {
  return Object.fromEntries(
    header
      .split(";")
      .map((part) => part.trim())
      .filter(Boolean)
      .map((part) => {
        const [key, ...value] = part.split("=");
        return [key, value.join("=")];
      })
  );
}

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);

  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function serveHtml(res, fileName) {
  const htmlPath = join(__dirname, "public", fileName);
  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  createReadStream(htmlPath).pipe(res);
}

function serveStatic(req, res, pathname) {
  const filePath = join(__dirname, "public", pathname.replace("/assets/", "assets/"));

  if (!existsSync(filePath)) {
    return sendJson(res, 404, { error: "Asset not found." });
  }

  const contentTypes = {
    ".css": "text/css; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
  };

  res.writeHead(200, { "Content-Type": contentTypes[extname(filePath)] || "application/octet-stream" });
  createReadStream(filePath).pipe(res);
}

function sendJson(res, status, body, extraHeaders = {}) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    ...extraHeaders,
  });
  res.end(JSON.stringify(body));
}

function ensureSupabaseConfig() {
  if (missingEnv.length > 0) {
    throw new Error(`Missing required env values: ${missingEnv.join(", ")}`);
  }
}

function loadEnv() {
  const envPath = join(__dirname, ".env");
  if (!existsSync(envPath)) return;

  const lines = readFileSync(envPath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const index = trimmed.indexOf("=");
    if (index === -1) continue;

    const key = trimmed.slice(0, index).trim();
    const value = trimmed.slice(index + 1).trim().replace(/^["']|["']$/g, "");
    if (!process.env[key]) process.env[key] = value;
  }
}
