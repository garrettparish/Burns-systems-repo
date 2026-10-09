-- ============================================================================
-- people_monitor_rpc.sql — apply to the PEOPLE OS project (sthianwnfwmhkturtyem, talentandculture).
-- NOT a Project Controls migration; lives here beside the monitor it feeds.
--
-- Read-only: exposes the last N hours of public.sync_log (source, status, time, record count,
-- first 200 chars of the error, error count) so the System Health board can judge the BambooHR
-- syncs by their real outcome without needing a code change in People OS's deploy.
-- Callable with the project's public anon key; returns no employee data.
-- ============================================================================
create or replace function public.monitor_sync_log(since_hours int default 72)
returns table (id uuid, source text, status text, synced_at timestamptz, records_synced int, error_message text, errors int)
language sql
security definer
set search_path = public, pg_temp
as $$
  select l.id, l.source, l.status, l.synced_at, l.records_synced,
         left(l.error_message, 200),
         case when jsonb_typeof(l.meta -> 'errors') = 'array' then jsonb_array_length(l.meta -> 'errors') else 0 end
    from public.sync_log l
   where l.synced_at > now() - make_interval(hours => least(greatest(since_hours, 1), 336))
   order by l.synced_at desc
   limit 500;
$$;

revoke all on function public.monitor_sync_log(int) from public;
grant execute on function public.monitor_sync_log(int) to anon, authenticated;
