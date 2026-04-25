import "server-only";

import { getSupabaseConfig } from "@/lib/config";

type SupabaseRequestOptions = {
  method?: "GET" | "PATCH" | "POST";
  body?: unknown;
};

export async function supabaseRequest<T>(path: string, options: SupabaseRequestOptions = {}) {
  const config = getSupabaseConfig();
  const response = await fetch(`${config.supabaseUrl}${path}`, {
    method: options.method || "GET",
    headers: {
      apikey: config.serviceRoleKey,
      Authorization: `Bearer ${config.serviceRoleKey}`,
      "Content-Type": "application/json",
      Prefer: "return=representation",
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
    cache: "no-store",
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Supabase request failed (${response.status}): ${text}`);
  }

  if (response.status === 204) return null as T;
  return (await response.json()) as T;
}
