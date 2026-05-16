import { NextResponse } from "next/server";
import { isAuthenticated } from "@/lib/admin-session";
import { getProfileChangeRequests } from "@/lib/profile-change-requests";

export const runtime = "nodejs";

export async function GET() {
  if (!(await isAuthenticated())) {
    return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  }

  try {
    const requests = await getProfileChangeRequests();
    return NextResponse.json({ requests });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not load profile change requests.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
