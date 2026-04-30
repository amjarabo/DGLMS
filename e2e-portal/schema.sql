-- ============================================================================
-- DGLMS E2E Portal — Supabase Schema v6
-- Paste this entire file into Supabase SQL Editor and run it.
-- Safe to run multiple times (uses IF NOT EXISTS / ON CONFLICT patterns).
-- ============================================================================

-- ============================================================================
-- 1. APP USERS — auto-populated on first login (mirrors auth.users)
-- ============================================================================
create table if not exists public.app_users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text unique not null,
  display_name text,
  role text not null default 'user' check (role in ('admin', 'user', 'guest')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz
);

-- Auto-create app_users row on first login
create or replace function public.handle_new_user() returns trigger as $$
begin
  insert into public.app_users (id, email, display_name, role)
  values (
    new.id,
    lower(new.email),
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)),
    'user'
  )
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ============================================================================
-- 2. ROLES — quick-lookup view of who's an admin
-- ============================================================================
create or replace view public.is_admin_view as
  select id, email from public.app_users where role = 'admin';

-- Helper function used in RLS policies
create or replace function public.is_admin() returns boolean
language sql security definer
as $$
  select coalesce(
    (select role = 'admin' from public.app_users where id = auth.uid()),
    false
  );
$$;

create or replace function public.is_guest() returns boolean
language sql security definer
as $$
  select coalesce(
    (select role = 'guest' from public.app_users where id = auth.uid()),
    false
  );
$$;


-- ============================================================================
-- 3. TEST RESULTS — one row per (tester, env, persona, test_case)
-- ============================================================================
create table if not exists public.test_results (
  id bigserial primary key,
  test_case_id text not null,
  environment text not null check (environment in ('qa', 'uat', 'prod')),
  persona text not null,
  result text not null default 'pending' check (result in ('pending', 'pass', 'fail', 'inconclusive')),
  tester_email text not null,
  tester_id uuid references public.app_users(id) on delete cascade,
  test_date date,
  evidence_link text,
  comments text,
  signed_off boolean not null default false,
  signed_off_at timestamptz,
  result_timestamp timestamptz,
  substeps jsonb default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tester_id, environment, persona, test_case_id)
);

create index if not exists idx_test_results_tester on public.test_results(tester_id);
create index if not exists idx_test_results_env on public.test_results(environment);
create index if not exists idx_test_results_tc on public.test_results(test_case_id);

-- Auto-update updated_at on every change
create or replace function public.set_updated_at() returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql;

drop trigger if exists test_results_updated_at on public.test_results;
create trigger test_results_updated_at
  before update on public.test_results
  for each row execute function public.set_updated_at();


-- ============================================================================
-- 4. ISSUES — one row per logged issue
-- ============================================================================
create table if not exists public.issues (
  id bigserial primary key,
  issue_number int generated always as identity,
  title text not null,
  test_case_id text,
  environment text check (environment in ('qa', 'uat', 'prod')),
  persona text,
  tester_email text not null,
  tester_id uuid references public.app_users(id) on delete set null,
  test_date date,
  behavior text not null,
  expected_behavior text,
  screenshot_link text,
  severity text not null default 'Medium' check (severity in ('Low', 'Medium', 'High', 'Critical')),
  status text not null default 'Open' check (status in ('Open', 'In Review', 'Fixed', 'Won''t Fix', 'Duplicate')),
  logged_at timestamptz not null default now()
);

create index if not exists idx_issues_status on public.issues(status);
create index if not exists idx_issues_severity on public.issues(severity);


-- ============================================================================
-- 5. ISSUE RECIPIENTS — who gets emailed when an issue is logged
-- ============================================================================
create table if not exists public.issue_recipients (
  id bigserial primary key,
  display_name text,
  recipient_email text not null unique,
  active boolean not null default true,
  notify_on_severity text[] not null default array['Low','Medium','High','Critical'],
  created_at timestamptz not null default now()
);

-- Seed yourself as the first recipient
insert into public.issue_recipients (display_name, recipient_email, active, notify_on_severity)
values ('Ana Jarabo (Admin)', 'ana.jarabo.ctr@dot.gov', true, array['Low','Medium','High','Critical'])
on conflict (recipient_email) do nothing;


-- ============================================================================
-- 6. SPRINT/PROJECT METADATA (for future flexibility)
-- ============================================================================
create table if not exists public.sprints (
  id bigserial primary key,
  name text not null,
  description text,
  start_date date,
  end_date date,
  status text not null default 'active' check (status in ('planning', 'active', 'completed', 'archived')),
  metadata jsonb default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.test_cases (
  id bigserial primary key,
  test_case_id text not null unique,
  title text not null,
  persona text not null,
  type text default 'Functional',
  story text,
  prerequisites text,
  instructions text,
  expected text,
  negative text,
  fields text,
  sprint_id bigint references public.sprints(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists idx_test_cases_persona on public.test_cases(persona);


-- ============================================================================
-- 7. ROW LEVEL SECURITY POLICIES
-- ============================================================================

-- Enable RLS on every table
alter table public.app_users enable row level security;
alter table public.test_results enable row level security;
alter table public.issues enable row level security;
alter table public.issue_recipients enable row level security;
alter table public.sprints enable row level security;
alter table public.test_cases enable row level security;

-- ---------- app_users ----------
drop policy if exists "Users can view their own row" on public.app_users;
drop policy if exists "Admins can view all users" on public.app_users;
drop policy if exists "Admins can update users" on public.app_users;
drop policy if exists "Authenticated users can read all" on public.app_users;

create policy "Authenticated users can read all"
  on public.app_users for select
  to authenticated
  using (true);

create policy "Admins can update users"
  on public.app_users for update
  to authenticated
  using (public.is_admin());


-- ---------- test_results ----------
drop policy if exists "Anyone authenticated can read all results" on public.test_results;
drop policy if exists "Users can insert their own results" on public.test_results;
drop policy if exists "Users can update their own results" on public.test_results;
drop policy if exists "Admins can do anything" on public.test_results;
drop policy if exists "Guests cannot write" on public.test_results;

-- Reading: everyone authenticated can read (so the team-wide overview works)
create policy "Anyone authenticated can read all results"
  on public.test_results for select
  to authenticated
  using (true);

-- Inserting: must be the current user, and not a guest
create policy "Users can insert their own results"
  on public.test_results for insert
  to authenticated
  with check (
    auth.uid() = tester_id
    and not public.is_guest()
  );

-- Updating: must be your own row, and not a guest (admins can update anyone's via separate policy)
create policy "Users can update their own results"
  on public.test_results for update
  to authenticated
  using (
    (auth.uid() = tester_id and not public.is_guest())
    or public.is_admin()
  );

-- Deleting: only admins
create policy "Only admins can delete results"
  on public.test_results for delete
  to authenticated
  using (public.is_admin());


-- ---------- issues ----------
drop policy if exists "Anyone authenticated can read all issues" on public.issues;
drop policy if exists "Users can insert issues" on public.issues;
drop policy if exists "Admins can update issues" on public.issues;

create policy "Anyone authenticated can read all issues"
  on public.issues for select
  to authenticated
  using (true);

create policy "Users can insert issues"
  on public.issues for insert
  to authenticated
  with check (
    auth.uid() = tester_id
    and not public.is_guest()
  );

create policy "Admins can update issues"
  on public.issues for update
  to authenticated
  using (public.is_admin());

create policy "Admins can delete issues"
  on public.issues for delete
  to authenticated
  using (public.is_admin());


-- ---------- issue_recipients ----------
drop policy if exists "Anyone authenticated can read recipients" on public.issue_recipients;
drop policy if exists "Admins can manage recipients" on public.issue_recipients;

create policy "Anyone authenticated can read recipients"
  on public.issue_recipients for select
  to authenticated
  using (true);

create policy "Admins can manage recipients"
  on public.issue_recipients for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());


-- ---------- sprints + test_cases ----------
drop policy if exists "Anyone authenticated can read sprints" on public.sprints;
drop policy if exists "Admins can manage sprints" on public.sprints;
drop policy if exists "Anyone authenticated can read test cases" on public.test_cases;
drop policy if exists "Admins can manage test cases" on public.test_cases;

create policy "Anyone authenticated can read sprints"
  on public.sprints for select
  to authenticated
  using (true);

create policy "Admins can manage sprints"
  on public.sprints for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

create policy "Anyone authenticated can read test cases"
  on public.test_cases for select
  to authenticated
  using (true);

create policy "Admins can manage test cases"
  on public.test_cases for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());


-- ============================================================================
-- 8. REALTIME — enable WebSocket subscriptions
-- ============================================================================
alter publication supabase_realtime add table public.test_results;
alter publication supabase_realtime add table public.issues;


-- ============================================================================
-- 9. INITIAL ADMIN — promote yourself
-- ============================================================================
-- This runs after you log in for the first time and your row exists in app_users.
-- Run it manually after your first magic-link login.
-- (It's commented out so it doesn't error before you log in.)

-- update public.app_users set role = 'admin' where email = 'ana.jarabo.ctr@dot.gov';


-- ============================================================================
-- DONE — verify
-- ============================================================================
select 'Schema setup complete!' as status,
       (select count(*) from information_schema.tables where table_schema = 'public') as tables_created;
