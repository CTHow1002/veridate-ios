import { NextResponse } from "next/server";
import { sessionCookieOptions, signSession } from "@/lib/admin-session";
import { getSessionConfig } from "@/lib/config";

export const runtime = "nodejs";

export async function POST(request: Request) {
  try {
    const body = await request.json().catch(() => ({}));
    const username = String(body.username || "");
    const password = String(body.password || "");
    const config = getSessionConfig();

    if (username !== config.adminUsername || password !== config.adminPassword) {
      return NextResponse.json({ error: "Incorrect admin username or password." }, { status: 401 });
    }

    const response = NextResponse.json({ ok: true });
    response.cookies.set("admin_session", signSession(username), sessionCookieOptions);
    return response;
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not sign in.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
