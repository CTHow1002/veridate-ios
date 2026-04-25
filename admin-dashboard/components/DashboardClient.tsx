"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { PendingSubmission } from "@/lib/types";

export default function DashboardClient() {
  const router = useRouter();
  const [submissions, setSubmissions] = useState<PendingSubmission[]>([]);
  const [error, setError] = useState("");
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    void loadSubmissions();
  }, []);

  async function loadSubmissions() {
    setError("");
    setIsLoading(true);

    try {
      const response = await fetch("/api/submissions");
      const result = (await response.json()) as { submissions?: PendingSubmission[]; error?: string };

      if (response.status === 401) {
        router.replace("/login");
        return;
      }

      if (!response.ok) {
        throw new Error(result.error || "Could not load submissions.");
      }

      setSubmissions(result.submissions || []);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Could not load submissions.");
    } finally {
      setIsLoading(false);
    }
  }

  async function logout() {
    await fetch("/api/logout", { method: "POST" });
    router.replace("/login");
    router.refresh();
  }

  const summaryText = isLoading
    ? "Loading pending reviews..."
    : submissions.length === 1
      ? "1 pending submission"
      : `${submissions.length} pending submissions`;

  return (
    <>
      <header className="topbar">
        <div>
          <p className="eyebrow">VeriDate Admin</p>
          <h1>Verification Review</h1>
        </div>
        <button className="secondary-button" onClick={logout}>
          Sign Out
        </button>
      </header>

      <main className="dashboard">
        <section className="toolbar">
          <div>
            <h2>Pending Submissions</h2>
            <p>{summaryText}</p>
          </div>
          <button className="secondary-button" onClick={loadSubmissions}>
            Refresh
          </button>
        </section>

        {error ? <section className="error-banner">{error}</section> : null}

        <section className="submissions-list">
          {!isLoading && submissions.length === 0 ? (
            <div className="empty-state">No pending verification submissions.</div>
          ) : null}
          {submissions.map((submission) => (
            <SubmissionCard key={submission.id} submission={submission} onReviewed={loadSubmissions} />
          ))}
        </section>
      </main>
    </>
  );
}

function SubmissionCard({
  submission,
  onReviewed,
}: {
  submission: PendingSubmission;
  onReviewed: () => Promise<void>;
}) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState("");
  const [isReviewing, setIsReviewing] = useState(false);

  async function review(action: "approve" | "reject") {
    setError("");
    setIsReviewing(true);

    try {
      const response = await fetch(`/api/submissions/${submission.id}/${action}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ rejectionReason: reason }),
      });
      const result = (await response.json()) as { error?: string };

      if (!response.ok) {
        throw new Error(result.error || `Could not ${action} submission.`);
      }

      await onReviewed();
    } catch (reviewError) {
      setError(reviewError instanceof Error ? reviewError.message : "Could not review submission.");
    } finally {
      setIsReviewing(false);
    }
  }

  return (
    <article className="submission-card">
      <div className="submission-main">
        <div className="identity-block">
          <span className="status-dot" />
          <div>
            <h3>{submission.profile.full_name || "Unnamed user"}</h3>
            <p>{formatDateTime(submission.submittedAt)}</p>
          </div>
        </div>

        <dl className="profile-grid">
          <div>
            <dt>Date of Birth</dt>
            <dd>{submission.profile.date_of_birth || "Not provided"}</dd>
          </div>
          <div>
            <dt>Work</dt>
            <dd>{joinParts([submission.profile.job_title, submission.profile.company_name])}</dd>
          </div>
          <div>
            <dt>Education</dt>
            <dd>{joinParts([submission.profile.education_level, submission.profile.school_name])}</dd>
          </div>
        </dl>

        <div className="file-grid">
          <VideoReview file={submission.files.selfieVideo} prompt={submission.livenessPrompt} />
          <FileLink label="ID Document" file={submission.files.idDocument} />
          <FileLink label="Job Proof" file={submission.files.jobProof} />
          <FileLink label="Education Proof" file={submission.files.educationProof} />
        </div>
      </div>

      <div className="review-panel">
        <textarea
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          placeholder="Rejection reason"
        />
        <div className="action-row">
          <button className="danger-button" disabled={isReviewing} onClick={() => review("reject")}>
            Reject
          </button>
          <button disabled={isReviewing} onClick={() => review("approve")}>
            Approve
          </button>
        </div>
        <p className="form-error">{error}</p>
      </div>
    </article>
  );
}

function VideoReview({
  file,
  prompt,
}: {
  file: PendingSubmission["files"]["selfieVideo"];
  prompt: string | null;
}) {
  if (!file?.url) {
    return <span className="missing-file video-review">Video missing</span>;
  }

  return (
    <div className="video-review">
      <video controls preload="metadata" src={file.url} />
      <p>{prompt || file.prompt || "No liveness prompt saved."}</p>
      <a href={file.url} title={file.path} target="_blank" rel="noreferrer">
        Open video
      </a>
    </div>
  );
}

function FileLink({ label, file }: { label: string; file: PendingSubmission["files"]["idDocument"] }) {
  if (!file?.url) {
    return <span className="missing-file">{label} missing</span>;
  }

  return (
    <a href={file.url} title={file.path} target="_blank" rel="noreferrer">
      {label}
    </a>
  );
}

function formatDateTime(value: string | null) {
  if (!value) return "Submitted date missing";
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

function joinParts(parts: Array<string | null | undefined>) {
  return parts.filter(Boolean).join(", ") || "Not provided";
}
