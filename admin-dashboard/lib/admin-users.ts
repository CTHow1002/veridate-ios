import "server-only";

import { supabaseRequest } from "@/lib/supabase-admin";

type AdminUserRow = {
  username: string;
};

export async function isAdminAllowed(username: string) {
  const cleanUsername = username.trim().toLowerCase();
  if (!cleanUsername) return false;

  const rows = await supabaseRequest<AdminUserRow[]>(
    `/rest/v1/admin_users?username=eq.${encodeURIComponent(cleanUsername)}&is_active=eq.true&select=username&limit=1`
  );

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
