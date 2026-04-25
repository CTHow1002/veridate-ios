import { NextResponse } from "next/server";
import { isAuthenticated } from "@/lib/admin-session";
import { getPendingSubmissions } from "@/lib/submissions";

export const runtime = "nodejs";

export async function GET() {
  if (!(await isAuthenticated())) {
    return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  }

  try {
    const submissions = await getPendingSubmissions();
    return NextResponse.json({ submissions });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not load submissions.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
