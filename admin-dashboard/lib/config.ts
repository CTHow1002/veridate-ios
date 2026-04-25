import "server-only";

type AdminConfig = {
  supabaseUrl: string;
  serviceRoleKey: string;
  adminUsername: string;
  adminPassword: string;
  sessionSecret: string;
};

export function getAdminConfig(): AdminConfig {
  const missing = ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "ADMIN_SESSION_SECRET"].filter(
    (key) => !process.env[key]
  );

  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(", ")}`);
  }

  return {
    supabaseUrl: process.env.SUPABASE_URL as string,
    serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY as string,
    adminUsername: process.env.ADMIN_USERNAME || "admin",
    adminPassword: process.env.ADMIN_PASSWORD || "admin",
    sessionSecret: process.env.ADMIN_SESSION_SECRET as string,
  };
}
