"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

const categories = [
  "announcement",
  "verification",
  "profile_change",
  "moderation",
  "safety",
  "account",
  "feature",
  "system",
] as const;

export default function AnnouncementsClient() {
  const router = useRouter();
  const [audience, setAudience] = useState<"all" | "user">("all");
  const [userId, setUserId] = useState("");
  const [category, setCategory] = useState<(typeof categories)[number]>("announcement");
  const [title, setTitle] = useState("");
  const [message, setMessage] = useState("");
  const [expiresAt, setExpiresAt] = useState("");
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [isSending, setIsSending] = useState(false);

  async function logout() {
    await fetch("/api/logout", { method: "POST" });
    router.replace("/login");
    router.refresh();
  }

  async function send() {
    setError("");
    setNotice("");
    setIsSending(true);

    try {
      const response = await fetch("/api/announcements", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          audience,
          userId,
          category,
          title,
          message,
          expiresAt: expiresAt ? new Date(expiresAt).toISOString() : null,
        }),
      });
      const result = (await response.json()) as { count?: number; error?: string };

      if (response.status === 401) {
        router.replace("/login");
        return;
      }

      if (!response.ok) {
        throw new Error(result.error || "Could not send announcement.");
      }

      setNotice(`Sent to ${result.count || 0} user${result.count === 1 ? "" : "s"}.`);
      setTitle("");
      setMessage("");
      setExpiresAt("");
      if (audience === "user") setUserId("");
    } catch (sendError) {
      setError(sendError instanceof Error ? sendError.message : "Could not send announcement.");
    } finally {
      setIsSending(false);
    }
  }

  return (
    <>
      <header className="topbar">
        <div>
          <p className="eyebrow">VeriDate Admin</p>
          <h1>Announcements</h1>
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
            <h2>Send App Notification</h2>
            <p>Deliver announcement or account notice into users&apos; notification center.</p>
          </div>
        </section>

        {error ? <section className="error-banner">{error}</section> : null}
        {notice ? <section className="success-banner">{notice}</section> : null}

        <section className="announcement-panel">
          <div className="announcement-grid">
            <label>
              Audience
              <select value={audience} onChange={(event) => setAudience(event.target.value as "all" | "user")}>
                <option value="all">All active users</option>
                <option value="user">Specific user ID</option>
              </select>
            </label>

            <label>
              Category
              <select value={category} onChange={(event) => setCategory(event.target.value as (typeof categories)[number])}>
                {categories.map((item) => (
                  <option key={item} value={item}>
                    {categoryLabel(item)}
                  </option>
                ))}
              </select>
            </label>

            {audience === "user" ? (
              <label className="announcement-full">
                User ID
                <input value={userId} onChange={(event) => setUserId(event.target.value)} placeholder="Supabase profile id" />
              </label>
            ) : null}

            <label className="announcement-full">
              Title
              <input value={title} onChange={(event) => setTitle(event.target.value)} placeholder="Short notification title" />
            </label>

            <label className="announcement-full">
              Message
              <textarea value={message} onChange={(event) => setMessage(event.target.value)} placeholder="Notification message" />
            </label>

            <label>
              Expire after
              <input type="datetime-local" value={expiresAt} onChange={(event) => setExpiresAt(event.target.value)} />
            </label>
          </div>

          <div className="action-row announcement-actions">
            <button className="secondary-button" type="button" onClick={() => router.push("/dashboard")}>
              Cancel
            </button>
            <button disabled={isSending} type="button" onClick={send}>
              {isSending ? "Sending..." : "Send Notification"}
            </button>
          </div>
        </section>
      </main>
    </>
  );
}

function categoryLabel(category: string) {
  return category
    .split("_")
    .map((part) => part[0].toUpperCase() + part.slice(1))
    .join(" ");
}
