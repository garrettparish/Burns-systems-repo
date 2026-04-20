-- ═══════════════════════════════════════════════════════════════════════════
-- Migration: tab_guides
-- Purpose: Store per-tab Quick Guide (short "what is this") + SOP (how-to)
--          content, editable in-app and persisted across users.
-- Run in: burns-project-controls Supabase (project ref sxzvlazmkxnbsoayhuln)
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.tab_guides (
  tab_id       text primary key,
  quick_guide  text default '',
  sop          text default '',
  updated_at   timestamptz not null default now(),
  updated_by   text
);

-- Timestamp trigger
create or replace function public._touch_tab_guides_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_tab_guides_updated_at on public.tab_guides;
create trigger trg_tab_guides_updated_at
  before update on public.tab_guides
  for each row execute function public._touch_tab_guides_updated_at();

-- RLS — read for any authenticated user, write for any authenticated user.
-- Adjust later if you want to restrict edit rights (e.g., only PMs).
alter table public.tab_guides enable row level security;

drop policy if exists "tab_guides_read_auth" on public.tab_guides;
create policy "tab_guides_read_auth"
  on public.tab_guides for select
  to authenticated using (true);

drop policy if exists "tab_guides_write_auth" on public.tab_guides;
create policy "tab_guides_write_auth"
  on public.tab_guides for insert
  to authenticated with check (true);

drop policy if exists "tab_guides_update_auth" on public.tab_guides;
create policy "tab_guides_update_auth"
  on public.tab_guides for update
  to authenticated using (true) with check (true);

-- No delete policy — guides are updated in place, not deleted.

-- Index (tiny table, but clean)
comment on table public.tab_guides is 'Per-tab Quick Guide + SOP content, editable in the Burns PCS app.';
