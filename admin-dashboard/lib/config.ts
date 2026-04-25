import "server-only";

type SessionConfig = {
  adminUsername: string;
  adminPassword: string;
  sessionSecret: string;
};

type SupabaseConfig = {
  supabaseUrl: string;
  serviceRoleKey: string;
};

export function getSessionConfig(): SessionConfig {
  requireEnv(["ADMIN_SESSION_SECRET"]);

  return {
    adminUsername: process.env.ADMIN_USERNAME || "admin",
    adminPassword: process.env.ADMIN_PASSWORD || "admin",
    sessionSecret: process.env.ADMIN_SESSION_SECRET as string,
  };
}

export function getSupabaseConfig(): SupabaseConfig {
  requireEnv(["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"]);

  return {
    supabaseUrl: process.env.SUPABASE_URL as string,
    serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY as string,
  };
}

function requireEnv(keys: string[]) {
  const missing = keys.filter((key) => !process.env[key]);

  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(", ")}`);
  }
}
