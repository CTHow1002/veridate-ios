import "server-only";

import { supabaseAuthAdminRequest, supabaseRequest } from "@/lib/supabase-admin";
import type { AccountDeletionRequest, AccountDeletionStatus, Profile } from "@/lib/types";

type AccountDeletionRequestRow = {
  id: string;
  user_id: string;
  status: AccountDeletionStatus;
  reason?: string | null;
  requested_at: string;
  scheduled_delete_at: string;
  processed_at?: string | null;
  canceled_at?: string | null;
  error_message?: string | null;
  created_at: string;
  updated_at: string;
};

type ProcessResult = {
  id: string;
  userId: string;
  status: "completed" | "failed";
  error?: string;
};

export async function getAccountDeletionRequests(): Promise<AccountDeletionRequest[]> {
  const rows = await supabaseRequest<AccountDeletionRequestRow[]>(
    "/rest/v1/account_deletion_requests?select=*&order=requested_at.desc&limit=50"
  );
  const profilesById = await fetchProfilesById([...new Set(rows.map((row) => row.user_id))]);

  return rows.map((row) => mapDeletionRequest(row, profilesById.get(row.user_id) || null));
}

export async function processDueAccountDeletions(limit = 5): Promise<ProcessResult[]> {
  const now = new Date().toISOString();
  const rows = await supabaseRequest<AccountDeletionRequestRow[]>(
    `/rest/v1/account_deletion_requests?status=eq.pending&scheduled_delete_at=lte.${encodeURIComponent(now)}&select=*&order=scheduled_delete_at.asc&limit=${limit}`
  );

  const results: ProcessResult[] = [];

  for (const row of rows) {
    results.push(await processAccountDeletion(row));
  }

  return results;
}

async function processAccountDeletion(row: AccountDeletionRequestRow): Promise<ProcessResult> {
  const processingAt = new Date().toISOString();

  try {
    await supabaseRequest(`/rest/v1/account_deletion_requests?id=eq.${encodeURIComponent(row.id)}`, {
      method: "PATCH",
      body: {
        status: "processing",
        error_message: null,
      },
    });

    await deleteUserData(row.user_id);
    await deleteAuthUser(row.user_id);

    await supabaseRequest(`/rest/v1/account_deletion_requests?id=eq.${encodeURIComponent(row.id)}`, {
      method: "PATCH",
      body: {
        status: "completed",
        processed_at: processingAt,
        error_message: null,
      },
    });

    return {
      id: row.id,
      userId: row.user_id,
      status: "completed",
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown deletion error.";
    await supabaseRequest(`/rest/v1/account_deletion_requests?id=eq.${encodeURIComponent(row.id)}`, {
      method: "PATCH",
      body: {
        status: "failed",
        error_message: message.slice(0, 1000),
      },
    });

    return {
      id: row.id,
      userId: row.user_id,
      status: "failed",
      error: message,
    };
  }
}

async function deleteUserData(userId: string) {
  const safeUserId = encodeURIComponent(userId);
  const matchFilter = `or=(user_one_id.eq.${safeUserId},user_two_id.eq.${safeUserId})`;
  const actionFilter = `or=(actor_user_id.eq.${safeUserId},target_user_id.eq.${safeUserId})`;
  const blockFilter = `or=(blocker_user_id.eq.${safeUserId},blocked_user_id.eq.${safeUserId})`;
  const reportFilter = `or=(reporter_user_id.eq.${safeUserId},reported_user_id.eq.${safeUserId})`;

  await safeDelete(`/rest/v1/message_reactions?user_id=eq.${safeUserId}`);
  await safeDelete(`/rest/v1/messages?sender_id=eq.${safeUserId}`);
  await safeDelete(`/rest/v1/chat_typing?user_id=eq.${safeUserId}`);
  await safeDelete(`/rest/v1/matches?${matchFilter}`);
  await safeDelete(`/rest/v1/profile_actions?${actionFilter}`);
  await safeDelete(`/rest/v1/blocks?${blockFilter}`);
  await safeDelete(`/rest/v1/user_blocks?${blockFilter}`);
  await safeDelete(`/rest/v1/reports?${reportFilter}`);
  await safeDelete(`/rest/v1/user_reports?${reportFilter}`);
  await safeDelete(`/rest/v1/verification_submissions?user_id=eq.${safeUserId}`);
  await safeDelete(`/rest/v1/profile_prompts?user_id=eq.${safeUserId}`);
  await safeDelete(`/rest/v1/profile_interests?user_id=eq.${safeUserId}`);
  await safeDelete(`/rest/v1/profile_photos?user_id=eq.${safeUserId}`);
  await safeDelete(`/rest/v1/dating_filters?user_id=eq.${safeUserId}`);
  await safeDelete(`/rest/v1/user_push_tokens?user_id=eq.${safeUserId}`);
  await safeDelete(`/rest/v1/profiles?id=eq.${safeUserId}`);
}

async function safeDelete(path: string) {
  try {
    await supabaseRequest(path, { method: "DELETE" });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (
      message.includes("PGRST205") ||
      message.includes("relation") ||
      message.includes("does not exist") ||
      message.includes("Could not find the table")
    ) {
      return;
    }

    throw error;
  }
}

async function deleteAuthUser(userId: string) {
  await supabaseAuthAdminRequest(`/auth/v1/admin/users/${encodeURIComponent(userId)}`, {
    method: "DELETE",
  });
}

async function fetchProfilesById(userIds: string[]) {
  if (userIds.length === 0) return new Map<string, Profile>();

  const profiles = await supabaseRequest<Profile[]>(
    `/rest/v1/profiles?id=in.(${userIds.map(encodeURIComponent).join(",")})&select=id,full_name,date_of_birth,verification_status,is_deactivated,account_deletion_requested_at,account_deletion_scheduled_at`
  );

  return new Map(profiles.map((profile) => [profile.id, profile]));
}

function mapDeletionRequest(row: AccountDeletionRequestRow, profile: Profile | null): AccountDeletionRequest {
  return {
    id: row.id,
    userId: row.user_id,
    status: row.status,
    reason: row.reason || null,
    requestedAt: row.requested_at,
    scheduledDeleteAt: row.scheduled_delete_at,
    processedAt: row.processed_at || null,
    canceledAt: row.canceled_at || null,
    errorMessage: row.error_message || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    profile,
  };
}
