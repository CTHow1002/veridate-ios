import { createClient } from "@supabase/supabase-js";
import "dotenv/config";

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

async function uploadRandomProfilePhoto(userId, index) {
  try {
    const sources = [
      `https://i.pravatar.cc/300?img=${randomInt(1, 70)}`
    ];

    const imageUrl = sources[Math.floor(Math.random() * sources.length)];

    const res = await fetch(imageUrl);
    const buffer = await res.arrayBuffer();

    const filePath = `profiles/${userId}.jpg`;

    const { error } = await supabase.storage
      .from(process.env.PROFILE_BUCKET)
      .upload(filePath, buffer, {
        contentType: "image/jpeg",
        upsert: true
      });

    if (error) {
      console.error("Upload error:", userId, error.message);
      return null;
    }

    return filePath;
  } catch (err) {
    console.error("Fetch error:", err.message);
    return null;
  }
}

async function updatePhotos() {
  // 🔥 Only get users WITHOUT photo
  const { data: users, error } = await supabase
    .from("profiles")
    .select("id")
    .is("profile_photo_url", null);

  if (error) {
    console.error("Fetch error:", error.message);
    return;
  }

  console.log(`Found ${users.length} users without photos`);

  let index = 1;

  for (const user of users) {
    console.log(`Updating ${index}/${users.length}: ${user.id}`);

    const photoPath = await uploadRandomProfilePhoto(user.id, index);

    if (!photoPath) continue;

    const { error: updateError } = await supabase
      .from("profiles")
      .update({ profile_photo_url: photoPath })
      .eq("id", user.id);

    if (updateError) {
      console.error("Update error:", updateError.message);
      continue;
    }

    console.log("Updated:", user.id);
    index++;
  }

  console.log("✅ Done updating profile photos");
}

updatePhotos();