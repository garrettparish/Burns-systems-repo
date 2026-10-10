-- ============================================================================
-- waste_monitor_rpc.sql — apply to the WASTE OS project (xgrbfeeupeaadfwwospv).
-- NOT a Project Controls migration; lives here beside the monitor it feeds.
--
-- Read-only: the last N hours of the CurbWaste pull's run logs (cw_sync_runs, cw_inventory_sync_runs),
-- reshaped to the columns monitor-pull-remote expects (same as the People OS feed). Callable with the
-- project's public anon key, so it returns NO business numbers: on a successful run the note text
-- (which carries the A/R balance) is dropped; on a failed run only the first 200 characters of the error.
--   cw_dispatch   dispatch window replace   (cw_sync_runs rows that are not A/R notes)
--   cw_ar         A/R snapshot              (cw_sync_runs rows whose note starts 'AR ' / 'AR_ERR')
--   cw_inventory  container inventory       (cw_inventory_sync_runs)
-- Dry runs are excluded. Written by burnsbox waste-cw-pull (and, until 2026-10-08, the Netlify job).
-- ============================================================================
create or replace function public.monitor_cw_runs(since_hours int default 72)
returns table (id text, source text, status text, synced_at timestamptz, records_synced int, error_message text, errors int)
language sql
security definer
set search_path = public, pg_temp
as $$
  select 'sync-' || r.id,
         case when r.error like 'AR %' or r.error like 'AR\_ERR%' then 'cw_ar' else 'cw_dispatch' end,
         case when r.ok then 'success' else 'error' end,
         r.ran_at,
         r.rows::int,
         case when r.ok then null else left(r.error, 200) end,
         0
    from public.cw_sync_runs r
   where not r.dry and r.ran_at > now() - make_interval(hours => least(greatest(since_hours, 1), 336))
  union all
  select 'inv-' || i.id,
         'cw_inventory',
         case when i.ok then 'success' else 'error' end,
         i.ran_at,
         i.mapped,
         case when i.ok then null else left(i.error, 200) end,
         0
    from public.cw_inventory_sync_runs i
   where not i.dry and i.ran_at > now() - make_interval(hours => least(greatest(since_hours, 1), 336))
  order by 4 desc
  limit 500;
$$;

revoke all on function public.monitor_cw_runs(int) from public;
grant execute on function public.monitor_cw_runs(int) to anon, authenticated;
