import "server-only";

import { supabaseRequest } from "@/lib/supabase-admin";
import type { ModeratedUser, Profile, ReportStatus } from "@/lib/types";

type ModeratedProfileRow = Pick<
  Profile,
  | "id"
  | "full_name"
  | "verification_status"
  | "is_banned"
  | "ban_until"
  | "ban_message"
  | "ban_details"
  | "warning_message"
  | "warning_details"
  | "warned_at"
  | "warning_until"
>;

type ModerationReportRow = {
  reported_user_id: string;
  status?: ReportStatus | null;
  reason?: string | null;
  moderation_notes?: string | null;
  reviewed_at?: string | null;
};

export type UserModerationAction = "update-ban" | "unban" | "update-warning" | "clear-warning";

type UserModerationInput = {
  action: UserModerationAction;
  moderationNotes?: string;
  banDays?: number | null;
  warningDays?: number | null;
};

export async function getModeratedUsers(): Promise<ModeratedUser[]> {
  const profiles = await supabaseRequest<ModeratedProfileRow[]>(
    "/rest/v1/profiles?or=(is_banned.eq.true,warned_at.not.is.null,warning_message.not.is.null)&select=id,full_name,verification_status,is_banned,ban_until,ban_message,ban_details,warning_message,warning_details,warned_at,warning_until"
  );

  if (profiles.length === 0) return [];

  const reportMap = await fetchLatestReports(profiles.map((profile) => profile.id));

  return profiles
    .map((profile) => {
      const report = reportMap.get(profile.id);

      return {
        id: profile.id,
        fullName: profile.full_name || null,
        verificationStatus: profile.verification_status || null,
        status: profile.is_banned ? "banned" : "warned",
        isBanned: profile.is_banned === true,
        banUntil: profile.ban_until || null,
        banMessage: profile.ban_message || null,
        banDetails: profile.ban_details || null,
        warningMessage: profile.warning_message || null,
        warningDetails: profile.warning_details || null,
        warnedAt: profile.warned_at || null,
        warningUntil: profile.warning_until || null,
        latestReportStatus: report?.status || null,
        latestReportReason: report?.reason || null,
        latestReportNotes: report?.moderation_notes || null,
        latestReportReviewedAt: report?.reviewed_at || null,
      } satisfies ModeratedUser;
    })
    .sort(compareModeratedUsers);
}

export async function updateModeratedUser(userId: string, input: UserModerationInput) {
  if (input.action === "unban") {
    await supabaseRequest(`/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}`, {
      method: "PATCH",
      body: {
        is_banned: false,
        ban_until: null,
        ban_message: null,
        ban_details: null,
      },
    });
    return;
  }

  if (input.action === "clear-warning") {
    await supabaseRequest(`/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}`, {
      method: "PATCH",
      body: {
        warning_message: null,
        warning_details: null,
        warned_at: null,
        warning_until: null,
      },
    });
    return;
  }

  const moderationNotes = cleanText(input.moderationNotes);

  if (input.action === "update-warning") {
    const warningUntil = durationFromDays(input.warningDays);

    await supabaseRequest(`/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}`, {
      method: "PATCH",
      body: {
        warning_message: moderationNotes || "You received a warning from VeriDate moderation.",
        warning_details: null,
        warned_at: new Date().toISOString(),
        warning_until: warningUntil,
      },
    });
    return;
  }

  const banUntil = durationFromDays(input.banDays);
  if (!banUntil) {
    throw new Error("Set a ban duration of at least 1 day.");
  }

  await supabaseRequest(`/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}`, {
    method: "PATCH",
    body: {
      is_banned: true,
      ban_until: banUntil,
      ban_message: moderationNotes || "Your VeriDate account has been temporarily restricted.",
      ban_details: moderationNotes,
    },
  });
}

async function fetchLatestReports(userIds: string[]) {
  const reports = await supabaseRequest<ModerationReportRow[]>(
    `/rest/v1/reports?reported_user_id=in.(${userIds.join(",")})&status=in.(warned,banned)&select=reported_user_id,status,reason,moderation_notes,reviewed_at&order=reviewed_at.desc.nullslast`
  );

  const reportsByUserId = new Map<string, ModerationReportRow>();

  for (const report of reports) {
    if (!reportsByUserId.has(report.reported_user_id)) {
      reportsByUserId.set(report.reported_user_id, report);
    }
  }

  return reportsByUserId;
}

function compareModeratedUsers(left: ModeratedUser, right: ModeratedUser) {
  if (left.isBanned !== right.isBanned) return left.isBanned ? -1 : 1;

  const leftDate = Date.parse(left.banUntil || left.warnedAt || left.latestReportReviewedAt || "") || 0;
  const rightDate = Date.parse(right.banUntil || right.warnedAt || right.latestReportReviewedAt || "") || 0;
  return rightDate - leftDate;
}

function durationFromDays(days?: number | null) {
  const numericDays = Number(days || 0);
  if (!Number.isFinite(numericDays) || numericDays <= 0) return null;

  const date = new Date();
  date.setUTCDate(date.getUTCDate() + Math.round(numericDays));
  return date.toISOString();
}

function cleanText(value?: string) {
  const cleaned = String(value || "").trim();
  return cleaned || null;
}
