-- ============================================================
-- HCSS Equipment Day-by-Day History
-- Burns Project Controls
-- ============================================================
-- One row per (hcss_code, date, job_code). Feeds the Equipment
-- Planner's weekly + 16-week views so past cells auto-populate
-- with the job each machine was actually on that day (mirrors
-- the crew history pattern in Store.crewHistory).
-- ============================================================

create table if not exists public.hcss_equipment_history (
  hcss_code   text  not null,
  date        date  not null,
  job_code    text  not null,
  hours       numeric default 0,
  synced_at   timestamptz not null default now(),
  primary key (hcss_code, date, job_code)
);

create index if not exists hcss_equipment_history_code_date_idx
  on public.hcss_equipment_history (hcss_code, date desc);

create index if not exists hcss_equipment_history_date_idx
  on public.hcss_equipment_history (date desc);

comment on table public.hcss_equipment_history is
  'Per-day equipment observations from HeavyJob timecards. Drives auto-populated past cells in the Equipment Planner, mirroring Store.crewHistory for crews.';

-- --- RLS --------------------------------------------------------
alter table public.hcss_equipment_history enable row level security;

drop policy if exists "anon read hcss_equipment_history" on public.hcss_equipment_history;
create policy "anon read hcss_equipment_history" on public.hcss_equipment_history
  for select using (true);
