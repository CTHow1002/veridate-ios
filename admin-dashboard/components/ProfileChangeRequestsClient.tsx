"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { ProfileChangeRequest } from "@/lib/types";

export default function ProfileChangeRequestsClient() {
  const router = useRouter();
  const [requests, setRequests] = useState<ProfileChangeRequest[]>([]);
  const [error, setError] = useState("");
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    void loadRequests();
  }, []);

  async function loadRequests() {
    setError("");
    setIsLoading(true);

    try {
      const response = await fetch("/api/profile-change-requests");
      const result = (await response.json()) as { requests?: ProfileChangeRequest[]; error?: string };

      if (response.status === 401) {
        router.replace("/login");
        return;
      }

      if (!response.ok) {
        throw new Error(result.error || "Could not load profile change requests.");
      }

      setRequests(result.requests || []);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Could not load profile change requests.");
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
    ? "Loading profile change requests..."
    : requests.length === 1
      ? "1 pending request"
      : `${requests.length} pending requests`;

  return (
    <>
      <header className="topbar">
        <div>
          <p className="eyebrow">VeriDate Admin</p>
          <h1>Profile Changes</h1>
        </div>
        <div className="topbar-actions">
          <Link className="nav-link" href="/dashboard">
            Verifications
          </Link>
          <Link className="nav-link" href="/dashboard/reports">
            Reports
          </Link>
          <Link className="nav-link" href="/dashboard/moderation">
            Moderation
          </Link>
          <Link className="nav-link" href="/dashboard/deletions">
            Deletions
          </Link>
          <button className="secondary-button" onClick={logout}>
            Sign Out
          </button>
        </div>
      </header>

      <main className="dashboard">
        <section className="toolbar">
          <div>
            <h2>Pending Profile Changes</h2>
            <p>{summaryText}</p>
          </div>
          <button className="secondary-button" onClick={loadRequests}>
            Refresh
          </button>
        </section>

        {error ? <section className="error-banner">{error}</section> : null}

        <section className="submissions-list">
          {!isLoading && requests.length === 0 ? (
            <div className="empty-state">No pending profile change requests.</div>
          ) : null}
          {requests.map((request) => (
            <ProfileChangeRequestCard key={request.id} request={request} onReviewed={loadRequests} />
          ))}
        </section>
      </main>
    </>
  );
}

function ProfileChangeRequestCard({
  request,
  onReviewed,
}: {
  request: ProfileChangeRequest;
  onReviewed: () => Promise<void>;
}) {
  const [adminNotes, setAdminNotes] = useState("");
  const [error, setError] = useState("");
  const [isReviewing, setIsReviewing] = useState(false);

  async function review(action: "approve" | "reject") {
    setError("");
    setIsReviewing(true);

    try {
      const response = await fetch(`/api/profile-change-requests/${request.id}/action`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, adminNotes }),
      });
      const result = (await response.json()) as { error?: string };

      if (!response.ok) {
        throw new Error(result.error || `Could not ${action} request.`);
      }

      await onReviewed();
    } catch (reviewError) {
      setError(reviewError instanceof Error ? reviewError.message : "Could not review profile change request.");
    } finally {
      setIsReviewing(false);
    }
  }

  return (
    <article className="submission-card moderation-card">
      <div className="submission-main">
        <div className="identity-block">
          <span className="status-dot" />
          <div>
            <h3>{request.profile?.full_name || request.currentFullName || "Unnamed user"}</h3>
            <p>{requestLabel(request.requestType)} - {formatDateTime(request.createdAt)}</p>
          </div>
        </div>

        <dl className="profile-grid moderation-grid">
          {changeRows(request).map((row) => (
            <div key={row.label}>
              <dt>{row.label}</dt>
              <dd>
                <span className="muted-value">{row.current || "Not provided"}</span>
                <span className="change-arrow"> -&gt; </span>
                <strong>{row.requested || "Clear value"}</strong>
              </dd>
            </div>
          ))}
          <div>
            <dt>User ID</dt>
            <dd>{request.userId}</dd>
          </div>
          <div>
            <dt>Status</dt>
            <dd>
              <span className={`status-pill status-${request.status}`}>{request.status}</span>
            </dd>
          </div>
        </dl>

        {request.message ? (
          <div className="report-details">
            <dt>User note</dt>
            <dd>{request.message}</dd>
          </div>
        ) : null}

        {request.attachmentFile ? (
          <div className="file-grid">
            <a href={request.attachmentFile.url} title={request.attachmentFile.path} target="_blank" rel="noreferrer">
              {request.attachmentFileName || "Open attached proof"}
            </a>
          </div>
        ) : null}
      </div>

      <div className="review-panel">
        <textarea
          value={adminNotes}
          onChange={(event) => setAdminNotes(event.target.value)}
          placeholder="Admin notes"
        />
        <div className="action-row">
          <button className="danger-button" disabled={isReviewing} onClick={() => review("reject")}>
            Reject
          </button>
          <button disabled={isReviewing} onClick={() => review("approve")}>
            Approve & Apply
          </button>
        </div>
        <p className="form-error">{error}</p>
      </div>
    </article>
  );
}

function changeRows(request: ProfileChangeRequest) {
  if (request.requestType === "legal_name") {
    return [
      {
        label: "Legal Name",
        current: request.currentFullName,
        requested: request.requestedFullName,
      },
    ];
  }

  if (request.requestType === "work") {
    return [
      {
        label: "Job Title",
        current: request.currentJobTitle,
        requested: request.requestedJobTitle,
      },
      {
        label: "Company",
        current: request.currentCompanyName,
        requested: request.requestedCompanyName,
      },
    ];
  }

  return [
    {
      label: "Education Level",
      current: request.currentEducationLevel,
      requested: request.requestedEducationLevel,
    },
    {
      label: "School",
      current: request.currentSchoolName,
      requested: request.requestedSchoolName,
    },
  ];
}

function requestLabel(type: ProfileChangeRequest["requestType"]) {
  if (type === "legal_name") return "Legal name update";
  if (type === "work") return "Work details update";
  return "Education update";
}

function formatDateTime(value: string | null) {
  if (!value) return "Submitted date missing";
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}
