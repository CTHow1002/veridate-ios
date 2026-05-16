import { NextResponse, type NextRequest } from "next/server";
import { isAuthenticated } from "@/lib/admin-session";
import { reviewProfileChangeRequest, type ProfileChangeRequestAction } from "@/lib/profile-change-requests";

export const runtime = "nodejs";

type RouteContext = {
  params: Promise<{ id: string }>;
};

export async function POST(request: NextRequest, context: RouteContext) {
  if (!(await isAuthenticated())) {
    return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  }

  const { id } = await context.params;
  const body = (await request.json().catch(() => ({}))) as {
    action?: string;
    adminNotes?: string;
  };
  const action = body.action as ProfileChangeRequestAction;

  if (action !== "approve" && action !== "reject") {
    return NextResponse.json({ error: "Choose a valid review action." }, { status: 400 });
  }

  try {
    await reviewProfileChangeRequest(id, action, body.adminNotes);
    return NextResponse.json({ ok: true });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not review profile change request.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
