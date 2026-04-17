-- ============================================================
-- HCSS Equipment Auto-Discovery
-- Burns Project Controls
-- ============================================================
-- Stores equipment codes auto-extracted from HeavyJob timecard
-- details. User-assigned fields (category, notes, manual location
-- override) live in the front-end Store.equipment (localStorage);
-- this table is the source of truth ONLY for HCSS-derived fields
-- (code, description, last seen job/date).
-- ============================================================

create table if not exists public.hcss_equipment (
  hcss_code           text        primary key,
  description         text        default '',
  last_seen_job_code  text        default '',
  last_seen_date      date,
  times_seen          integer     default 1,
  raw                 jsonb,
  first_seen_at       timestamptz not null default now(),
  synced_at           timestamptz not null default now()
);

create index if not exists hcss_equipment_last_seen_idx
  on public.hcss_equipment (last_seen_date desc);

comment on table public.hcss_equipment is
  'Auto-discovered equipment from HeavyJob timecards. Source of truth for HCSS-derived fields only; user-assigned category/notes live in front-end localStorage.';

-- --- RLS --------------------------------------------------------
alter table public.hcss_equipment enable row level security;

drop policy if exists "anon read hcss_equipment" on public.hcss_equipment;
create policy "anon read hcss_equipment" on public.hcss_equipment
  for select using (true);
