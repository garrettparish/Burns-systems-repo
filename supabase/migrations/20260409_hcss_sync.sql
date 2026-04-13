-- ============================================================
-- HCSS Sync — Phase 1 (HeavyJob daily actuals)
-- Burns Project Controls
-- ============================================================
-- Creates two tables:
--   1. actuals_detail_sync — one row per (job, date, cost_code, foreman)
--      Matches the shape produced by parseActualsDetailRaw() in index.html
--      so the front-end can consume it with zero translation.
--   2. sync_log — audit trail of every run (cron or manual)
--
-- Also schedules the hcss-sync-actuals Edge Function to run daily
-- at 05:00 America/Chicago (10:00 UTC) via pg_cron + pg_net.
--
-- Idempotent: safe to re-run. Uses IF NOT EXISTS / ON CONFLICT.
-- ============================================================

-- --- extensions ---------------------------------------------
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- --- actuals_detail_sync ------------------------------------
create table if not exists public.actuals_detail_sync (
  job_number          text        not null,
  date                date        not null,
  cost_code           text        not null,
  foreman             text        not null default '',
  cost_code_desc      text        default '',
  unit                text        default '',
  actual_qty          numeric     default 0,
  actual_labor_hours  numeric     default 0,
  actual_equip_hours  numeric     default 0,
  actual_labor_cost   numeric     default 0,
  actual_equip_cost   numeric     default 0,
  actual_mat_cost     numeric     default 0,
  actual_sub_cost     numeric     default 0,
  expected_labor_hours numeric    default 0,
  expected_labor_cost  numeric    default 0,
  expected_equip_cost  numeric    default 0,
  expected_mat_cost    numeric    default 0,
  expected_sub_cost    numeric    default 0,
  source              text        not null default 'hcss-api',
  synced_at           timestamptz not null default now(),
  primary key (job_number, date, cost_code, foreman)
);

create index if not exists actuals_detail_sync_job_idx
  on public.actuals_detail_sync (job_number);
create index if not exists actuals_detail_sync_date_idx
  on public.actuals_detail_sync (date desc);

comment on table public.actuals_detail_sync is
  'HCSS-synced daily actuals. Primary key matches parseActualsDetailRaw _key. Front-end reads this in place of XLSX import.';

-- --- sync_log -----------------------------------------------
create table if not exists public.sync_log (
  id              bigserial primary key,
  run_at          timestamptz not null default now(),
  kind            text        not null,                   -- 'actuals' | 'activities' | 'manual' | 'discover'
  status          text        not null,                   -- 'success' | 'error' | 'partial'
  trigger         text        not null default 'cron',    -- 'cron' | 'manual' | 'api'
  jobs_synced     int         default 0,
  rows_inserted   int         default 0,
  rows_updated    int         default 0,
  rows_unchanged  int         default 0,
  duration_ms     int         default 0,
  error_message   text,
  details         jsonb
);

create index if not exists sync_log_run_at_idx
  on public.sync_log (run_at desc);

comment on table public.sync_log is
  'Every HCSS sync run (cron or manual). Query ORDER BY run_at DESC LIMIT 1 for latest sync status.';

-- --- row-level security -------------------------------------
-- Allow anon key to read (same as existing jobs table pattern).
-- Writes are done by the Edge Function using the service_role key,
-- which bypasses RLS automatically.
alter table public.actuals_detail_sync enable row level security;
alter table public.sync_log            enable row level security;

drop policy if exists "anon read actuals" on public.actuals_detail_sync;
create policy "anon read actuals" on public.actuals_detail_sync
  for select using (true);

drop policy if exists "anon read sync_log" on public.sync_log;
create policy "anon read sync_log" on public.sync_log
  for select using (true);

-- --- daily cron schedule ------------------------------------
-- 10:00 UTC = 05:00 America/Chicago (5 AM CT, works for both CDT and CST
--  — CT is 6 AM during DST but close enough; adjust if you prefer strict 5 AM local).
-- NOTE: requires the following to be set ONCE via the SQL editor before
-- the schedule can dispatch (we cannot put a real secret in a migration):
--
--   alter database postgres set "app.hcss_sync_url"    = 'https://<project>.functions.supabase.co/hcss-sync-actuals';
--   alter database postgres set "app.hcss_sync_secret" = '<service_role_jwt>';
--
-- Re-run this section after setting those values if the job doesn't appear.

-- Unschedule any previous version before re-adding (idempotent).
do $$
declare jid int;
begin
  select jobid into jid from cron.job where jobname = 'hcss-sync-actuals-daily';
  if jid is not null then
    perform cron.unschedule(jid);
  end if;
end $$;

select cron.schedule(
  'hcss-sync-actuals-daily',
  '0 10 * * *',
  $cron$
    select net.http_post(
      url     := current_setting('app.hcss_sync_url', true),
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || current_setting('app.hcss_sync_secret', true)
      ),
      body    := jsonb_build_object('trigger', 'cron')
    );
  $cron$
);

-- --- sanity check view --------------------------------------
-- Convenience view the front-end can use for "Last synced" banner.
create or replace view public.sync_status as
select
  (select run_at from public.sync_log where kind='actuals' and status='success'
     order by run_at desc limit 1) as last_success_at,
  (select run_at from public.sync_log where kind='actuals'
     order by run_at desc limit 1) as last_run_at,
  (select status from public.sync_log where kind='actuals'
     order by run_at desc limit 1) as last_run_status,
  (select rows_inserted + rows_updated from public.sync_log where kind='actuals'
     order by run_at desc limit 1) as last_row_count,
  (select error_message from public.sync_log where kind='actuals'
     order by run_at desc limit 1) as last_error,
  (select count(*) from public.actuals_detail_sync) as total_rows,
  (select count(distinct job_number) from public.actuals_detail_sync) as jobs_covered;

grant select on public.sync_status to anon;
