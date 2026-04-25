export type Profile = {
  id: string;
  full_name?: string | null;
  date_of_birth?: string | null;
  job_title?: string | null;
  company_name?: string | null;
  education_level?: string | null;
  school_name?: string | null;
};

export type SignedFile = {
  path: string;
  url: string;
};

export type PendingSubmission = {
  id: string;
  userId: string;
  submittedAt: string | null;
  profile: Profile;
  files: {
    selfie: SignedFile | null;
    idDocument: SignedFile | null;
    jobProof: SignedFile | null;
    educationProof: SignedFile | null;
  };
};
