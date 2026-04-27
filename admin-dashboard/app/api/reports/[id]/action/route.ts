import { NextResponse } from "next/server";
import { isAuthenticated } from "@/lib/admin-session";
import { moderateReport, type ReportAction } from "@/lib/reports";

export const runtime = "nodejs";

type RouteContext = {
  params: Promise<{
    id: string;
  }>;
};

const actions = new Set<ReportAction>(["dismiss", "warn", "ban"]);

export async function POST(request: Request, context: RouteContext) {
  if (!(await isAuthenticated())) {
    return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  }

  const body = await request.json().catch(() => ({}));
  const action = String(body.action || "") as ReportAction;
  const moderationNotes = String(body.moderationNotes || "").trim();
  const banDays = Number(body.banDays || 0);

  if (!actions.has(action)) {
    return NextResponse.json({ error: "Choose a valid moderation action." }, { status: 400 });
  }

  try {
    const { id } = await context.params;
    await moderateReport(id, action, { moderationNotes, banDays });
    return NextResponse.json({ ok: true, action });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not review report.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
