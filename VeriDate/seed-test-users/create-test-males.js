import { createClient } from "@supabase/supabase-js";
import "dotenv/config";

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

const cities = [
  { city: "Kuala Lumpur", lat: 3.139, lng: 101.6869 },
  { city: "Petaling Jaya", lat: 3.1073, lng: 101.6067 },
  { city: "Subang Jaya", lat: 3.0567, lng: 101.5851 },
  { city: "Shah Alam", lat: 3.0733, lng: 101.5185 },
  { city: "Penang", lat: 5.4141, lng: 100.3288 },
  { city: "Ipoh", lat: 4.5975, lng: 101.0901 },
  { city: "Johor Bahru", lat: 1.4927, lng: 103.7414 },
];

const firstNames = [
  "Aaron", "Jason", "Ethan", "Daniel", "Ryan", "Marcus",
  "Adrian", "Nicholas", "Kevin", "Joshua", "Brandon",
  "Samuel", "Justin", "Darren", "Ian", "Calvin",
  "Jordan", "Lucas", "Nathan", "Eric"
];

const lastNames = [
  "Tan", "Lee", "Lim", "Wong", "Ng", "Chan", "Teh", "Yap", "Koh", "Chong"
];

const jobs = [
  "Software Engineer",
  "Doctor",
  "Architect",
  "Financial Analyst",
  "Business Owner",
  "Marketing Manager",
  "Product Manager",
  "Lawyer",
  "Dentist",
  "UI/UX Designer"
];

const companies = [
  "Grab",
  "Shopee",
  "Maybank",
  "Petronas",
  "Deloitte",
  "KPMG",
  "PwC",
  "AIA Malaysia",
  "Intel",
  "Google Malaysia"
];

const schools = [
  "University of Malaya",
  "Monash University Malaysia",
  "Taylor's University",
  "Sunway University",
  "UCSI University",
  "HELP University"
];

const educationLevels = [
  "Bachelor's Degree",
  "Master's Degree",
  "Professional Certificate"
];

const goals = [
  "serious_relationship",
  "marriage",
  "friendship_first",
  "not_sure"
];

const bios = [
  "Gym, coffee, and meaningful conversations.",
  "Looking for something genuine and long term.",
  "I enjoy fitness, travel, and good food.",
  "Career-focused but values work-life balance.",
  "Introverted at first but very loyal once comfortable.",
  "Looking for someone kind, mature, and emotionally stable.",
  "Big fan of spontaneous road trips and cafe hopping.",
  "Always up for trying new restaurants."
];

function randomItem(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function randomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function birthDateFromAge(age) {
  const year = new Date().getFullYear() - age;
  const month = randomInt(1, 12);
  const day = randomInt(1, 28);

  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function randomLastSeen() {
  const now = Date.now();
  const minutesAgo = randomInt(1, 60 * 72);

  return new Date(now - minutesAgo * 60 * 1000).toISOString();
}

async function createUsers() {
  for (let i = 1; i <= 100; i++) {
    const firstName = randomItem(firstNames);
    const lastName = randomItem(lastNames);

    const fullName = `${firstName} ${lastName}`;

    const email = `testmale${String(i).padStart(3, "0")}@veridate.test`;

    const age = randomInt(23, 38);

    const location = randomItem(cities);

    const isOnline = Math.random() < 0.2;

    console.log(`Creating ${i}/100: ${email}`);

    const { data: authData, error: authError } =
      await supabase.auth.admin.createUser({
        email,
        password: "Test123456!",
        email_confirm: true,
        user_metadata: {
          full_name: fullName,
          gender: "male"
        }
      });

    if (authError) {
      console.error("Auth error:", authError.message);
      continue;
    }

    const userId = authData.user.id;

    const profile = {
      id: userId,
      full_name: fullName,
      date_of_birth: birthDateFromAge(age),
      age,
      gender: "male",
      city: location.city,
      country: "Malaysia",
      bio: randomItem(bios),
      job_title: randomItem(jobs),
      company_name: randomItem(companies),
      education_level: randomItem(educationLevels),
      school_name: randomItem(schools),
      height_cm: randomInt(168, 188),
      relationship_goal: randomItem(goals),
      profile_photo_url: null,
      verification_status: "verified",
      is_active: true,
      is_banned: false,
      latitude: location.lat + (Math.random() - 0.5) * 0.08,
      longitude: location.lng + (Math.random() - 0.5) * 0.08,
      is_online: isOnline,
      last_seen_at: isOnline
        ? new Date().toISOString()
        : randomLastSeen(),
      hometown: location.city,
      currently_living: location.city
    };

    const { error: profileError } = await supabase
      .from("profiles")
      .upsert(profile, { onConflict: "id" });

    if (profileError) {
      console.error("Profile error:", profileError.message);
      continue;
    }

    console.log(`Created: ${fullName}`);
  }

  console.log("✅ Done creating 100 male users");
}

createUsers();