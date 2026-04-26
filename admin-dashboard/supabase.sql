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

-- Distance-based matching support for the iPhone app.
alter table public.profiles
add column if not exists latitude double precision;

alter table public.profiles
add column if not exists longitude double precision;

create table if not exists public.dating_filters (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  preferred_gender text,
  min_age integer,
  max_age integer,
  min_height_cm integer,
  education_level text,
  relationship_goal text,
  verified_only boolean not null default false,
  max_distance_km integer not null default 50,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.dating_filters
add column if not exists max_distance_km integer not null default 50;

alter table public.dating_filters
alter column max_distance_km set default 50;

create unique index if not exists dating_filters_user_id_key
on public.dating_filters (user_id);

alter table public.dating_filters enable row level security;

drop policy if exists "Users can read own dating filters" on public.dating_filters;
create policy "Users can read own dating filters"
on public.dating_filters
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists "Users can create own dating filters" on public.dating_filters;
create policy "Users can create own dating filters"
on public.dating_filters
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can update own dating filters" on public.dating_filters;
create policy "Users can update own dating filters"
on public.dating_filters
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

create or replace function public.get_discovery_profiles(requesting_user_id uuid)
returns setof public.profiles
language sql
security definer
set search_path = public
as $$
  with requester as (
    select latitude, longitude
    from public.profiles
    where id = requesting_user_id
  ),
  filter as (
    select
      preferred_gender,
      min_age,
      max_age,
      min_height_cm,
      education_level,
      relationship_goal,
      verified_only,
      max_distance_km
    from public.dating_filters
    where user_id = requesting_user_id
  ),
  candidates as (
    select
      p as profile,
      (
        6371 * 2 * asin(
          least(
            1,
            sqrt(
              power(sin(radians((p.latitude - requester.latitude) / 2)), 2)
              + cos(radians(requester.latitude))
              * cos(radians(p.latitude))
              * power(sin(radians((p.longitude - requester.longitude) / 2)), 2)
            )
          )
        )
      ) as distance_km
    from public.profiles p
    cross join requester
    left join filter on true
    where p.id <> requesting_user_id
      and requester.latitude is not null
      and requester.longitude is not null
      and p.latitude is not null
      and p.longitude is not null
      and p.full_name is not null
      and not exists (
        select 1
        from public.profile_actions pa
        where pa.actor_user_id = requesting_user_id
          and pa.target_user_id = p.id
      )
      and (filter.preferred_gender is null or p.gender = filter.preferred_gender)
      and (filter.min_age is null or p.age >= filter.min_age)
      and (filter.max_age is null or p.age <= filter.max_age)
      and (filter.min_height_cm is null or p.height_cm >= filter.min_height_cm)
      and (filter.education_level is null or p.education_level = filter.education_level)
      and (filter.relationship_goal is null or p.relationship_goal = filter.relationship_goal)
      and (coalesce(filter.verified_only, false) = false or p.verification_status = 'verified')
  )
  select (candidates.profile).*
  from candidates
  left join filter on true
  where candidates.distance_km <= coalesce(filter.max_distance_km, 50)
  order by candidates.distance_km asc;
$$;

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
