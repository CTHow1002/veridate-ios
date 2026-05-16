import { NextResponse } from "next/server";
import { isAuthenticated } from "@/lib/admin-session";
import { getModeratedUsers } from "@/lib/moderation";

export const runtime = "nodejs";

export async function GET() {
  if (!(await isAuthenticated())) {
    return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  }

  try {
    const users = await getModeratedUsers();
    return NextResponse.json({ users });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not load moderation list.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
