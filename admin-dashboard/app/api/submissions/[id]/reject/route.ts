import { NextResponse } from "next/server";
import { isAuthenticated } from "@/lib/admin-session";
import { reviewSubmission } from "@/lib/submissions";

export const runtime = "nodejs";

type RouteContext = {
  params: Promise<{
    id: string;
  }>;
};

export async function POST(request: Request, context: RouteContext) {
  if (!(await isAuthenticated())) {
    return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  }

  const body = await request.json().catch(() => ({}));
  const rejectionReason = String(body.rejectionReason || "").trim();

  if (!rejectionReason) {
    return NextResponse.json({ error: "Enter a rejection reason." }, { status: 400 });
  }

  try {
    const { id } = await context.params;
    await reviewSubmission(id, "rejected", rejectionReason);
    return NextResponse.json({ ok: true, status: "rejected" });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not reject submission.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
