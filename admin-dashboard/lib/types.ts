export type Profile = {
  id: string;
  full_name?: string | null;
  date_of_birth?: string | null;
  job_title?: string | null;
  company_name?: string | null;
  education_level?: string | null;
  school_name?: string | null;
  verification_status?: string | null;
  is_banned?: boolean | null;
  ban_until?: string | null;
  ban_message?: string | null;
  ban_details?: string | null;
  warning_message?: string | null;
  warning_details?: string | null;
  warned_at?: string | null;
};

export type SignedFile = {
  path: string;
  url: string;
};

export type LivenessVideo = SignedFile & {
  prompt: string | null;
};

export type PendingSubmission = {
  id: string;
  userId: string;
  submittedAt: string | null;
  livenessPrompt: string | null;
  profile: Profile;
  files: {
    selfieVideo: LivenessVideo | null;
    idDocument: SignedFile | null;
    jobProof: SignedFile | null;
    educationProof: SignedFile | null;
  };
};

export type ReportStatus = "open" | "dismissed" | "warned" | "banned";

export type SafetyReport = {
  id: string;
  reporterUserId: string;
  reportedUserId: string;
  matchId: string | null;
  reason: string;
  details: string | null;
  proofFile: SignedFile | null;
  status: ReportStatus;
  moderationNotes: string | null;
  actionTaken: string | null;
  reviewedAt: string | null;
  createdAt: string | null;
  reporter: Profile;
  reportedUser: Profile;
};
