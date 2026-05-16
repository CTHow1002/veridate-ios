import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

Deno.serve(async (req) => {
  try {
    const payload = await req.json();

    console.log("Incoming push payload:", payload);

    const record = payload.record ?? payload.new ?? payload;
    const messageId = record.id;
    const matchId = record.match_id;
    const senderId = record.sender_id;
    const body = record.body ?? "New message";

    const { data: match, error: matchError } = await supabase
  .from("matches")
  .select("id,user_one_id,user_two_id")
  .eq("id", matchId)
  .single();

if (matchError || !match) {
  console.error("Match lookup failed:", { matchId, matchError });
  throw new Error("Match not found");
}

const receiverId =
  match.user_one_id === senderId ? match.user_two_id : match.user_one_id;

    const { data: sender } = await supabase
      .from("profiles")
      .select("full_name")
      .eq("id", senderId)
      .single();

    const { data: tokens, error: tokenError } = await supabase
      .from("user_push_tokens")
      .select("token")
      .eq("user_id", receiverId)
      .eq("platform", "ios");

    if (tokenError) {
      throw tokenError;
    }

    console.log("Receiver:", receiverId);
    console.log("Tokens:", tokens?.length ?? 0);

    // APNs sending will be added in next step.
    // For now this confirms DB trigger/function works.

    return new Response(
      JSON.stringify({
        ok: true,
        messageId,
        receiverId,
        tokenCount: tokens?.length ?? 0,
        preview: body.slice(0, 80),
        senderName: sender?.full_name ?? "Someone",
      }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("send-chat-push error:", error);

    return new Response(
      JSON.stringify({
        ok: false,
        error: String(error),
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});