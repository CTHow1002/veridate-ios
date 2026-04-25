-- VeriDate admin review dashboard support table.
-- Run this only if your project does not already have verification_submissions.

create table if not exists public.verification_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'verified', 'rejected')),
  selfie_video_file_path text not null,
  liveness_prompt text,
  selfie_file_path text,
  id_document_file_path text not null,
  job_proof_file_path text not null,
  education_proof_file_path text not null,
  rejection_reason text,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  unique (user_id)
);

-- If the table already existed before the admin dashboard was added,
-- create table if not exists will not add new columns. These keep older
-- VeriDate projects compatible with the current iOS upload payload.
alter table public.verification_submissions
add column if not exists selfie_video_file_path text;

alter table public.verification_submissions
add column if not exists liveness_prompt text;

alter table public.verification_submissions
add column if not exists selfie_file_path text;

alter table public.verification_submissions
alter column selfie_file_path drop not null;

alter table public.verification_submissions
add column if not exists id_document_file_path text;

alter table public.verification_submissions
add column if not exists job_proof_file_path text;

alter table public.verification_submissions
add column if not exists education_proof_file_path text;

alter table public.verification_submissions
add column if not exists rejection_reason text;

alter table public.verification_submissions
add column if not exists submitted_at timestamptz not null default now();

alter table public.verification_submissions
add column if not exists reviewed_at timestamptz;

create unique index if not exists verification_submissions_user_id_key
on public.verification_submissions (user_id);

alter table public.verification_submissions enable row level security;

drop policy if exists "Users can create own verification submission" on public.verification_submissions;
create policy "Users can create own verification submission"
on public.verification_submissions
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can read own verification submission" on public.verification_submissions;
create policy "Users can read own verification submission"
on public.verification_submissions
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can resubmit own verification submission" on public.verification_submissions;
create policy "Users can resubmit own verification submission"
on public.verification_submissions
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- Admin review uses the service_role key on the backend, which bypasses RLS.

create table if not exists public.admin_users (
  id uuid primary key default gen_random_uuid(),
  username text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  last_login_at timestamptz
);

-- If admin_users already existed, create table if not exists will not add
-- these dashboard columns. Keep this migration safe to rerun.
alter table public.admin_users
add column if not exists username text;

alter table public.admin_users
add column if not exists is_active boolean not null default true;

alter table public.admin_users
add column if not exists created_at timestamptz not null default now();

alter table public.admin_users
add column if not exists last_login_at timestamptz;

-- Older VeriDate experiments may have created admin_users.email as a
-- required column. The dashboard now keys admins by username only.
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

    update public.admin_users
    set username = lower(email)
    where username is null
      and email is not null;
  end if;
end $$;

create unique index if not exists admin_users_username_key
on public.admin_users (username);

alter table public.admin_users enable row level security;

-- The admin dashboard reads this table only through its server-side service_role key.
-- Add your admin user once:
-- insert into public.admin_users (username) values ('admin') on conflict (username) do update set is_active = true;

notify pgrst, 'reload schema';
