# VeriDate

VeriDate is split across four services on purpose:

| Area | Hosted / Managed In | Notes |
| --- | --- | --- |
| iPhone app | Xcode | The SwiftUI app lives in `VeriDate/` and is built/run from `VeriDate.xcodeproj`. |
| Backend, database, auth, storage | Supabase | Supabase owns auth, Postgres tables, row-level security, and storage buckets. |
| Admin dashboard | Vercel | The review dashboard lives in `admin-dashboard/` and deploys as a Next.js app. |
| Code storage | GitHub | This repository stores the iOS app, admin dashboard, and setup docs. |

## Project Structure

```text
VeriDate/
  VeriDate.xcodeproj
  VeriDate/
    Models/
    Services/
    ViewModels/
    Views/

admin-dashboard/
  app/
  components/
  lib/
  supabase.sql
```

## iPhone App

Open this in Xcode:

```text
VeriDate/VeriDate.xcodeproj
```

The app uses Supabase from [SupabaseManager.swift](/Users/cthow/Documents/Codex/2026-04-24/github-plugin-github-openai-curated-you/VeriDate/VeriDate/Services/SupabaseManager.swift). The iPhone app must only use the public Supabase anon key, never the service role key.

## Supabase

Supabase hosts:

- Authentication
- Postgres tables, including `profiles` and `verification_submissions`
- Storage buckets, including `profile-photos` and `verification-documents`
- Row-level security policies

Run [admin-dashboard/supabase.sql](/Users/cthow/Documents/Codex/2026-04-24/github-plugin-github-openai-curated-you/admin-dashboard/supabase.sql) in the Supabase SQL Editor if the admin review table or columns are missing.

## Admin Dashboard

The admin dashboard is a Next.js app in:

```text
admin-dashboard/
```

For local development:

```bash
cd admin-dashboard
npm install
npm run dev
```

For Vercel deployment:

- Set the Vercel project root to `admin-dashboard`
- Use `npm run build` as the build command
- Add the required environment variables in Vercel Project Settings

Required Vercel environment variables:

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
ADMIN_USERNAME
ADMIN_PASSWORD
ADMIN_SESSION_SECRET
```

Do not create any `NEXT_PUBLIC_` secret variables. The Supabase service role key belongs only on the server side.

## GitHub

GitHub stores the source code. Do not commit local secrets or generated build output:

- `admin-dashboard/.env`
- `admin-dashboard/.next/`
- `admin-dashboard/node_modules/`
- `Build/`
