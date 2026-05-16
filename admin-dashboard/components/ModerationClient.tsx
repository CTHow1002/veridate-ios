"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { ModeratedUser } from "@/lib/types";

type ModerationAction = "update-ban" | "unban" | "update-warning" | "clear-warning";

export default function ModerationClient() {
  const router = useRouter();
  const [users, setUsers] = useState<ModeratedUser[]>([]);
  const [error, setError] = useState("");
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    void loadUsers();
  }, []);

  async function loadUsers() {
    setError("");
    setIsLoading(true);

    try {
      const response = await fetch("/api/moderation");
      const result = (await response.json()) as { users?: ModeratedUser[]; error?: string };

      if (response.status === 401) {
        router.replace("/login");
        return;
      }

      if (!response.ok) {
        throw new Error(result.error || "Could not load moderation list.");
      }

      setUsers(result.users || []);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Could not load moderation list.");
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
    ? "Loading moderated users..."
    : users.length === 1
      ? "1 moderated user"
      : `${users.length} moderated users`;

  return (
    <>
      <header className="topbar">
        <div>
          <p className="eyebrow">VeriDate Admin</p>
          <h1>Moderation List</h1>
        </div>
        <div className="topbar-actions">
          <Link className="nav-link" href="/dashboard">
            Verification
          </Link>
          <Link className="nav-link" href="/dashboard/reports">
            Reports
          </Link>
          <Link className="nav-link" href="/dashboard/profile-changes">
            Profile Changes
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
            <h2>Bans & Warnings</h2>
            <p>{summaryText}</p>
          </div>
          <button className="secondary-button" onClick={loadUsers}>
            Refresh
          </button>
        </section>

        {error ? <section className="error-banner">{error}</section> : null}

        <section className="submissions-list">
          {!isLoading && users.length === 0 ? (
            <div className="empty-state">No banned or warned users.</div>
          ) : null}
          {users.map((user) => (
            <ModerationCard key={user.id} user={user} onUpdated={loadUsers} />
          ))}
        </section>
      </main>
    </>
  );
}

function ModerationCard({
  user,
  onUpdated,
}: {
  user: ModeratedUser;
  onUpdated: () => Promise<void>;
}) {
  const [moderationNotes, setModerationNotes] = useState(user.banMessage || user.warningMessage || "");
  const [warningDays, setWarningDays] = useState(7);
  const [banDays, setBanDays] = useState(7);
  const [error, setError] = useState("");
  const [isUpdating, setIsUpdating] = useState(false);

  async function update(action: ModerationAction) {
    setError("");
    setIsUpdating(true);

    try {
      const response = await fetch(`/api/moderation/${user.id}/action`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, moderationNotes, warningDays, banDays }),
      });
      const result = (await response.json()) as { error?: string };

      if (!response.ok) {
        throw new Error(result.error || "Could not update moderation status.");
      }

      await onUpdated();
    } catch (updateError) {
      setError(updateError instanceof Error ? updateError.message : "Could not update moderation status.");
    } finally {
      setIsUpdating(false);
    }
  }

  return (
    <article className="submission-card moderation-card">
      <div className="submission-main">
        <div className="identity-block">
          <span className={`status-dot ${user.isBanned ? "danger-dot" : ""}`} />
          <div>
            <div className="identity-title-row">
              <h3>{user.fullName || "Unnamed user"}</h3>
              <span className={`status-pill status-${user.status}`}>{user.status}</span>
            </div>
            <p>{user.id}</p>
          </div>
        </div>

        <dl className="profile-grid moderation-grid">
          <div>
            <dt>Verification</dt>
            <dd>{user.verificationStatus || "Not verified"}</dd>
          </div>
          <div>
            <dt>Ban Until</dt>
            <dd>{formatDateTime(user.banUntil)}</dd>
          </div>
          <div>
            <dt>Warned At</dt>
            <dd>{formatDateTime(user.warnedAt)}</dd>
          </div>
          <div>
            <dt>Warning Until</dt>
            <dd>{formatDateTime(user.warningUntil)}</dd>
          </div>
          <div>
            <dt>Latest Report</dt>
            <dd>{user.latestReportReason || "No linked report"}</dd>
          </div>
        </dl>

        <div className="moderation-details">
          <ModerationDetail title="Ban Message" value={user.banMessage} />
          <ModerationDetail title="Ban Details" value={user.banDetails} />
          <ModerationDetail title="Warning Message" value={user.warningMessage} />
          <ModerationDetail title="Warning Details" value={user.warningDetails} />
          <ModerationDetail title="Latest Report Notes" value={user.latestReportNotes} />
        </div>
      </div>

      <div className="review-panel">
        <textarea
          value={moderationNotes}
          onChange={(event) => setModerationNotes(event.target.value)}
          placeholder="Ban message, warning message, or moderation notes"
        />
        <DurationControls
          warningDays={warningDays}
          banDays={banDays}
          onWarningDaysChange={setWarningDays}
          onBanDaysChange={setBanDays}
        />
        <div className="action-row moderation-actions">
          <button className="secondary-button" disabled={isUpdating} onClick={() => update("update-ban")}>
            {user.isBanned ? "Adjust Ban" : "Ban User"}
          </button>
          <button className="secondary-button" disabled={isUpdating} onClick={() => update("update-warning")}>
            {user.warningMessage || user.warnedAt ? "Adjust Warning" : "Warn User"}
          </button>
          {user.isBanned ? (
            <button className="danger-button" disabled={isUpdating} onClick={() => update("unban")}>
              Unban
            </button>
          ) : null}
          {user.warningMessage || user.warnedAt ? (
            <button className="secondary-button" disabled={isUpdating} onClick={() => update("clear-warning")}>
              Clear Warning
            </button>
          ) : null}
        </div>
        <p className="form-error">{error}</p>
      </div>
    </article>
  );
}

function DurationControls({
  warningDays,
  banDays,
  onWarningDaysChange,
  onBanDaysChange,
}: {
  warningDays: number;
  banDays: number;
  onWarningDaysChange: (value: number) => void;
  onBanDaysChange: (value: number) => void;
}) {
  return (
    <div className="duration-grid">
      <label className="duration-field warning-duration">
        <span>Warning notice duration</span>
        <small>Show warning every app open for this many days</small>
        <input
          type="number"
          min="1"
          max="365"
          value={warningDays}
          onChange={(event) => onWarningDaysChange(Number(event.target.value))}
        />
      </label>
      <label className="duration-field">
        <span>Ban duration</span>
        <small>Restrict account access for this many days</small>
        <input
          type="number"
          min="1"
          max="365"
          value={banDays}
          onChange={(event) => onBanDaysChange(Number(event.target.value))}
        />
      </label>
    </div>
  );
}

function ModerationDetail({ title, value }: { title: string; value: string | null }) {
  if (!value) return null;

  return (
    <div className="report-details">
      <dt>{title}</dt>
      <dd>{value}</dd>
    </div>
  );
}

function formatDateTime(value: string | null) {
  if (!value) return "Not set";
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}
