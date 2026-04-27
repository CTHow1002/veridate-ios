import "server-only";

import { getSupabaseConfig } from "@/lib/config";
import { supabaseRequest } from "@/lib/supabase-admin";
import type { Profile, ReportStatus, SafetyReport, SignedFile } from "@/lib/types";

type ReportRow = {
  id: string;
  reporter_user_id: string;
  reported_user_id: string;
  match_id?: string | null;
  reason: string;
  details?: string | null;
  proof_file_path?: string | null;
  status?: ReportStatus | null;
  moderation_notes?: string | null;
  action_taken?: string | null;
  reviewed_at?: string | null;
  created_at?: string | null;
};

export type ReportAction = "dismiss" | "warn" | "ban";

type ModerationInput = {
  moderationNotes?: string;
  banDays?: number | null;
};

export async function getOpenReports(): Promise<SafetyReport[]> {
  const reports = await supabaseRequest<ReportRow[]>(
    "/rest/v1/reports?status=eq.open&select=*&order=created_at.asc"
  );
  const userIds = [
    ...new Set(
      reports
        .flatMap((report) => [report.reporter_user_id, report.reported_user_id])
        .filter(Boolean)
    ),
  ];
  const profilesById = await fetchProfilesById(userIds);

  return Promise.all(
    reports.map(async (report) => ({
      id: report.id,
      reporterUserId: report.reporter_user_id,
      reportedUserId: report.reported_user_id,
      matchId: report.match_id || null,
      reason: report.reason,
      details: report.details || null,
      proofFile: await signedStorageLink(report.proof_file_path || null),
      status: report.status || "open",
      moderationNotes: report.moderation_notes || null,
      actionTaken: report.action_taken || null,
      reviewedAt: report.reviewed_at || null,
      createdAt: report.created_at || null,
      reporter: profilesById.get(report.reporter_user_id) || ({ id: report.reporter_user_id } satisfies Profile),
      reportedUser: profilesById.get(report.reported_user_id) || ({ id: report.reported_user_id } satisfies Profile),
    }))
  );
}

export async function moderateReport(id: string, action: ReportAction, input: ModerationInput = {}) {
  const [report] = await supabaseRequest<ReportRow[]>(
    `/rest/v1/reports?id=eq.${encodeURIComponent(id)}&select=id,reported_user_id,status`
  );

  if (!report) {
    throw new Error("Report not found.");
  }

  if (report.status && report.status !== "open") {
    throw new Error("This report has already been reviewed.");
  }

  const status = statusForAction(action);
  const reviewedAt = new Date().toISOString();
  const moderationNotes = cleanText(input.moderationNotes);

  if (action === "warn") {
    await supabaseRequest(`/rest/v1/profiles?id=eq.${encodeURIComponent(report.reported_user_id)}`, {
      method: "PATCH",
      body: {
        warning_message: moderationNotes || "You received a warning from VeriDate moderation.",
        warning_details: moderationNotes,
        warned_at: reviewedAt,
      },
    });
  } else if (action === "ban") {
    const banUntil = banUntilFromDays(input.banDays);

    await supabaseRequest(`/rest/v1/profiles?id=eq.${encodeURIComponent(report.reported_user_id)}`, {
      method: "PATCH",
      body: {
        is_banned: true,
        ban_until: banUntil,
        ban_message: moderationNotes || "Your VeriDate account has been temporarily restricted.",
        ban_details: moderationNotes,
      },
    });

    const [profile] = await supabaseRequest<Pick<Profile, "is_banned" | "ban_until">[]>(
      `/rest/v1/profiles?id=eq.${encodeURIComponent(report.reported_user_id)}&select=is_banned,ban_until&limit=1`
    );

    if (profile?.is_banned !== true) {
      throw new Error("The reported user's ban status did not update.");
    }
  }

  await supabaseRequest(`/rest/v1/reports?id=eq.${encodeURIComponent(id)}`, {
    method: "PATCH",
    body: {
      status,
      action_taken: action,
      moderation_notes: moderationNotes || null,
      reviewed_at: reviewedAt,
    },
  });
}

async function fetchProfilesById(userIds: string[]) {
  if (userIds.length === 0) return new Map<string, Profile>();

  const profiles = await supabaseRequest<Profile[]>(
    `/rest/v1/profiles?id=in.(${userIds.join(",")})&select=id,full_name,date_of_birth,job_title,company_name,education_level,school_name,verification_status,is_banned,ban_until,ban_message,ban_details,warning_message,warning_details,warned_at`
  );

  return new Map(profiles.map((profile) => [profile.id, profile]));
}

function statusForAction(action: ReportAction): ReportStatus {
  if (action === "dismiss") return "dismissed";
  if (action === "warn") return "warned";
  return "banned";
}

function cleanText(value?: string) {
  const cleaned = String(value || "").trim();
  return cleaned || null;
}

function banUntilFromDays(days?: number | null) {
  const numericDays = Number(days || 0);
  if (!Number.isFinite(numericDays) || numericDays <= 0) return null;

  const date = new Date();
  date.setUTCDate(date.getUTCDate() + Math.round(numericDays));
  return date.toISOString();
}

async function signedStorageLink(path: string | null): Promise<SignedFile | null> {
  if (!path) return null;
  if (/^https?:\/\//i.test(path)) return { path, url: path };

  const objectPath = normalizeStoragePath(path);
  const safePath = objectPath
    .split("/")
    .map((part) => encodeURIComponent(part))
    .join("/");

  const response = await supabaseRequest<{ signedURL: string }>(
    `/storage/v1/object/sign/verification-documents/${safePath}`,
    {
      method: "POST",
      body: { expiresIn: 600 },
    }
  );

  return {
    path: objectPath,
    url: storageObjectUrl(response.signedURL),
  };
}

function normalizeStoragePath(path: string) {
  return path
    .replace(/^\/+/, "")
    .replace(/^storage\/v1\/object\/(?:public\/|sign\/)?verification-documents\//, "")
    .replace(/^object\/(?:public\/|sign\/)?verification-documents\//, "")
    .replace(/^verification-documents\//, "");
}

function storageObjectUrl(signedURL: string) {
  const supabaseUrl = getSupabaseConfig().supabaseUrl.replace(/\/$/, "");

  if (/^https?:\/\//i.test(signedURL)) {
    return signedURL;
  }

  if (signedURL.startsWith("/storage/v1/")) {
    return `${supabaseUrl}${signedURL}`;
  }

  return `${supabaseUrl}/storage/v1${signedURL.startsWith("/") ? "" : "/"}${signedURL}`;
}
