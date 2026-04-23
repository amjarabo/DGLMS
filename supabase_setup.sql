-- =====================================================================
-- DGLMS Portal — Supabase setup
-- Paste this entire file into: Supabase dashboard → SQL Editor → New query → Run
-- Safe to run more than once (uses IF NOT EXISTS and drops policies first).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. DOMAIN GATE — reject any email that isn't @dot.gov
-- ---------------------------------------------------------------------
create or replace function public.is_dot_gov_user()
returns boolean
language sql
stable
as $$
  select coalesce(
    lower(auth.jwt() ->> 'email') like '%@dot.gov',
    false
  );
$$;

-- ---------------------------------------------------------------------
-- 2. LOGIN AUDIT TABLE
-- ---------------------------------------------------------------------
create table if not exists public.login_audit (
  id          bigserial primary key,
  user_id     uuid references auth.users(id) on delete set null,
  email       text not null,
  page        text,
  user_agent  text,
  login_at    timestamptz not null default now()
);

create index if not exists login_audit_email_idx on public.login_audit(email);
create index if not exists login_audit_login_at_idx on public.login_audit(login_at desc);

alter table public.login_audit enable row level security;

drop policy if exists "dot.gov can insert own logins" on public.login_audit;
create policy "dot.gov can insert own logins"
  on public.login_audit
  for insert
  to authenticated
  with check (
    public.is_dot_gov_user()
    and lower(email) = lower(auth.jwt() ->> 'email')
  );

drop policy if exists "dot.gov can read all logins" on public.login_audit;
create policy "dot.gov can read all logins"
  on public.login_audit
  for select
  to authenticated
  using ( public.is_dot_gov_user() );

-- ---------------------------------------------------------------------
-- 3. SHARED WORKBOOKS TABLE — parsed Excel/CSV data pushed from the UI
-- ---------------------------------------------------------------------
create table if not exists public.shared_workbooks (
  id            bigserial primary key,
  uploaded_by   uuid references auth.users(id) on delete set null,
  uploader_email text not null,
  section       text not null,        -- which portal page (smoke, regression, testcases, etc.)
  filename      text not null,
  storage_path  text,                 -- path in the "workbooks" storage bucket, if file was uploaded too
  parsed_data   jsonb not null,       -- SheetJS-parsed rows
  row_count     int generated always as (jsonb_array_length(parsed_data)) stored,
  notes         text,
  created_at    timestamptz not null default now()
);

create index if not exists shared_workbooks_section_idx on public.shared_workbooks(section, created_at desc);
create index if not exists shared_workbooks_created_at_idx on public.shared_workbooks(created_at desc);

alter table public.shared_workbooks enable row level security;

drop policy if exists "dot.gov can read all workbooks" on public.shared_workbooks;
create policy "dot.gov can read all workbooks"
  on public.shared_workbooks
  for select
  to authenticated
  using ( public.is_dot_gov_user() );

drop policy if exists "dot.gov can insert workbooks" on public.shared_workbooks;
create policy "dot.gov can insert workbooks"
  on public.shared_workbooks
  for insert
  to authenticated
  with check (
    public.is_dot_gov_user()
    and lower(uploader_email) = lower(auth.jwt() ->> 'email')
  );

drop policy if exists "dot.gov can delete own workbooks" on public.shared_workbooks;
create policy "dot.gov can delete own workbooks"
  on public.shared_workbooks
  for delete
  to authenticated
  using (
    public.is_dot_gov_user()
    and uploaded_by = auth.uid()
  );

-- Enable realtime so everyone sees pushed workbooks within ~1 second
alter publication supabase_realtime add table public.shared_workbooks;

-- ---------------------------------------------------------------------
-- 4. STORAGE BUCKET — original Excel/CSV files (optional, if you want to keep the file too)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('workbooks', 'workbooks', false)
on conflict (id) do nothing;

drop policy if exists "dot.gov can read workbooks bucket" on storage.objects;
create policy "dot.gov can read workbooks bucket"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'workbooks'
    and public.is_dot_gov_user()
  );

drop policy if exists "dot.gov can upload to workbooks bucket" on storage.objects;
create policy "dot.gov can upload to workbooks bucket"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'workbooks'
    and public.is_dot_gov_user()
  );

drop policy if exists "dot.gov can delete own uploads" on storage.objects;
create policy "dot.gov can delete own uploads"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'workbooks'
    and public.is_dot_gov_user()
    and owner = auth.uid()
  );

-- ---------------------------------------------------------------------
-- 5. DONE
-- ---------------------------------------------------------------------
-- Next steps (do these in the Supabase dashboard UI, not SQL):
--
-- a) Authentication → Providers → Email → make sure "Enable email provider" is ON
--                                        and "Confirm email" is OFF (or ON if you want
--                                        invited users to confirm before first login)
--
-- b) Authentication → URL Configuration → Site URL
--    Set to wherever your GitHub Pages portal lives, e.g.
--      https://your-username.github.io/dglms-portal/
--    (or http://localhost:5500/ for local testing)
--
-- c) Authentication → Users → Add user → Send invite
--    Add each @dot.gov teammate one at a time. They'll receive an email
--    with a link to set their password.
--
-- d) Confirm it worked: run this query after your first login
--      select email, page, login_at from public.login_audit order by login_at desc limit 10;
