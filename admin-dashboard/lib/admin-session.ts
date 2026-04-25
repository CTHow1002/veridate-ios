import "server-only";

import { createHmac, timingSafeEqual } from "node:crypto";
import { cookies } from "next/headers";
import { isAdminAllowed } from "@/lib/admin-users";
import { getSessionConfig } from "@/lib/config";

export const sessionCookieOptions = {
  httpOnly: true,
  sameSite: "lax",
  path: "/",
  maxAge: 60 * 60 * 8,
} as const;

export function signSession(username: string) {
  const payload = Buffer.from(
    JSON.stringify({
      username: username.trim().toLowerCase(),
      expiresAt: Date.now() + 1000 * 60 * 60 * 8,
    })
  ).toString("base64url");

  return `${payload}.${sign(payload)}`;
}

export async function isAuthenticated() {
  return (await getAuthenticatedAdmin()) !== null;
}

export async function getAuthenticatedAdmin() {
  const cookieStore = await cookies();
  const cookie = cookieStore.get("admin_session")?.value;
  if (!cookie) return null;

  const [payload, signature] = cookie.split(".");
  if (!payload || !signature) return null;

  if (!safeEqual(signature, sign(payload))) return null;

  try {
    const session = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as {
      username?: string;
      expiresAt?: number;
    };
    const username = session.username?.trim().toLowerCase();
    if (!username || Number(session.expiresAt) <= Date.now()) return null;
    if (!(await isAdminAllowed(username))) return null;

    return username;
  } catch {
    return null;
  }
}

function sign(value: string) {
  return createHmac("sha256", getSessionConfig().sessionSecret).update(value).digest("base64url");
}

function safeEqual(left: string, right: string) {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);

  if (leftBuffer.length !== rightBuffer.length) return false;
  return timingSafeEqual(leftBuffer, rightBuffer);
}
