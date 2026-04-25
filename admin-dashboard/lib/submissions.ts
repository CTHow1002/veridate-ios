import "server-only";

import { getSupabaseConfig } from "@/lib/config";
import { supabaseRequest } from "@/lib/supabase-admin";
import type { PendingSubmission, Profile, SignedFile } from "@/lib/types";

type VerificationSubmission = {
  id: string;
  user_id: string;
  submitted_at?: string | null;
  created_at?: string | null;
  selfie_file_path?: string | null;
  selfie_path?: string | null;
  selfie_file?: string | null;
  id_document_file_path?: string | null;
  id_document_path?: string | null;
  id_document_file?: string | null;
  job_proof_file_path?: string | null;
  job_proof_path?: string | null;
  job_proof_file?: string | null;
  education_proof_file_path?: string | null;
  education_proof_path?: string | null;
  education_proof_file?: string | null;
};

export async function getPendingSubmissions(): Promise<PendingSubmission[]> {
  const submissions = await supabaseRequest<VerificationSubmission[]>(
    "/rest/v1/verification_submissions?status=eq.pending&select=*&order=submitted_at.asc"
  );
  const userIds = [...new Set(submissions.map((submission) => submission.user_id).filter(Boolean))];
  const profilesById = await fetchProfilesById(userIds);

  return Promise.all(
    submissions.map(async (submission) => {
      const profile = profilesById.get(submission.user_id) || ({ id: submission.user_id } satisfies Profile);

      return {
        id: submission.id,
        userId: submission.user_id,
        submittedAt: submission.submitted_at || submission.created_at || null,
        profile,
        files: await signedFileLinks(submission),
      };
    })
  );
}

export async function reviewSubmission(id: string, status: "verified" | "rejected", rejectionReason?: string) {
  const [submission] = await supabaseRequest<VerificationSubmission[]>(
    `/rest/v1/verification_submissions?id=eq.${encodeURIComponent(id)}&select=*`
  );

  if (!submission) {
    throw new Error("Submission not found.");
  }

  await supabaseRequest(`/rest/v1/verification_submissions?id=eq.${encodeURIComponent(id)}`, {
    method: "PATCH",
    body: {
      status,
      rejection_reason: status === "rejected" ? rejectionReason : null,
      reviewed_at: new Date().toISOString(),
    },
  });

  await supabaseRequest(`/rest/v1/profiles?id=eq.${encodeURIComponent(submission.user_id)}`, {
    method: "PATCH",
    body: {
      verification_status: status,
    },
  });
}

async function fetchProfilesById(userIds: string[]) {
  if (userIds.length === 0) return new Map<string, Profile>();

  const profiles = await supabaseRequest<Profile[]>(
    `/rest/v1/profiles?id=in.(${userIds.join(",")})&select=id,full_name,date_of_birth,job_title,company_name,education_level,school_name`
  );

  return new Map(profiles.map((profile) => [profile.id, profile]));
}

async function signedFileLinks(submission: VerificationSubmission): Promise<PendingSubmission["files"]> {
  const [selfie, idDocument, jobProof, educationProof] = await Promise.all([
    signedStorageLink(firstValue([submission.selfie_file_path, submission.selfie_path, submission.selfie_file])),
    signedStorageLink(
      firstValue([submission.id_document_file_path, submission.id_document_path, submission.id_document_file])
    ),
    signedStorageLink(firstValue([submission.job_proof_file_path, submission.job_proof_path, submission.job_proof_file])),
    signedStorageLink(
      firstValue([
        submission.education_proof_file_path,
        submission.education_proof_path,
        submission.education_proof_file,
      ])
    ),
  ]);

  return {
    selfie,
    idDocument,
    jobProof,
    educationProof,
  };
}

async function signedStorageLink(path: string | null): Promise<SignedFile | null> {
  if (!path) return null;
  if (/^https?:\/\//i.test(path)) return { path, url: path };

  const safePath = path
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
    path,
    url: `${getSupabaseConfig().supabaseUrl}${response.signedURL}`,
  };
}

function firstValue(values: Array<string | null | undefined>) {
  return values.find(Boolean) || null;
}
