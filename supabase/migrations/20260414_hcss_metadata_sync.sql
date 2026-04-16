-- ============================================================
-- HCSS Metadata Sync — Jobs & Cost Codes
-- Burns Project Controls
-- ============================================================
-- Stores job list and cost code definitions pulled from the
-- HCSS HeavyJob API. These are lightweight reference tables
-- that help auto-match HCSS jobs to project controls jobs
-- and auto-populate cost code definitions.
-- ============================================================

-- --- hcss_jobs ------------------------------------------------
create table if not exists public.hcss_jobs (
  hcss_id             text        primary key,   -- UUID from HCSS
  job_code            text        not null,
  job_name            text        default '',
  status              text        default '',
  start_date          date,
  end_date            date,
  business_unit_id    text        default '',
  business_unit_code  text        default '',
  raw                 jsonb,                      -- full API response for reference
  synced_at           timestamptz not null default now()
);

create index if not exists hcss_jobs_code_idx on public.hcss_jobs (job_code);

comment on table public.hcss_jobs is
  'HeavyJob job list synced via HCSS API. Used to auto-match with project controls jobs.';

-- --- hcss_cost_codes ------------------------------------------
create table if not exists public.hcss_cost_codes (
  id                  bigserial   primary key,
  hcss_job_id         text        not null references public.hcss_jobs(hcss_id) on delete cascade,
  job_code            text        not null,
  cost_code           text        not null,
  description         text        default '',
  unit                text        default '',
  is_hidden           boolean     default false,
  quantity_driven     boolean     default false,
  raw                 jsonb,
  synced_at           timestamptz not null default now(),
  unique (hcss_job_id, cost_code)
);

create index if not exists hcss_cc_job_idx on public.hcss_cost_codes (job_code);

comment on table public.hcss_cost_codes is
  'Cost code definitions per job from HeavyJob API. Keyed by (hcss_job_id, cost_code).';

-- --- RLS -------------------------------------------------------
alter table public.hcss_jobs        enable row level security;
alter table public.hcss_cost_codes  enable row level security;

drop policy if exists "anon read hcss_jobs" on public.hcss_jobs;
create policy "anon read hcss_jobs" on public.hcss_jobs
  for select using (true);

drop policy if exists "anon read hcss_cost_codes" on public.hcss_cost_codes;
create policy "anon read hcss_cost_codes" on public.hcss_cost_codes
  for select using (true);
