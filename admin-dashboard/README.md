# VeriDate Admin Dashboard

Simple private Next.js dashboard for reviewing pending VeriDate verification submissions, including short video verification clips.

The Supabase service role key is used only in server-side route handlers and server-only libraries. It is never sent to browser/client components. Private verification files are shown through short-lived Supabase signed URLs.

## Local Setup

1. Copy `.env.example` to `.env`.
2. Fill in:
   - `SUPABASE_URL`
   - `SUPABASE_SERVICE_ROLE_KEY`
   - `ADMIN_USERNAME`
   - `ADMIN_PASSWORD`
   - `ADMIN_SESSION_SECRET`
3. If needed, run `supabase.sql` in the Supabase SQL Editor.
4. Add your admin username to the allowlist:

```sql
alter table public.admin_users
add column if not exists username text;

alter table public.admin_users
add column if not exists is_active boolean not null default true;

create unique index if not exists admin_users_username_key
on public.admin_users (username);

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'admin_users'
      and column_name = 'email'
  ) then
    alter table public.admin_users alter column email drop not null;
  end if;
end $$;

insert into public.admin_users (username)
values ('admin')
on conflict (username) do update set is_active = true;
```

5. Install dependencies:

```bash
npm install
```

6. Start the dashboard:

```bash
npm run dev
```

Open `http://localhost:3000`.

## Build

```bash
npm run typecheck
npm run build
```

## Vercel Deployment

Create a Vercel project using this folder as the app root:

```text
admin-dashboard
```

Add these environment variables in Vercel Project Settings:

```text
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
ADMIN_USERNAME
ADMIN_PASSWORD
ADMIN_SESSION_SECRET
```

Do not prefix secrets with `NEXT_PUBLIC_`. Any `NEXT_PUBLIC_` variable can be exposed to the browser.
