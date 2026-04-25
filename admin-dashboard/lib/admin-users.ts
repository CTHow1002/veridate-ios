import "server-only";

import { supabaseRequest } from "@/lib/supabase-admin";

type AdminUserRow = {
  username: string;
};

export async function isAdminAllowed(username: string) {
  const cleanUsername = username.trim().toLowerCase();
  if (!cleanUsername) return false;

  let rows: AdminUserRow[];

  try {
    rows = await supabaseRequest<AdminUserRow[]>(
      `/rest/v1/admin_users?username=eq.${encodeURIComponent(cleanUsername)}&is_active=eq.true&select=username&limit=1`
    );
  } catch (error) {
    if (isMissingUsernameColumnError(error)) {
      throw new Error(
        "Admin allowlist setup is incomplete. Run the latest admin-dashboard/supabase.sql in Supabase SQL Editor, then add your admin username to public.admin_users."
      );
    }

    throw error;
  }

  return rows.length > 0;
}

export async function recordAdminLogin(username: string) {
  const cleanUsername = username.trim().toLowerCase();
  if (!cleanUsername) return;

  await supabaseRequest(`/rest/v1/admin_users?username=eq.${encodeURIComponent(cleanUsername)}`, {
    method: "PATCH",
    body: {
      last_login_at: new Date().toISOString(),
    },
  });
}

function isMissingUsernameColumnError(error: unknown) {
  if (!(error instanceof Error)) return false;

  return (
    error.message.includes("42703") &&
    error.message.toLowerCase().includes("admin_users.username")
  );
}
