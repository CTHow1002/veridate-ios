"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { SafetyReport } from "@/lib/types";

type ReportAction = "dismiss" | "warn" | "ban";

export default function ReportsClient() {
  const router = useRouter();
  const [reports, setReports] = useState<SafetyReport[]>([]);
  const [error, setError] = useState("");
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    void loadReports();
  }, []);

  async function loadReports() {
    setError("");
    setIsLoading(true);

    try {
      const response = await fetch("/api/reports");
      const result = (await response.json()) as { reports?: SafetyReport[]; error?: string };

      if (response.status === 401) {
        router.replace("/login");
        return;
      }

      if (!response.ok) {
        throw new Error(result.error || "Could not load reports.");
      }

      setReports(result.reports || []);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Could not load reports.");
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
    ? "Loading safety reports..."
    : reports.length === 1
      ? "1 open report"
      : `${reports.length} open reports`;

  return (
    <>
      <header className="topbar">
        <div>
          <p className="eyebrow">VeriDate Admin</p>
          <h1>Safety Reports</h1>
        </div>
        <div className="topbar-actions">
          <Link className="nav-link" href="/dashboard">
            Verification
          </Link>
          <button className="secondary-button" onClick={logout}>
            Sign Out
          </button>
        </div>
      </header>

      <main className="dashboard">
        <section className="toolbar">
          <div>
            <h2>Open Reports</h2>
            <p>{summaryText}</p>
          </div>
          <button className="secondary-button" onClick={loadReports}>
            Refresh
          </button>
        </section>

        {error ? <section className="error-banner">{error}</section> : null}

        <section className="submissions-list">
          {!isLoading && reports.length === 0 ? <div className="empty-state">No open safety reports.</div> : null}
          {reports.map((report) => (
            <ReportCard key={report.id} report={report} onReviewed={loadReports} />
          ))}
        </section>
      </main>
    </>
  );
}

function ReportCard({
  report,
  onReviewed,
}: {
  report: SafetyReport;
  onReviewed: () => Promise<void>;
}) {
  const [moderationNotes, setModerationNotes] = useState("");
  const [banDays, setBanDays] = useState(7);
  const [error, setError] = useState("");
  const [isReviewing, setIsReviewing] = useState(false);

  async function review(action: ReportAction) {
    setError("");
    setIsReviewing(true);

    try {
      const response = await fetch(`/api/reports/${report.id}/action`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, moderationNotes, banDays }),
      });
      const result = (await response.json()) as { error?: string };

      if (!response.ok) {
        throw new Error(result.error || "Could not review report.");
      }

      await onReviewed();
    } catch (reviewError) {
      setError(reviewError instanceof Error ? reviewError.message : "Could not review report.");
    } finally {
      setIsReviewing(false);
    }
  }

  return (
    <article className="submission-card report-card">
      <div className="submission-main">
        <div className="identity-block">
          <span className="status-dot danger-dot" />
          <div>
            <h3>{report.reason}</h3>
            <p>{formatDateTime(report.createdAt)}</p>
          </div>
        </div>

        <dl className="profile-grid report-grid">
          <div>
            <dt>Reported User</dt>
            <dd>{profileLabel(report.reportedUser, report.reportedUserId)}</dd>
          </div>
          <div>
            <dt>Reporter</dt>
            <dd>{profileLabel(report.reporter, report.reporterUserId)}</dd>
          </div>
          <div>
            <dt>Match</dt>
            <dd>{report.matchId || "Not linked"}</dd>
          </div>
        </dl>

        <div className="report-details">
          <dt>Details</dt>
          <dd>{report.details || "No extra details provided."}</dd>
        </div>

        <div className="report-details">
          <dt>Proof</dt>
          <dd>
            {report.proofFile ? (
              <a href={report.proofFile.url} title={report.proofFile.path} target="_blank" rel="noreferrer">
                Open proof
              </a>
            ) : (
              "No proof attached."
            )}
          </dd>
        </div>
      </div>

      <div className="review-panel">
        <textarea
          value={moderationNotes}
          onChange={(event) => setModerationNotes(event.target.value)}
          placeholder="Warning/ban message and moderation notes"
        />
        <label className="compact-label">
          Ban duration in days
          <input
            type="number"
            min="1"
            max="365"
            value={banDays}
            onChange={(event) => setBanDays(Number(event.target.value))}
          />
        </label>
        <div className="action-row report-actions">
          <button className="secondary-button" disabled={isReviewing} onClick={() => review("dismiss")}>
            Dismiss
          </button>
          <button className="secondary-button" disabled={isReviewing} onClick={() => review("warn")}>
            Warn
          </button>
          <button className="danger-button" disabled={isReviewing} onClick={() => review("ban")}>
            Ban
          </button>
        </div>
        <p className="form-error">{error}</p>
      </div>
    </article>
  );
}

function profileLabel(profile: SafetyReport["reporter"], fallbackId: string) {
  const name = profile.full_name || "Unnamed user";
  const status = profile.is_banned ? "Banned" : profile.verification_status || "Profile";
  return `${name} - ${status} - ${fallbackId}`;
}

function formatDateTime(value: string | null) {
  if (!value) return "Timestamp missing";
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}
