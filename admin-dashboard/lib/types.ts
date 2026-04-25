export type Profile = {
  id: string;
  full_name?: string | null;
  date_of_birth?: string | null;
  job_title?: string | null;
  company_name?: string | null;
  education_level?: string | null;
  school_name?: string | null;
  verification_status?: string | null;
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
