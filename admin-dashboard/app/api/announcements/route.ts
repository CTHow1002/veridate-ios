import { NextResponse } from "next/server";
import { isAuthenticated } from "@/lib/admin-session";
import { sendAnnouncement, type NotificationCategory } from "@/lib/notifications";

export const runtime = "nodejs";

export async function POST(request: Request) {
  if (!(await isAuthenticated())) {
    return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  }

  const body = (await request.json().catch(() => ({}))) as {
    audience?: string;
    userId?: string;
    category?: string;
    title?: string;
    message?: string;
    expiresAt?: string | null;
  };

  const audience = body.audience === "user" ? "user" : "all";
  const userId = String(body.userId || "").trim();
  const category = String(body.category || "announcement") as NotificationCategory;
  const title = String(body.title || "").trim();
  const message = String(body.message || "").trim();
  const expiresAt = String(body.expiresAt || "").trim() || null;

  if (audience === "user" && !userId) {
    return NextResponse.json({ error: "Enter a user id for targeted announcement." }, { status: 400 });
  }

  try {
    const result = await sendAnnouncement({
      audience,
      userId: audience === "user" ? userId : undefined,
      category,
      title,
      body: message,
      expiresAt,
    });

    return NextResponse.json({ ok: true, count: result.count });
  } catch (error) {
    const messageText = error instanceof Error ? error.message : "Could not send announcement.";
    return NextResponse.json({ error: messageText }, { status: 500 });
  }
}
