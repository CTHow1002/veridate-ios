import { NextResponse } from "next/server";
import { isAuthenticated } from "@/lib/admin-session";
import { getOpenReports } from "@/lib/reports";

export const runtime = "nodejs";

export async function GET() {
  if (!(await isAuthenticated())) {
    return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  }

  try {
    const reports = await getOpenReports();
    return NextResponse.json({ reports });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not load reports.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
