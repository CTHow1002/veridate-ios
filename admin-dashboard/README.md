# VeriDate Admin Dashboard

Simple private web dashboard for reviewing pending VeriDate verification submissions.

## Setup

1. Copy `.env.example` to `.env`.
2. Fill in:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `ADMIN_USERNAME`
   - `ADMIN_PASSWORD`
   - `ADMIN_SESSION_SECRET`
3. If needed, run `supabase.sql` in the Supabase SQL Editor.
4. Start the dashboard:

```bash
npm run dev
```

Open `http://localhost:3000`.

The service role key is used only by `server.js` and is never sent to the browser.
