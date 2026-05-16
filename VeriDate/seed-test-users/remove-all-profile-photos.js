import { createClient } from "@supabase/supabase-js";
import "dotenv/config";

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

async function removeAllPhotos() {
  console.log("Removing all profile photos...");

  const { data, error } = await supabase
    .from("profiles")
    .update({ profile_photo_url: null })
    .neq("id", "00000000-0000-0000-0000-000000000000"); // update all rows

  if (error) {
    console.error("Error:", error.message);
    return;
  }

  console.log("✅ All profile photos removed");
}

removeAllPhotos();