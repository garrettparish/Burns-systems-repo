-- 2026-04-28 — Add hcss_job_costs table for the new POST /jobCosts/advancedRequest sync.
-- This is the bridge that gives us fresh per-(date × cost code × foreman) BELMOS dollars
-- without waiting on Spectrum's 30-day lag. Production Tracker will read $ from here
-- once the syncJobCosts Edge Function mode lands.

create table if not exists public.hcss_job_costs (
  job_number      text         not null,
  date            date         not null,
  cost_code       text         not null,
  cost_code_id    text         default '',          -- HCSS UUID for backfill / debugging
  foreman_id      text         not null default '',
  foreman_name    text         default '',          -- resolved from timecards when possible
  qty             numeric      default 0,
  labor_hours     numeric      default 0,
  labor_cost      numeric      default 0,
  equip_hours     numeric      default 0,
  equip_cost      numeric      default 0,
  mat_cost        numeric      default 0,
  sub_cost        numeric      default 0,
  trucking_cost   numeric      default 0,
  source          text         not null default 'hcss-jobcosts-api',
  synced_at       timestamptz  not null default now(),
  primary key (job_number, date, cost_code, foreman_id)
);

create index if not exists hcss_job_costs_job_date_idx
  on public.hcss_job_costs (job_number, date);

create index if not exists hcss_job_costs_costcode_idx
  on public.hcss_job_costs (job_number, cost_code);

alter table public.hcss_job_costs enable row level security;

drop policy if exists "anon read hcss_job_costs" on public.hcss_job_costs;
create policy "anon read hcss_job_costs"
  on public.hcss_job_costs
  for select
  to anon
  using (true);

-- Capture HCSS cost code UUID in the metadata sync so we can join jobCosts rows
-- back to the cost_code string locally instead of round-tripping the costCodes
-- endpoint on every job-cost sync.
alter table public.hcss_cost_codes
  add column if not exists cost_code_id text default '';

create index if not exists hcss_cost_codes_costcodeid_idx
  on public.hcss_cost_codes (cost_code_id);
