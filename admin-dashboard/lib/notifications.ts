import "server-only";

import { supabaseRequest } from "@/lib/supabase-admin";

export type NotificationCategory =
  | "announcement"
  | "verification"
  | "profile_change"
  | "moderation"
  | "safety"
  | "account"
  | "feature"
  | "system";

type NotificationInput = {
  userId: string;
  category: NotificationCategory;
  title: string;
  body: string;
  metadata?: Record<string, unknown>;
  actionUrl?: string | null;
  expiresAt?: string | null;
};

type AnnouncementInput = {
  audience: "all" | "user";
  userId?: string;
  category: NotificationCategory;
  title: string;
  body: string;
  expiresAt?: string | null;
};

type ProfileIdRow = {
  id: string;
};

const validCategories = new Set<NotificationCategory>([
  "announcement",
  "verification",
  "profile_change",
  "moderation",
  "safety",
  "account",
  "feature",
  "system",
]);

export async function createAppNotification(input: NotificationInput) {
  const title = cleanText(input.title);
  const body = cleanText(input.body);

  if (!input.userId) throw new Error("Notification user id missing.");
  if (!title) throw new Error("Notification title missing.");
  if (!body) throw new Error("Notification body missing.");

  try {
    await supabaseRequest("/rest/v1/app_notifications", {
      method: "POST",
      body: {
        user_id: input.userId,
        category: input.category,
        title,
        body,
        action_url: input.actionUrl || null,
        metadata: input.metadata || {},
        expires_at: input.expiresAt || null,
        created_by: "admin_dashboard",
      },
    });
  } catch (error) {
    console.warn("Could not create app notification:", error);
  }
}

export async function sendAnnouncement(input: AnnouncementInput) {
  const category = input.category;
  const title = cleanText(input.title);
  const body = cleanText(input.body);

  if (!validCategories.has(category)) throw new Error("Choose a valid announcement category.");
  if (!title) throw new Error("Enter an announcement title.");
  if (!body) throw new Error("Enter an announcement message.");

  const userIds =
    input.audience === "all"
      ? await fetchActiveUserIds()
      : input.userId
        ? [input.userId]
        : [];

  if (userIds.length === 0) {
    throw new Error("No notification recipients found.");
  }

  const rows = userIds.map((userId) => ({
    user_id: userId,
    category,
    title,
    body,
    expires_at: input.expiresAt || null,
    metadata: { audience: input.audience },
    created_by: "admin_dashboard",
  }));

  for (let index = 0; index < rows.length; index += 500) {
    await supabaseRequest("/rest/v1/app_notifications", {
      method: "POST",
      body: rows.slice(index, index + 500),
    });
  }

  return { count: userIds.length };
}

async function fetchActiveUserIds() {
  const rows = await supabaseRequest<ProfileIdRow[]>(
    "/rest/v1/profiles?or=(is_deactivated.is.null,is_deactivated.eq.false)&select=id&limit=10000"
  );

  return rows.map((row) => row.id);
}

function cleanText(value?: string | null) {
  const cleaned = String(value || "").trim();
  return cleaned || null;
}
