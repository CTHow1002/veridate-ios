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

alter table public.profiles
add column if not exists is_online boolean not null default false;

alter table public.profiles
add column if not exists last_seen_at timestamptz;

alter table public.profiles enable row level security;

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
on public.profiles
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

create table if not exists public.dating_filters (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  preferred_gender text,
  min_age integer,
  max_age integer,
  preferred_city text,
  min_distance_km integer not null default 0,
  max_distance_km integer not null default 100,
  min_height_cm integer,
  max_height_cm integer,
  education_level text,
  relationship_goal text,
  verified_only boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.dating_filters
add column if not exists min_distance_km integer not null default 0;

alter table public.dating_filters
add column if not exists max_distance_km integer not null default 100;

alter table public.dating_filters
add column if not exists preferred_gender text;

alter table public.dating_filters
add column if not exists min_age integer;

alter table public.dating_filters
add column if not exists max_age integer;

alter table public.dating_filters
add column if not exists preferred_city text;

alter table public.dating_filters
add column if not exists min_height_cm integer;

alter table public.dating_filters
add column if not exists max_height_cm integer;

alter table public.dating_filters
add column if not exists education_level text;

alter table public.dating_filters
add column if not exists relationship_goal text;

alter table public.dating_filters
add column if not exists verified_only boolean not null default false;

alter table public.dating_filters
alter column min_distance_km set default 0;

alter table public.dating_filters
alter column max_distance_km set default 100;

alter table public.dating_filters
alter column min_age set default 18;

alter table public.dating_filters
alter column max_age set default 50;

alter table public.dating_filters
alter column min_height_cm set default 120;

alter table public.dating_filters
alter column max_height_cm set default 200;

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

create table if not exists public.profile_actions (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid not null references public.profiles(id) on delete cascade,
  target_user_id uuid not null references public.profiles(id) on delete cascade,
  action text not null check (action in ('like', 'pass')),
  created_at timestamptz not null default now(),
  unique (actor_user_id, target_user_id)
);

alter table public.profile_actions enable row level security;

drop policy if exists "Users can create own profile actions" on public.profile_actions;
create policy "Users can create own profile actions"
on public.profile_actions
for insert
to authenticated
with check (auth.uid() = actor_user_id);

drop policy if exists "Users can read own profile actions" on public.profile_actions;
create policy "Users can read own profile actions"
on public.profile_actions
for select
to authenticated
using (auth.uid() = actor_user_id);

create table if not exists public.matches (
  id uuid primary key default gen_random_uuid(),
  user_one_id uuid not null references public.profiles(id) on delete cascade,
  user_two_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (user_one_id <> user_two_id),
  unique (user_one_id, user_two_id)
);

alter table public.matches enable row level security;

drop policy if exists "Users can read their matches" on public.matches;
create policy "Users can read their matches"
on public.matches
for select
to authenticated
using (auth.uid() = user_one_id or auth.uid() = user_two_id);

drop policy if exists "Matched users can read each other profiles" on public.profiles;
create policy "Matched users can read each other profiles"
on public.profiles
for select
to authenticated
using (
  auth.uid() = id
  or exists (
    select 1
    from public.matches
    where (matches.user_one_id = auth.uid() and matches.user_two_id = profiles.id)
       or (matches.user_two_id = auth.uid() and matches.user_one_id = profiles.id)
  )
);

-- Chat support for matched users.
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.matches(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (length(trim(body)) > 0),
  is_read boolean not null default false,
  delivered_at timestamptz,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.messages
add column if not exists delivered_at timestamptz;

alter table public.messages
add column if not exists read_at timestamptz;

create index if not exists messages_match_created_at_idx
on public.messages (match_id, created_at);

alter table public.messages enable row level security;

create or replace function public.set_user_presence(p_is_online boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  update public.profiles
  set
    is_online = p_is_online,
    last_seen_at = now()
  where id = auth.uid();
end;
$$;

grant execute on function public.set_user_presence(boolean) to authenticated;

drop policy if exists "Matched users can read messages" on public.messages;
create policy "Matched users can read messages"
on public.messages
for select
to authenticated
using (
  exists (
    select 1
    from public.matches
    where matches.id = messages.match_id
      and (auth.uid() = matches.user_one_id or auth.uid() = matches.user_two_id)
  )
);

drop policy if exists "Matched users can send messages" on public.messages;
create policy "Matched users can send messages"
on public.messages
for insert
to authenticated
with check (
  auth.uid() = sender_id
  and exists (
    select 1
    from public.matches
    where matches.id = messages.match_id
      and (auth.uid() = matches.user_one_id or auth.uid() = matches.user_two_id)
  )
);

drop policy if exists "Matched users can mark messages read" on public.messages;
create policy "Matched users can mark messages read"
on public.messages
for update
to authenticated
using (
  exists (
    select 1
    from public.matches
    where matches.id = messages.match_id
      and (auth.uid() = matches.user_one_id or auth.uid() = matches.user_two_id)
  )
)
with check (
  exists (
    select 1
    from public.matches
    where matches.id = messages.match_id
      and (auth.uid() = matches.user_one_id or auth.uid() = matches.user_two_id)
  )
);

create or replace function public.mark_match_messages_delivered(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1
    from public.matches
    where id = p_match_id
      and (user_one_id = auth.uid() or user_two_id = auth.uid())
  ) then
    raise exception 'Not allowed';
  end if;

  update public.messages
  set delivered_at = coalesce(delivered_at, now())
  where match_id = p_match_id
    and sender_id <> auth.uid();
end;
$$;

grant execute on function public.mark_match_messages_delivered(uuid) to authenticated;

create or replace function public.mark_match_messages_read(p_match_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1
    from public.matches
    where id = p_match_id
      and (user_one_id = auth.uid() or user_two_id = auth.uid())
  ) then
    raise exception 'Not allowed';
  end if;

  update public.messages
  set
    delivered_at = coalesce(delivered_at, now()),
    read_at = coalesce(read_at, now()),
    is_read = true
  where match_id = p_match_id
    and sender_id <> auth.uid();
end;
$$;

grant execute on function public.mark_match_messages_read(uuid) to authenticated;

create table if not exists public.user_blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_user_id uuid not null references public.profiles(id) on delete cascade,
  blocked_user_id uuid not null references public.profiles(id) on delete cascade,
  match_id uuid references public.matches(id) on delete set null,
  reason text,
  created_at timestamptz not null default now(),
  check (blocker_user_id <> blocked_user_id),
  unique (blocker_user_id, blocked_user_id)
);

alter table public.user_blocks enable row level security;

drop policy if exists "Users can create own blocks" on public.user_blocks;
create policy "Users can create own blocks"
on public.user_blocks
for insert
to authenticated
with check (auth.uid() = blocker_user_id);

drop policy if exists "Users can read own blocks" on public.user_blocks;
create policy "Users can read own blocks"
on public.user_blocks
for select
to authenticated
using (auth.uid() = blocker_user_id);

drop policy if exists "Users can update own blocks" on public.user_blocks;
create policy "Users can update own blocks"
on public.user_blocks
for update
to authenticated
using (auth.uid() = blocker_user_id)
with check (auth.uid() = blocker_user_id);

create table if not exists public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_user_id uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid not null references public.profiles(id) on delete cascade,
  match_id uuid references public.matches(id) on delete set null,
  reason text not null,
  created_at timestamptz not null default now(),
  check (reporter_user_id <> reported_user_id)
);

alter table public.user_reports enable row level security;

drop policy if exists "Users can create own reports" on public.user_reports;
create policy "Users can create own reports"
on public.user_reports
for insert
to authenticated
with check (auth.uid() = reporter_user_id);

drop policy if exists "Users can read own reports" on public.user_reports;
create policy "Users can read own reports"
on public.user_reports
for select
to authenticated
using (auth.uid() = reporter_user_id);

create or replace function public.create_match_on_mutual_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  first_user uuid;
  second_user uuid;
begin
  if new.action <> 'like' then
    return new;
  end if;

  if exists (
    select 1
    from public.profile_actions
    where actor_user_id = new.target_user_id
      and target_user_id = new.actor_user_id
      and action = 'like'
  ) then
    if new.actor_user_id < new.target_user_id then
      first_user := new.actor_user_id;
      second_user := new.target_user_id;
    else
      first_user := new.target_user_id;
      second_user := new.actor_user_id;
    end if;

    insert into public.matches (user_one_id, user_two_id)
    values (first_user, second_user)
    on conflict (user_one_id, user_two_id) do nothing;
  end if;

  return new;
end;
$$;

drop trigger if exists profile_actions_create_match on public.profile_actions;
create trigger profile_actions_create_match
after insert or update of action on public.profile_actions
for each row
execute function public.create_match_on_mutual_like();

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
      preferred_city,
      min_distance_km,
      max_distance_km,
      min_height_cm,
      max_height_cm,
      education_level,
      relationship_goal,
      verified_only
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
      and p.full_name is not null
      and p.verification_status = 'verified'
      and not exists (
        select 1
        from public.profile_actions pa
        where pa.actor_user_id = requesting_user_id
          and pa.target_user_id = p.id
      )
      and (filter.preferred_gender is null or p.gender = filter.preferred_gender)
      and (filter.min_age is null or p.age >= filter.min_age)
      and (filter.max_age is null or p.age <= filter.max_age)
      and (
        filter.preferred_city is null
        or filter.preferred_city = ''
        or p.city ilike '%' || filter.preferred_city || '%'
      )
      and (filter.min_height_cm is null or p.height_cm >= filter.min_height_cm)
      and (filter.max_height_cm is null or p.height_cm <= filter.max_height_cm)
      and (filter.education_level is null or p.education_level = filter.education_level)
      and (filter.relationship_goal is null or p.relationship_goal = filter.relationship_goal)
      and (coalesce(filter.verified_only, false) = false or p.verification_status = 'verified')
  )
  select (candidates.profile).*
  from candidates
  left join filter on true
  where (
    candidates.distance_km is null
    or (candidates.profile).latitude is null
    or (candidates.profile).longitude is null
    or (
      candidates.distance_km >= coalesce(filter.min_distance_km, 0)
      and candidates.distance_km <= coalesce(filter.max_distance_km, 100)
    )
  )
  order by candidates.distance_km asc nulls last;
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
