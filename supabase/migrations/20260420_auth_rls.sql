-- ============================================================================
-- 20260420_auth_rls.sql
-- Multi-user auth: audit log, editor tracking, and RLS policies.
--
-- Model: any authenticated user can do anything. Every write is stamped with
-- the user's id + timestamp, and copied into job_edits as a durable audit trail.
-- Tighter scoping (per-job teams, roles) can be layered on later by modifying
-- the policies below.
-- ============================================================================

-- --------------------------------------------------------
-- 1. Editor tracking on jobs
-- --------------------------------------------------------
alter table public.jobs
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_by uuid references auth.users(id),
  add column if not exists updated_at timestamptz not null default now();

-- --------------------------------------------------------
-- 2. Audit log table — every save appends a row
-- --------------------------------------------------------
create table if not exists public.job_edits (
  id           bigserial primary key,
  job_id       text not null,
  user_id      uuid references auth.users(id),
  user_email   text,
  action       text not null check (action in ('create','update','delete')),
  summary      text,
  created_at   timestamptz not null default now()
);
create index if not exists idx_job_edits_job_id    on public.job_edits(job_id);
create index if not exists idx_job_edits_created   on public.job_edits(created_at desc);
create index if not exists idx_job_edits_user      on public.job_edits(user_id);

-- --------------------------------------------------------
-- 3. RLS on jobs — authenticated users have full CRUD
-- --------------------------------------------------------
alter table public.jobs enable row level security;

drop policy if exists "auth users select jobs" on public.jobs;
drop policy if exists "auth users insert jobs" on public.jobs;
drop policy if exists "auth users update jobs" on public.jobs;
drop policy if exists "auth users delete jobs" on public.jobs;

create policy "auth users select jobs" on public.jobs
  for select to authenticated using (true);
create policy "auth users insert jobs" on public.jobs
  for insert to authenticated with check (true);
create policy "auth users update jobs" on public.jobs
  for update to authenticated using (true) with check (true);
create policy "auth users delete jobs" on public.jobs
  for delete to authenticated using (true);

-- --------------------------------------------------------
-- 4. RLS on job_edits — authenticated can read; can only
--    insert rows tagged with their own user_id
-- --------------------------------------------------------
alter table public.job_edits enable row level security;

drop policy if exists "auth users select edits" on public.job_edits;
drop policy if exists "auth users insert edits" on public.job_edits;

create policy "auth users select edits" on public.job_edits
  for select to authenticated using (true);
create policy "auth users insert edits" on public.job_edits
  for insert to authenticated with check (auth.uid() = user_id);

-- --------------------------------------------------------
-- 5. RLS on HCSS read-only tables (writes happen via Edge
--    Functions with the service role, which bypasses RLS).
--    Clients only need SELECT.
-- --------------------------------------------------------
alter table public.hcss_equipment enable row level security;
drop policy if exists "anon read hcss_equipment"           on public.hcss_equipment;
drop policy if exists "auth users select equipment"        on public.hcss_equipment;
create policy "auth users select equipment" on public.hcss_equipment
  for select to authenticated using (true);

alter table public.hcss_equipment_history enable row level security;
drop policy if exists "anon read hcss_equipment_history"   on public.hcss_equipment_history;
drop policy if exists "auth users select equipment history" on public.hcss_equipment_history;
create policy "auth users select equipment history" on public.hcss_equipment_history
  for select to authenticated using (true);

alter table public.hcss_jobs enable row level security;
drop policy if exists "anon read hcss_jobs"                on public.hcss_jobs;
drop policy if exists "auth users select hcss jobs"        on public.hcss_jobs;
create policy "auth users select hcss jobs" on public.hcss_jobs
  for select to authenticated using (true);

alter table public.hcss_cost_codes enable row level security;
drop policy if exists "anon read hcss_cost_codes"          on public.hcss_cost_codes;
drop policy if exists "auth users select cost codes"       on public.hcss_cost_codes;
create policy "auth users select cost codes" on public.hcss_cost_codes
  for select to authenticated using (true);

alter table public.actuals_detail_sync enable row level security;
-- Drop the original anon-read policy from 20260409_hcss_sync.sql
drop policy if exists "anon read actuals"        on public.actuals_detail_sync;
drop policy if exists "auth users select actuals" on public.actuals_detail_sync;
create policy "auth users select actuals" on public.actuals_detail_sync
  for select to authenticated using (true);

-- sync_log: replace the old anon-read policy with authenticated-only.
-- (Edge Functions continue to bypass RLS via the service role key.)
alter table public.sync_log enable row level security;
drop policy if exists "anon read sync_log"        on public.sync_log;
drop policy if exists "auth users select sync log" on public.sync_log;
create policy "auth users select sync log" on public.sync_log
  for select to authenticated using (true);

-- The sync_status view reads from sync_log. Grant view-level select to
-- authenticated so the dashboard "last sync" indicator keeps working.
-- (Anon grant from the original migration is left alone — it's harmless
-- because the underlying sync_log RLS now blocks anon anyway.)
grant select on public.sync_status to authenticated;

-- Old anon-read policies are dropped inline above where the target table's
-- RLS is being reconfigured. Nothing else needs revoking — the HCSS tables
-- were enabled with RLS but never had permissive anon policies attached.
