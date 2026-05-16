"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import type { AccountDeletionRequest } from "@/lib/types";

export default function AccountDeletionsClient() {
  const router = useRouter();
  const [requests, setRequests] = useState<AccountDeletionRequest[]>([]);
  const [error, setError] = useState("");
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    void loadRequests();
  }, []);

  async function loadRequests() {
    setError("");
    setIsLoading(true);

    try {
      const response = await fetch("/api/account-deletions");
      const result = (await response.json()) as { requests?: AccountDeletionRequest[]; error?: string };

      if (response.status === 401) {
        router.replace("/login");
        return;
      }

      if (!response.ok) {
        throw new Error(result.error || "Could not load deletion requests.");
      }

      setRequests(result.requests || []);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Could not load deletion requests.");
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
    ? "Loading account deletion queue..."
    : requests.length === 1
      ? "1 recent request"
      : `${requests.length} recent requests`;

  return (
    <>
      <header className="topbar">
        <div>
          <p className="eyebrow">VeriDate Admin</p>
          <h1>Account Deletions</h1>
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
          <Link className="nav-link" href="/dashboard/profile-changes">
            Profile Changes
          </Link>
          <button className="secondary-button" onClick={logout}>
            Sign Out
          </button>
        </div>
      </header>

      <main className="dashboard">
        <section className="toolbar">
          <div>
            <h2>Deletion Queue</h2>
            <p>{summaryText}</p>
          </div>
          <button className="secondary-button" onClick={loadRequests}>
            Refresh
          </button>
        </section>

        {error ? <section className="error-banner">{error}</section> : null}

        <section className="submissions-list">
          {!isLoading && requests.length === 0 ? (
            <div className="empty-state">No account deletion requests yet.</div>
          ) : null}
          {requests.map((request) => (
            <DeletionRequestCard key={request.id} request={request} />
          ))}
        </section>
      </main>
    </>
  );
}

function DeletionRequestCard({ request }: { request: AccountDeletionRequest }) {
  const profileName = request.profile?.full_name || "Deleted profile";
  const isActive = request.status === "pending" || request.status === "processing";

  return (
    <article className="submission-card deletion-card">
      <div className="submission-main">
        <div className="identity-block">
          <span className={`status-dot ${isActive ? "danger-dot" : ""}`} />
          <div>
            <h3>{profileName}</h3>
            <p>{request.userId}</p>
          </div>
        </div>

        <dl className="profile-grid deletion-grid">
          <div>
            <dt>Status</dt>
            <dd>
              <span className={`status-pill status-${request.status}`}>{request.status}</span>
            </dd>
          </div>
          <div>
            <dt>Requested</dt>
            <dd>{formatDateTime(request.requestedAt)}</dd>
          </div>
          <div>
            <dt>Scheduled Delete</dt>
            <dd>{formatDateTime(request.scheduledDeleteAt)}</dd>
          </div>
          <div>
            <dt>Processed</dt>
            <dd>{formatDateTime(request.processedAt)}</dd>
          </div>
        </dl>

        {request.errorMessage ? (
          <div className="report-details">
            <dt>Error</dt>
            <dd>{request.errorMessage}</dd>
          </div>
        ) : null}
      </div>
    </article>
  );
}

function formatDateTime(value: string | null) {
  if (!value) return "Not yet";
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}
