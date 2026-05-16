import { NextResponse } from "next/server";
import { isAuthenticated } from "@/lib/admin-session";
import { updateModeratedUser, type UserModerationAction } from "@/lib/moderation";

export const runtime = "nodejs";

type RouteContext = {
  params: Promise<{
    id: string;
  }>;
};

const actions = new Set<UserModerationAction>(["update-ban", "unban", "update-warning", "clear-warning"]);

export async function POST(request: Request, context: RouteContext) {
  if (!(await isAuthenticated())) {
    return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  }

  const body = await request.json().catch(() => ({}));
  const action = String(body.action || "") as UserModerationAction;
  const moderationNotes = String(body.moderationNotes || "").trim();
  const warningDays = Number(body.warningDays || 0);
  const banDays = Number(body.banDays || 0);

  if (!actions.has(action)) {
    return NextResponse.json({ error: "Choose a valid moderation action." }, { status: 400 });
  }

  try {
    const { id } = await context.params;
    await updateModeratedUser(id, { action, moderationNotes, warningDays, banDays });
    return NextResponse.json({ ok: true, action });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not update user moderation.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
