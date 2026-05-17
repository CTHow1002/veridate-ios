import "server-only";

import { getSupabaseConfig } from "@/lib/config";
import { createAppNotification } from "@/lib/notifications";
import { supabaseRequest } from "@/lib/supabase-admin";
import type { Profile, ProfileChangeRequest, ProfileChangeRequestStatus, ProfileChangeRequestType, SignedFile } from "@/lib/types";

type ProfileChangeRequestRow = {
  id: string;
  user_id: string;
  request_type: ProfileChangeRequestType;
  status: ProfileChangeRequestStatus;
  current_full_name?: string | null;
  requested_full_name?: string | null;
  current_job_title?: string | null;
  requested_job_title?: string | null;
  current_company_name?: string | null;
  requested_company_name?: string | null;
  current_education_level?: string | null;
  requested_education_level?: string | null;
  current_school_name?: string | null;
  requested_school_name?: string | null;
  message?: string | null;
  attachment_file_path?: string | null;
  attachment_file_name?: string | null;
  attachment_content_type?: string | null;
  attachment_source?: string | null;
  admin_notes?: string | null;
  reviewed_at?: string | null;
  created_at: string;
  updated_at: string;
};

export type ProfileChangeRequestAction = "approve" | "reject";

export async function getProfileChangeRequests(): Promise<ProfileChangeRequest[]> {
  const rows = await supabaseRequest<ProfileChangeRequestRow[]>(
    "/rest/v1/profile_change_requests?status=eq.pending&select=*&order=created_at.asc&limit=50"
  );
  const profilesById = await fetchProfilesById([...new Set(rows.map((row) => row.user_id))]);

  return Promise.all(rows.map(async (row) => mapProfileChangeRequest(row, profilesById.get(row.user_id) || null)));
}

export async function reviewProfileChangeRequest(
  id: string,
  action: ProfileChangeRequestAction,
  adminNotes?: string
) {
  const [request] = await supabaseRequest<ProfileChangeRequestRow[]>(
    `/rest/v1/profile_change_requests?id=eq.${encodeURIComponent(id)}&select=*&limit=1`
  );

  if (!request) {
    throw new Error("Profile change request not found.");
  }

  if (request.status !== "pending") {
    throw new Error("This profile change request is no longer pending.");
  }

  if (action === "approve") {
    await applyProfileChange(request);
  }

  await supabaseRequest(`/rest/v1/profile_change_requests?id=eq.${encodeURIComponent(id)}`, {
    method: "PATCH",
    body: {
      status: action === "approve" ? "approved" : "rejected",
      admin_notes: cleanText(adminNotes),
      reviewed_at: new Date().toISOString(),
    },
  });

  await createAppNotification({
    userId: request.user_id,
    category: "profile_change",
    title: action === "approve" ? "Profile change approved" : "Profile change rejected",
    body:
      action === "approve"
        ? `${requestTypeLabel(request.request_type)} was approved and applied to your profile.`
        : `${requestTypeLabel(request.request_type)} was rejected.${cleanText(adminNotes) ? ` Note: ${cleanText(adminNotes)}` : ""}`,
    metadata: { requestId: id, requestType: request.request_type, status: action },
  });
}

async function applyProfileChange(request: ProfileChangeRequestRow) {
  const body: Partial<Profile> = {};

  if (request.request_type === "legal_name") {
    body.full_name = cleanText(request.requested_full_name);
  }

  if (request.request_type === "work") {
    body.job_title = cleanText(request.requested_job_title);
    body.company_name = cleanText(request.requested_company_name);
  }

  if (request.request_type === "education") {
    body.education_level = cleanText(request.requested_education_level);
    body.school_name = cleanText(request.requested_school_name);
  }

  if (Object.keys(body).length === 0) {
    throw new Error("No requested changes were provided.");
  }

  await supabaseRequest(`/rest/v1/profiles?id=eq.${encodeURIComponent(request.user_id)}`, {
    method: "PATCH",
    body,
  });
}

async function fetchProfilesById(userIds: string[]) {
  if (userIds.length === 0) return new Map<string, Profile>();

  const profiles = await supabaseRequest<Profile[]>(
    `/rest/v1/profiles?id=in.(${userIds.map(encodeURIComponent).join(",")})&select=id,full_name,date_of_birth,job_title,company_name,education_level,school_name,verification_status`
  );

  return new Map(profiles.map((profile) => [profile.id, profile]));
}

async function mapProfileChangeRequest(row: ProfileChangeRequestRow, profile: Profile | null): Promise<ProfileChangeRequest> {
  return {
    id: row.id,
    userId: row.user_id,
    requestType: row.request_type,
    status: row.status,
    currentFullName: row.current_full_name || null,
    requestedFullName: row.requested_full_name || null,
    currentJobTitle: row.current_job_title || null,
    requestedJobTitle: row.requested_job_title || null,
    currentCompanyName: row.current_company_name || null,
    requestedCompanyName: row.requested_company_name || null,
    currentEducationLevel: row.current_education_level || null,
    requestedEducationLevel: row.requested_education_level || null,
    currentSchoolName: row.current_school_name || null,
    requestedSchoolName: row.requested_school_name || null,
    message: row.message || null,
    attachmentFile: await signedStorageLink(row.attachment_file_path || null),
    attachmentFileName: row.attachment_file_name || null,
    attachmentContentType: row.attachment_content_type || null,
    attachmentSource: row.attachment_source || null,
    adminNotes: row.admin_notes || null,
    reviewedAt: row.reviewed_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    profile,
  };
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

function cleanText(value?: string | null) {
  const trimmed = String(value || "").trim();
  return trimmed.length > 0 ? trimmed : null;
}

function requestTypeLabel(type: ProfileChangeRequestType) {
  if (type === "legal_name") return "Legal name update";
  if (type === "work") return "Job details update";
  return "Education details update";
}
