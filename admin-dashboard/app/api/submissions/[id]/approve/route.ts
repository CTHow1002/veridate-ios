import { NextResponse } from "next/server";
import { isAuthenticated } from "@/lib/admin-session";
import { reviewSubmission } from "@/lib/submissions";

export const runtime = "nodejs";

type RouteContext = {
  params: Promise<{
    id: string;
  }>;
};

export async function POST(_request: Request, context: RouteContext) {
  if (!(await isAuthenticated())) {
    return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  }

  try {
    const { id } = await context.params;
    await reviewSubmission(id, "verified");
    return NextResponse.json({ ok: true, status: "verified" });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not approve submission.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
