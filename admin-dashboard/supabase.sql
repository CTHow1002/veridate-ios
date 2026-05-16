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
with check (auth.uid() = user_id);

drop policy if exists "Users can read own verification submission" on public.verification_submissions;
create policy "Users can read own verification submission"
on public.verification_submissions
for select
using (auth.uid() = user_id);

drop policy if exists "Users can resubmit own verification submission" on public.verification_submissions;
create policy "Users can resubmit own verification submission"
on public.verification_submissions
for update
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

alter table public.profiles
add column if not exists is_banned boolean not null default false;

alter table public.profiles
add column if not exists ban_until timestamptz;

alter table public.profiles
add column if not exists ban_message text;

alter table public.profiles
add column if not exists ban_details text;

alter table public.profiles
add column if not exists warning_message text;

alter table public.profiles
add column if not exists warning_details text;

alter table public.profiles
add column if not exists warned_at timestamptz;

alter table public.profiles
add column if not exists warning_until timestamptz;

alter table public.profiles
add column if not exists is_deactivated boolean not null default false;

alter table public.profiles
add column if not exists is_discoverable boolean not null default true;

alter table public.profiles
add column if not exists account_deletion_requested_at timestamptz;

alter table public.profiles
add column if not exists account_deletion_scheduled_at timestamptz;

alter table public.profiles
add column if not exists hometown text;

alter table public.profiles
add column if not exists currently_living text;

alter table public.profiles
add column if not exists bio text;

alter table public.profiles
add column if not exists full_name text;

alter table public.profiles
add column if not exists date_of_birth date;

alter table public.profiles
add column if not exists gender text;

alter table public.profiles
add column if not exists city text;

alter table public.profiles
add column if not exists job_title text;

alter table public.profiles
add column if not exists company_name text;

alter table public.profiles
add column if not exists education_level text;

alter table public.profiles
add column if not exists school_name text;

alter table public.profiles
add column if not exists height_cm integer;

alter table public.profiles
add column if not exists relationship_goal text;

alter table public.profiles
add column if not exists profile_photo_url text;

alter table public.profiles
add column if not exists updated_at timestamptz not null default now();

create table if not exists public.profile_change_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  request_type text not null check (request_type in ('legal_name', 'work', 'education')),
  current_full_name text,
  requested_full_name text,
  current_job_title text,
  requested_job_title text,
  current_company_name text,
  requested_company_name text,
  current_education_level text,
  requested_education_level text,
  current_school_name text,
  requested_school_name text,
  message text,
  attachment_file_path text,
  attachment_file_name text,
  attachment_content_type text,
  attachment_source text check (attachment_source in ('photos', 'camera', 'files') or attachment_source is null),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  admin_notes text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profile_change_requests
add column if not exists attachment_file_path text;

alter table public.profile_change_requests
add column if not exists attachment_file_name text;

alter table public.profile_change_requests
add column if not exists attachment_content_type text;

alter table public.profile_change_requests
add column if not exists attachment_source text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profile_change_requests_attachment_source_check'
  ) then
    alter table public.profile_change_requests
    add constraint profile_change_requests_attachment_source_check
    check (attachment_source in ('photos', 'camera', 'files') or attachment_source is null);
  end if;
end $$;

alter table public.profile_change_requests enable row level security;

grant select, insert on public.profile_change_requests to authenticated;

drop policy if exists "Users can create own profile change requests" on public.profile_change_requests;
create policy "Users can create own profile change requests"
on public.profile_change_requests
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists "Users can read own profile change requests" on public.profile_change_requests;
create policy "Users can read own profile change requests"
on public.profile_change_requests
for select
to authenticated
using (auth.uid() = user_id);

create or replace function public.touch_profile_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.full_name is distinct from old.full_name
    or new.date_of_birth is distinct from old.date_of_birth
    or new.gender is distinct from old.gender
    or new.city is distinct from old.city
    or new.hometown is distinct from old.hometown
    or new.currently_living is distinct from old.currently_living
    or new.bio is distinct from old.bio
    or new.job_title is distinct from old.job_title
    or new.company_name is distinct from old.company_name
    or new.education_level is distinct from old.education_level
    or new.school_name is distinct from old.school_name
    or new.height_cm is distinct from old.height_cm
    or new.relationship_goal is distinct from old.relationship_goal
    or new.profile_photo_url is distinct from old.profile_photo_url
  then
    new.updated_at = now();
  else
    new.updated_at = old.updated_at;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_touch_updated_at on public.profiles;
create trigger profiles_touch_updated_at
before update on public.profiles
for each row
execute function public.touch_profile_updated_at();

alter table public.profiles enable row level security;

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
on public.profiles
for update
using (auth.uid() = id)
with check (auth.uid() = id);

-- Account deletion queue. iOS inserts here; Vercel Cron processes it with the service role key.
create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  status text not null default 'pending' check (status in ('pending', 'processing', 'completed', 'failed', 'canceled')),
  reason text,
  requested_at timestamptz not null default now(),
  scheduled_delete_at timestamptz not null default (now() + interval '24 hours'),
  processed_at timestamptz,
  canceled_at timestamptz,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.account_deletion_requests
add column if not exists status text not null default 'pending';

alter table public.account_deletion_requests
add column if not exists reason text;

alter table public.account_deletion_requests
add column if not exists requested_at timestamptz not null default now();

alter table public.account_deletion_requests
add column if not exists scheduled_delete_at timestamptz not null default (now() + interval '24 hours');

alter table public.account_deletion_requests
add column if not exists processed_at timestamptz;

alter table public.account_deletion_requests
add column if not exists canceled_at timestamptz;

alter table public.account_deletion_requests
add column if not exists error_message text;

alter table public.account_deletion_requests
add column if not exists created_at timestamptz not null default now();

alter table public.account_deletion_requests
add column if not exists updated_at timestamptz not null default now();

do $$
declare
  constraint_name text;
begin
  for constraint_name in
    select c.conname
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    join pg_class referenced_table on referenced_table.oid = c.confrelid
    join pg_namespace referenced_schema on referenced_schema.oid = referenced_table.relnamespace
    where n.nspname = 'public'
      and t.relname = 'account_deletion_requests'
      and referenced_schema.nspname = 'public'
      and referenced_table.relname = 'profiles'
      and c.contype = 'f'
  loop
    execute format('alter table public.account_deletion_requests drop constraint %I', constraint_name);
  end loop;
end $$;

create unique index if not exists account_deletion_requests_one_active_per_user
on public.account_deletion_requests (user_id)
where status in ('pending', 'processing');

create or replace function public.touch_account_deletion_request_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists account_deletion_requests_touch_updated_at on public.account_deletion_requests;
create trigger account_deletion_requests_touch_updated_at
before update on public.account_deletion_requests
for each row
execute function public.touch_account_deletion_request_updated_at();

alter table public.account_deletion_requests enable row level security;

grant select, insert, update on public.account_deletion_requests to authenticated;

drop policy if exists "Users can create own account deletion request" on public.account_deletion_requests;
create policy "Users can create own account deletion request"
on public.account_deletion_requests
for insert
with check (
  auth.uid() = user_id
  and status = 'pending'
  and scheduled_delete_at >= now() + interval '23 hours'
);

drop policy if exists "Users can read own account deletion requests" on public.account_deletion_requests;
create policy "Users can read own account deletion requests"
on public.account_deletion_requests
for select
using (auth.uid() = user_id);

drop policy if exists "Users can cancel own pending account deletion request" on public.account_deletion_requests;
create policy "Users can cancel own pending account deletion request"
on public.account_deletion_requests
for update
using (auth.uid() = user_id and status = 'pending')
with check (auth.uid() = user_id and status = 'canceled');

create table if not exists public.profile_prompts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  prompt text not null,
  answer text not null,
  display_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profile_prompts enable row level security;

create or replace function public.touch_profile_prompts_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profile_prompts_touch_updated_at on public.profile_prompts;
create trigger profile_prompts_touch_updated_at
before update on public.profile_prompts
for each row
execute function public.touch_profile_prompts_updated_at();

drop policy if exists "Users can read own profile prompts" on public.profile_prompts;
create policy "Users can read own profile prompts"
on public.profile_prompts
for select
using (auth.uid() = user_id);

drop policy if exists "Users can create own profile prompts" on public.profile_prompts;
create policy "Users can create own profile prompts"
on public.profile_prompts
for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update own profile prompts" on public.profile_prompts;
create policy "Users can update own profile prompts"
on public.profile_prompts
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete own profile prompts" on public.profile_prompts;
create policy "Users can delete own profile prompts"
on public.profile_prompts
for delete
using (auth.uid() = user_id);

create index if not exists profile_prompts_user_order_idx
on public.profile_prompts (user_id, display_order);

create table if not exists public.profile_interests (
  user_id uuid not null references public.profiles(id) on delete cascade,
  interest text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, interest)
);

alter table public.profile_interests enable row level security;

drop policy if exists "Users can read own profile interests" on public.profile_interests;
create policy "Users can read own profile interests"
on public.profile_interests
for select
using (auth.uid() = user_id);

drop policy if exists "Users can create own profile interests" on public.profile_interests;
create policy "Users can create own profile interests"
on public.profile_interests
for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can delete own profile interests" on public.profile_interests;
create policy "Users can delete own profile interests"
on public.profile_interests
for delete
using (auth.uid() = user_id);

create index if not exists profile_interests_user_idx
on public.profile_interests (user_id);

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
using (auth.uid() = user_id);

drop policy if exists "Users can create own dating filters" on public.dating_filters;
create policy "Users can create own dating filters"
on public.dating_filters
for insert
with check (auth.uid() = user_id);

drop policy if exists "Users can update own dating filters" on public.dating_filters;
create policy "Users can update own dating filters"
on public.dating_filters
for update
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

alter table public.profile_actions
add column if not exists pass_resurface_after timestamptz;

alter table public.profile_actions
add column if not exists resurfaced_count integer not null default 0;

create or replace function public.prepare_profile_action()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.action = 'pass' then
    new.pass_resurface_after = now() + ((30 + floor(random() * 31))::int * interval '1 day');

    if tg_op = 'UPDATE' then
      new.resurfaced_count = coalesce(old.resurfaced_count, 0) + 1;
    else
      new.resurfaced_count = coalesce(new.resurfaced_count, 0);
    end if;
  else
    new.pass_resurface_after = null;
    new.resurfaced_count = 0;
  end if;

  return new;
end;
$$;

drop trigger if exists profile_actions_prepare on public.profile_actions;
create trigger profile_actions_prepare
before insert or update of action, created_at on public.profile_actions
for each row
execute function public.prepare_profile_action();

drop policy if exists "Users can create own profile actions" on public.profile_actions;
create policy "Users can create own profile actions"
on public.profile_actions
for insert
with check (auth.uid() = actor_user_id);

drop policy if exists "Users can read own profile actions" on public.profile_actions;
create policy "Users can read own profile actions"
on public.profile_actions
for select
using (auth.uid() = actor_user_id or auth.uid() = target_user_id);

drop policy if exists "Users can delete own profile actions" on public.profile_actions;
create policy "Users can delete own profile actions"
on public.profile_actions
for delete
using (auth.uid() = actor_user_id);

drop policy if exists "Users can update own profile actions" on public.profile_actions;
create policy "Users can update own profile actions"
on public.profile_actions
for update
using (auth.uid() = actor_user_id)
with check (auth.uid() = actor_user_id);

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
using (auth.uid() = user_one_id or auth.uid() = user_two_id);

drop policy if exists "Matched users can read each other profiles" on public.profiles;
create policy "Matched users can read each other profiles"
on public.profiles
for select
using (
  auth.uid() = id
  or exists (
    select 1
    from public.matches
    where (matches.user_one_id = auth.uid() and matches.user_two_id = profiles.id)
      or (matches.user_two_id = auth.uid() and matches.user_one_id = profiles.id)
  )
);

drop policy if exists "Users can read profiles that liked them" on public.profiles;
create policy "Users can read profiles that liked them"
on public.profiles
for select
using (
  exists (
    select 1
    from public.profile_actions pa
    where pa.actor_user_id = profiles.id
      and pa.target_user_id = auth.uid()
      and pa.action = 'like'
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
  attachment_file_path text,
  attachment_file_name text,
  attachment_content_type text,
  attachment_kind text check (attachment_kind in ('image', 'file') or attachment_kind is null),
  attachment_group_id uuid,
  reply_to_message_id uuid references public.messages(id) on delete set null,
  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.messages
add column if not exists delivered_at timestamptz;

alter table public.messages
add column if not exists read_at timestamptz;

alter table public.messages
add column if not exists attachment_file_path text;

alter table public.messages
add column if not exists attachment_file_name text;

alter table public.messages
add column if not exists attachment_content_type text;

alter table public.messages
add column if not exists attachment_kind text;

alter table public.messages
add column if not exists attachment_group_id uuid;

alter table public.messages
add column if not exists reply_to_message_id uuid references public.messages(id) on delete set null;

alter table public.messages
add column if not exists edited_at timestamptz;

alter table public.messages
add column if not exists deleted_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'messages_attachment_kind_check'
  ) then
    alter table public.messages
    add constraint messages_attachment_kind_check
    check (attachment_kind in ('image', 'file') or attachment_kind is null);
  end if;
end $$;

create index if not exists messages_match_created_at_idx
on public.messages (match_id, created_at);

create table if not exists public.message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  match_id uuid not null references public.matches(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  unique (message_id, user_id)
);

create index if not exists message_reactions_match_idx
on public.message_reactions (match_id);

create index if not exists message_reactions_message_idx
on public.message_reactions (message_id);

insert into storage.buckets (id, name, public, file_size_limit)
values ('chat-attachments', 'chat-attachments', false, 10485760)
on conflict (id) do update
set public = false,
    file_size_limit = 10485760;

drop policy if exists "Matched users can upload chat attachments" on storage.objects;
create policy "Matched users can upload chat attachments"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'chat-attachments'
);

drop policy if exists "Matched users can read chat attachments" on storage.objects;
create policy "Matched users can read chat attachments"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'chat-attachments'
);

alter table public.messages enable row level security;
alter table public.message_reactions enable row level security;

grant select, insert, update, delete on public.message_reactions to authenticated;

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

create table if not exists public.blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_user_id uuid not null references public.profiles(id) on delete cascade,
  blocked_user_id uuid not null references public.profiles(id) on delete cascade,
  match_id uuid references public.matches(id) on delete set null,
  reason text,
  created_at timestamptz not null default now(),
  check (blocker_user_id <> blocked_user_id),
  unique (blocker_user_id, blocked_user_id)
);

alter table public.blocks
add column if not exists blocker_user_id uuid references public.profiles(id) on delete cascade;

alter table public.blocks
add column if not exists blocked_user_id uuid references public.profiles(id) on delete cascade;

alter table public.blocks
add column if not exists blocker_id uuid references public.profiles(id) on delete cascade;

alter table public.blocks
add column if not exists blocked_id uuid references public.profiles(id) on delete cascade;

alter table public.blocks
add column if not exists match_id uuid references public.matches(id) on delete set null;

alter table public.blocks
add column if not exists reason text;

alter table public.blocks
add column if not exists created_at timestamptz not null default now();

create unique index if not exists blocks_blocker_blocked_unique_idx
on public.blocks (blocker_user_id, blocked_user_id);

create unique index if not exists blocks_legacy_blocker_blocked_unique_idx
on public.blocks (blocker_id, blocked_id);

update public.blocks
set
  blocker_user_id = coalesce(blocker_user_id, blocker_id),
  blocked_user_id = coalesce(blocked_user_id, blocked_id),
  blocker_id = coalesce(blocker_id, blocker_user_id),
  blocked_id = coalesce(blocked_id, blocked_user_id)
where blocker_user_id is null
   or blocked_user_id is null
   or blocker_id is null
   or blocked_id is null;

create or replace function public.sync_block_user_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.blocker_user_id := coalesce(new.blocker_user_id, new.blocker_id);
  new.blocked_user_id := coalesce(new.blocked_user_id, new.blocked_id);
  new.blocker_id := coalesce(new.blocker_id, new.blocker_user_id);
  new.blocked_id := coalesce(new.blocked_id, new.blocked_user_id);
  return new;
end;
$$;

drop trigger if exists sync_block_user_columns_before_write on public.blocks;
create trigger sync_block_user_columns_before_write
before insert or update on public.blocks
for each row
execute function public.sync_block_user_columns();

drop policy if exists "Matched users can read messages" on public.messages;
create policy "Matched users can read messages"
on public.messages
for select
using (
  exists (
    select 1
    from public.matches m
    where m.id = messages.match_id
      and auth.uid() in (m.user_one_id, m.user_two_id)
  )
);

drop policy if exists "Matched users can send messages" on public.messages;
create policy "Matched users can send messages"
on public.messages
for insert
with check (
  auth.uid() = sender_id
  and exists (
    select 1
    from public.matches m
    where m.id = messages.match_id
      and auth.uid() in (m.user_one_id, m.user_two_id)
  )
  and not exists (
    select 1
    from public.blocks b
    where exists (
      select 1
      from public.matches m
      where m.id = messages.match_id
        and (
          (b.blocker_user_id = m.user_one_id and b.blocked_user_id = m.user_two_id)
          or (b.blocker_user_id = m.user_two_id and b.blocked_user_id = m.user_one_id)
        )
    )
  )
);

drop policy if exists "Matched users can mark messages read" on public.messages;
create policy "Matched users can mark messages read"
on public.messages
for update
using (
  exists (
    select 1
    from public.matches m
    where m.id = messages.match_id
      and auth.uid() in (m.user_one_id, m.user_two_id)
  )
)
with check (
  exists (
    select 1
    from public.matches m
    where m.id = messages.match_id
      and auth.uid() in (m.user_one_id, m.user_two_id)
  )
);

drop policy if exists "Matched users can read reactions" on public.message_reactions;
create policy "Matched users can read reactions"
on public.message_reactions
for select
using (
  exists (
    select 1
    from public.matches m
    where m.id = message_reactions.match_id
      and auth.uid() in (m.user_one_id, m.user_two_id)
  )
);

drop policy if exists "Matched users can react" on public.message_reactions;
create policy "Matched users can react"
on public.message_reactions
for insert
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.matches m
    join public.messages msg on msg.match_id = m.id
    where m.id = message_reactions.match_id
      and msg.id = message_reactions.message_id
      and msg.match_id = message_reactions.match_id
      and auth.uid() in (m.user_one_id, m.user_two_id)
  )
);

drop policy if exists "Users can update their own reactions" on public.message_reactions;
create policy "Users can update their own reactions"
on public.message_reactions
for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own reactions" on public.message_reactions;
create policy "Users can delete their own reactions"
on public.message_reactions
for delete
using (auth.uid() = user_id);

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

create table if not exists public.chat_typing (
  match_id uuid not null references public.matches(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  is_typing boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (match_id, user_id)
);

alter table public.chat_typing enable row level security;

grant select, insert, update on public.chat_typing to authenticated;

drop policy if exists "Matched users can read typing status" on public.chat_typing;
create policy "Matched users can read typing status"
on public.chat_typing
for select
to authenticated
using (
  exists (
    select 1
    from public.matches m
    where m.id = chat_typing.match_id
      and auth.uid() in (m.user_one_id, m.user_two_id)
  )
);

drop policy if exists "Matched users can create own typing status" on public.chat_typing;
create policy "Matched users can create own typing status"
on public.chat_typing
for insert
to authenticated
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.matches m
    where m.id = chat_typing.match_id
      and auth.uid() in (m.user_one_id, m.user_two_id)
  )
);

drop policy if exists "Matched users can update own typing status" on public.chat_typing;
create policy "Matched users can update own typing status"
on public.chat_typing
for update
to authenticated
using (auth.uid() = user_id)
with check (
  auth.uid() = user_id
  and exists (
    select 1
    from public.matches m
    where m.id = chat_typing.match_id
      and auth.uid() in (m.user_one_id, m.user_two_id)
  )
);

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chat_typing'
  ) then
    alter publication supabase_realtime add table public.chat_typing;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_reactions'
  ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;
end;
$$;

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

grant select, insert, update, delete on public.user_blocks to authenticated;

create unique index if not exists user_blocks_blocker_blocked_unique_idx
on public.user_blocks (blocker_user_id, blocked_user_id);

drop policy if exists "Users can create own blocks" on public.user_blocks;
create policy "Users can create own blocks"
on public.user_blocks
for insert
with check (auth.uid() = blocker_user_id);

drop policy if exists "Users can read own blocks" on public.user_blocks;
create policy "Users can read own blocks"
on public.user_blocks
for select
using (auth.uid() = blocker_user_id);

drop policy if exists "Users can update own blocks" on public.user_blocks;
create policy "Users can update own blocks"
on public.user_blocks
for update
using (auth.uid() = blocker_user_id)
with check (auth.uid() = blocker_user_id);

drop policy if exists "Users can delete own blocks" on public.user_blocks;
create policy "Users can delete own blocks"
on public.user_blocks
for delete
using (auth.uid() = blocker_user_id);

create table if not exists public.blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_user_id uuid not null references public.profiles(id) on delete cascade,
  blocked_user_id uuid not null references public.profiles(id) on delete cascade,
  match_id uuid references public.matches(id) on delete set null,
  reason text,
  created_at timestamptz not null default now(),
  check (blocker_user_id <> blocked_user_id),
  unique (blocker_user_id, blocked_user_id)
);

alter table public.blocks enable row level security;

grant select, insert, update, delete on public.blocks to authenticated;

drop policy if exists "Users can create own blocks" on public.blocks;
create policy "Users can create own blocks"
on public.blocks
for insert
to authenticated
with check (
  auth.uid() is not null
  and auth.uid() = coalesce(blocker_user_id, blocker_id)
  and coalesce(blocker_user_id, blocker_id) <> coalesce(blocked_user_id, blocked_id)
);

drop policy if exists "Users can read own blocks" on public.blocks;
create policy "Users can read own blocks"
on public.blocks
for select
to authenticated
using (
  auth.uid() = coalesce(blocker_user_id, blocker_id)
  or auth.uid() = coalesce(blocked_user_id, blocked_id)
);

drop policy if exists "Users can update own blocks" on public.blocks;
create policy "Users can update own blocks"
on public.blocks
for update
to authenticated
using (auth.uid() = coalesce(blocker_user_id, blocker_id))
with check (auth.uid() = coalesce(blocker_user_id, blocker_id));

drop policy if exists "Users can delete own blocks" on public.blocks;
create policy "Users can delete own blocks"
on public.blocks
for delete
to authenticated
using (auth.uid() = coalesce(blocker_user_id, blocker_id));

create or replace function public.unblock_user_everywhere(p_blocked_user_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_count integer := 0;
  affected_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  delete from public.blocks
  where coalesce(blocker_user_id, blocker_id) = auth.uid()
    and coalesce(blocked_user_id, blocked_id) = p_blocked_user_id;
  get diagnostics affected_count = row_count;
  deleted_count := deleted_count + affected_count;

  delete from public.user_blocks
  where blocker_user_id = auth.uid()
    and blocked_user_id = p_blocked_user_id;
  get diagnostics affected_count = row_count;
  deleted_count := deleted_count + affected_count;

  return deleted_count;
end;
$$;

grant execute on function public.unblock_user_everywhere(uuid) to authenticated;

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
with check (auth.uid() = reporter_user_id);

drop policy if exists "Users can read own reports" on public.user_reports;
create policy "Users can read own reports"
on public.user_reports
for select
using (auth.uid() = reporter_user_id);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_user_id uuid not null references public.profiles(id) on delete cascade,
  reported_user_id uuid not null references public.profiles(id) on delete cascade,
  match_id uuid references public.matches(id) on delete set null,
  reason text not null,
  details text,
  status text not null default 'open' check (status in ('open', 'dismissed', 'warned', 'banned')),
  moderation_notes text,
  action_taken text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (reporter_user_id <> reported_user_id)
);

alter table public.reports
add column if not exists reporter_user_id uuid references public.profiles(id) on delete cascade;

alter table public.reports
add column if not exists reported_user_id uuid references public.profiles(id) on delete cascade;

alter table public.reports
add column if not exists match_id uuid references public.matches(id) on delete set null;

alter table public.reports
add column if not exists reason text;

alter table public.reports
add column if not exists details text;

alter table public.reports
add column if not exists proof_file_path text;

alter table public.reports
add column if not exists status text not null default 'open';

alter table public.reports
add column if not exists moderation_notes text;

alter table public.reports
add column if not exists action_taken text;

alter table public.reports
add column if not exists reviewed_at timestamptz;

alter table public.reports
add column if not exists created_at timestamptz not null default now();

create or replace function public.sync_report_legacy_columns()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  row_data jsonb;
begin
  row_data := to_jsonb(new);

  if row_data ? 'reporter_id'
     and row_data->>'reporter_id' is null
     and row_data ? 'reporter_user_id' then
    row_data := jsonb_set(row_data, '{reporter_id}', row_data->'reporter_user_id');
  end if;

  if row_data ? 'reported_id'
     and row_data->>'reported_id' is null
     and row_data ? 'reported_user_id' then
    row_data := jsonb_set(row_data, '{reported_id}', row_data->'reported_user_id');
  end if;

  return jsonb_populate_record(new, row_data);
end;
$$;

drop trigger if exists sync_report_legacy_columns_trigger on public.reports;
create trigger sync_report_legacy_columns_trigger
before insert or update on public.reports
for each row
execute function public.sync_report_legacy_columns();

alter table public.reports enable row level security;

grant select, insert on public.reports to authenticated;

drop policy if exists "Users can create own reports" on public.reports;
create policy "Users can create own reports"
on public.reports
for insert
to authenticated
with check (
  auth.uid() is not null
  and auth.uid() = reporter_user_id
  and reporter_user_id <> reported_user_id
);

drop policy if exists "Users can read own reports" on public.reports;
create policy "Users can read own reports"
on public.reports
for select
to authenticated
using (
  auth.uid() = reporter_user_id
);

drop policy if exists "Users can upload report proof" on storage.objects;
create policy "Users can upload report proof"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'verification-documents'
  and (storage.foldername(name))[1] = 'reports'
  and (storage.foldername(name))[2] = auth.uid()::text
);

drop policy if exists "Users can update own report proof" on storage.objects;
create policy "Users can update own report proof"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'verification-documents'
  and (storage.foldername(name))[1] = 'reports'
  and (storage.foldername(name))[2] = auth.uid()::text
)
with check (
  bucket_id = 'verification-documents'
  and (storage.foldername(name))[1] = 'reports'
  and (storage.foldername(name))[2] = auth.uid()::text
);

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
    select
      latitude,
      longitude,
      relationship_goal
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
      age_calc.candidate_age,
      viewer_action.action as viewer_action,
      viewer_action.pass_resurface_after,
      coalesce(viewer_action.resurfaced_count, 0) as resurfaced_count,
      (
        viewer_action.action = 'pass'
        and coalesce(p.updated_at, now()) > viewer_action.created_at
      ) as updated_since_pass,
      (
        case
          when requester.relationship_goal is not null
            and p.relationship_goal = requester.relationship_goal
          then 3
          else 0
        end
        +
        case
          when filter.education_level is null
            or filter.education_level = ''
          then 0
          when (
            case lower(coalesce(p.education_level, ''))
              when 'primary' then 0
              when 'primary school' then 0
              when 'secondary' then 1
              when 'secondary school' then 1
              when 'high school' then 1
              when 'spm' then 1
              when 'diploma' then 2
              when 'advanced diploma' then 2
              when 'degree' then 3
              when 'bachelor' then 3
              when 'bachelor''s degree' then 3
              when 'bachelors degree' then 3
              when 'master' then 4
              when 'master''s degree' then 4
              when 'phd' then 5
              when 'doctorate' then 5
              else -1
            end
          ) >= (
            case lower(filter.education_level)
              when 'primary' then 0
              when 'primary school' then 0
              when 'secondary' then 1
              when 'secondary school' then 1
              when 'high school' then 1
              when 'spm' then 1
              when 'diploma' then 2
              when 'advanced diploma' then 2
              when 'degree' then 3
              when 'bachelor' then 3
              when 'bachelor''s degree' then 3
              when 'bachelors degree' then 3
              when 'master' then 4
              when 'master''s degree' then 4
              when 'phd' then 5
              when 'doctorate' then 5
              else 999
            end
          )
          then 2
          else 0
        end
        +
        case
          when filter.preferred_gender is not null
            and p.gender = filter.preferred_gender
          then 2
          else 0
        end
        +
        case
          when p.height_cm is not null
            and p.height_cm >= coalesce(filter.min_height_cm, p.height_cm)
            and p.height_cm <= coalesce(filter.max_height_cm, p.height_cm)
          then 1
          else 0
        end
        +
        case
          when age_calc.candidate_age is not null
            and age_calc.candidate_age >= coalesce(filter.min_age, age_calc.candidate_age)
            and age_calc.candidate_age <= coalesce(filter.max_age, age_calc.candidate_age)
          then 1
          else 0
        end
      ) as compatibility_score,
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
    cross join lateral (
      select coalesce(
        date_part('year', age(current_date, nullif(p.date_of_birth::text, '')::date))::int,
        p.age
      ) as candidate_age
    ) age_calc
    left join filter on true
    left join public.profile_actions viewer_action
      on viewer_action.actor_user_id = requesting_user_id
     and viewer_action.target_user_id = p.id
    where p.id <> requesting_user_id
      and p.full_name is not null
      and coalesce(p.is_deactivated, false) = false
      and coalesce(p.is_discoverable, true) = true
      and (
        coalesce(p.is_banned, false) = false
        or (p.ban_until is not null and p.ban_until <= now())
      )
      and p.verification_status = 'verified'
      and (
        viewer_action.actor_user_id is null
        or (
          viewer_action.action = 'pass'
          and coalesce(viewer_action.pass_resurface_after, viewer_action.created_at + interval '60 days') <= now()
        )
      )
      and viewer_action.action is distinct from 'like'
      and not exists (
        select 1
        from public.blocks b
        where (b.blocker_user_id = requesting_user_id and b.blocked_user_id = p.id)
           or (b.blocked_user_id = requesting_user_id and b.blocker_user_id = p.id)
      )
      and not exists (
        select 1
        from public.user_blocks ub
        where (ub.blocker_user_id = requesting_user_id and ub.blocked_user_id = p.id)
           or (ub.blocked_user_id = requesting_user_id and ub.blocker_user_id = p.id)
      )
      and (filter.preferred_gender is null or p.gender = filter.preferred_gender)
      and (filter.min_age is null or age_calc.candidate_age >= filter.min_age)
      and (filter.max_age is null or age_calc.candidate_age <= filter.max_age)
      and (
        filter.preferred_city is null
        or filter.preferred_city = ''
        or p.city ilike '%' || filter.preferred_city || '%'
      )
      and (filter.min_height_cm is null or p.height_cm >= filter.min_height_cm)
      and (filter.max_height_cm is null or p.height_cm <= filter.max_height_cm)
      and (
        filter.education_level is null
        or filter.education_level = ''
        or (
          case lower(coalesce(p.education_level, ''))
            when 'primary' then 0
            when 'primary school' then 0
            when 'secondary' then 1
            when 'secondary school' then 1
            when 'high school' then 1
            when 'spm' then 1
            when 'diploma' then 2
            when 'advanced diploma' then 2
            when 'degree' then 3
            when 'bachelor' then 3
            when 'bachelor''s degree' then 3
            when 'bachelors degree' then 3
            when 'master' then 4
            when 'master''s degree' then 4
            when 'phd' then 5
            when 'doctorate' then 5
            else -1
          end
        ) >= (
          case lower(filter.education_level)
            when 'primary' then 0
            when 'primary school' then 0
            when 'secondary' then 1
            when 'secondary school' then 1
            when 'high school' then 1
            when 'spm' then 1
            when 'diploma' then 2
            when 'advanced diploma' then 2
            when 'degree' then 3
            when 'bachelor' then 3
            when 'bachelor''s degree' then 3
            when 'bachelors degree' then 3
            when 'master' then 4
            when 'master''s degree' then 4
            when 'phd' then 5
            when 'doctorate' then 5
            else 999
          end
        )
      )
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
  order by
    case when candidates.viewer_action = 'pass' then 1 else 0 end asc,
    case when candidates.updated_since_pass then 0 else 1 end asc,
    coalesce((candidates.profile).is_online, false) desc,
    (candidates.profile).last_seen_at desc nulls last,
    candidates.compatibility_score desc,
    candidates.resurfaced_count asc,
    candidates.distance_km asc nulls last;
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
