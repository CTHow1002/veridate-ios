-- VeriDate admin review dashboard support table.
-- Run this only if your project does not already have verification_submissions.

create table if not exists public.verification_submissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'verified', 'rejected')),
  selfie_file_path text not null,
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
add column if not exists selfie_file_path text;

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
