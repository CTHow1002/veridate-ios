import { NextResponse } from "next/server";
import { processDueAccountDeletions } from "@/lib/account-deletions";

export const runtime = "nodejs";

export async function GET(request: Request) {
  return processCronRequest(request);
}

export async function POST(request: Request) {
  return processCronRequest(request);
}

async function processCronRequest(request: Request) {
  const cronSecret = process.env.CRON_SECRET;
  const authHeader = request.headers.get("authorization") || "";
  const isVercelCron = request.headers.get("x-vercel-cron") === "1";

  if (cronSecret && authHeader !== `Bearer ${cronSecret}` && !isVercelCron) {
    return NextResponse.json({ error: "Unauthorized cron request." }, { status: 401 });
  }

  if (!cronSecret && !isVercelCron && process.env.NODE_ENV === "production") {
    return NextResponse.json({ error: "CRON_SECRET is required in production." }, { status: 401 });
  }

  try {
    const results = await processDueAccountDeletions();
    return NextResponse.json({
      ok: true,
      processed: results.length,
      results,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Could not process account deletions.";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
