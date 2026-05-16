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
  "Alicia", "Chloe", "Emily", "Hannah", "Jasmine", "Mei Lin", "Sarah", "Nicole",
  "Amanda", "Rachel", "Vanessa", "Samantha", "Joey", "Evelyn", "Crystal",
  "Michelle", "Yvonne", "Carmen", "Elaine", "Natalie"
];

const lastNames = [
  "Tan", "Lee", "Lim", "Wong", "Ng", "Chan", "Teh", "Yap", "Koh", "Chong"
];

const jobs = [
  "Marketing Executive", "Doctor", "Pharmacist", "UX Designer", "Teacher",
  "Financial Analyst", "Software Engineer", "Beauty Consultant", "HR Executive",
  "Business Development Executive"
];

const companies = [
  "Maybank", "Public Bank", "Grab", "Shopee", "Sunway Group",
  "KPJ Healthcare", "AIA Malaysia", "Deloitte", "KPMG", "L'Oréal Malaysia"
];

const schools = [
  "University of Malaya", "Monash University Malaysia", "Taylor's University",
  "Sunway University", "INTI International University", "HELP University",
  "UCSI University", "Universiti Sains Malaysia"
];

const educationLevels = [
  "Bachelor's Degree",
  "Master's Degree",
  "Diploma",
  "Professional Certificate"
];

const goals = [
  "serious_relationship",
  "marriage",
  "friendship_first",
  "not_sure"
];

const bios = [
  "Coffee, weekend walks, and meaningful conversations.",
  "Looking for someone genuine, kind, and emotionally mature.",
  "Work hard, travel when possible, and always make time for good food.",
  "I enjoy quiet cafes, fitness, skincare, and deep conversations.",
  "Here to meet someone sincere and intentional.",
  "A little introverted at first, but warm once comfortable.",
  "I value consistency, honesty, and good communication.",
  "Love spontaneous road trips, brunch, and cozy movie nights."
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
  const minutesAgo = randomInt(1, 60 * 72); // within 72 hours
  return new Date(now - minutesAgo * 60 * 1000).toISOString();
}

function randomPhotoUrl(i) {
  // For testing only. Later you can replace with Supabase Storage image paths.
  return `https://randomuser.me/api/portraits/women/${(i % 90) + 1}.jpg`;
}

async function createUsers() {
  for (let i = 1; i <= 100; i++) {
    const firstName = randomItem(firstNames);
    const lastName = randomItem(lastNames);
    const fullName = `${firstName} ${lastName}`;
    const email = `testfemale${String(i).padStart(3, "0")}@veridate.test`;
    const password = "Test123456!";
    const age = randomInt(21, 36);
    const location = randomItem(cities);
    const isOnline = Math.random() < 0.18;

    console.log(`Creating ${i}/100: ${email}`);

    const { data: authData, error: authError } = await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        full_name: fullName,
        gender: "female"
      }
    });

    if (authError) {
      console.error("Auth error:", email, authError.message);
      continue;
    }

    const userId = authData.user.id;

    const profile = {
      id: userId,
      full_name: fullName,
      date_of_birth: birthDateFromAge(age),
      age,
      gender: "female",
      city: location.city,
      country: "Malaysia",
      bio: randomItem(bios),
      job_title: randomItem(jobs),
      company_name: randomItem(companies),
      education_level: randomItem(educationLevels),
      school_name: randomItem(schools),
      height_cm: randomInt(154, 174),
      relationship_goal: randomItem(goals),
      profile_photo_url: randomPhotoUrl(i),
      verification_status: "verified",
      is_active: true,
      is_banned: false,
      latitude: location.lat + (Math.random() - 0.5) * 0.08,
      longitude: location.lng + (Math.random() - 0.5) * 0.08,
      is_online: isOnline,
      last_seen_at: isOnline ? new Date().toISOString() : randomLastSeen(),
      hometown: location.city,
      currently_living: location.city
    };

    const { error: profileError } = await supabase
      .from("profiles")
      .upsert(profile, { onConflict: "id" });

    if (profileError) {
      console.error("Profile error:", email, profileError.message);
      continue;
    }

    console.log("Created:", fullName);
  }

  console.log("Done creating test female users.");
}

createUsers();