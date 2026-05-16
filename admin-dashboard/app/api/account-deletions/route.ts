import { NextResponse } from "next/server";
import { isAuthenticated } from "@/lib/admin-session";
import { getAccountDeletionRequests } from "@/lib/account-deletions";

export const runtime = "nodejs";

export async function GET() {
  if (!(await isAuthenticated())) {
    return NextResponse.json({ error: "Not signed in." }, { status: 401 });
  }

  try {
    const requests = await getAccountDeletionRequests();
    return NextResponse.json({ requests });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not load account deletion requests.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
