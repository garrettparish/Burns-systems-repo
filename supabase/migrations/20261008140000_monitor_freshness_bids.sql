-- ============================================================================
-- 20261008140000_monitor_freshness_bids.sql
-- Next monitor sources:
--   1. Freshness evidence — for jobs that write a table in THIS database but keep
--      no run log (Dirt OS Netlify jobs). A pg_cron tick turns "newest row in
--      <table>.<column>" into a heartbeat dated at that timestamp, so a job that
--      stops writing simply stops producing events and goes `late`.
--   2. Bids Netlify jobs — registered here; they report via the monitor-report
--      Edge Function (burns-bids netlify/functions/lib/monitor.js wrapper).
--   3. Retention — monitor_event keeps 30 days (status reads 14).
-- ============================================================================

alter table public.monitor_source add column if not exists freshness_table  text;
alter table public.monitor_source add column if not exists freshness_column text;

create or replace function public.monitor_freshness_tick()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  s record;
  rel regclass;
  newest timestamptz;
  n integer := 0;
begin
  for s in select key, freshness_table, freshness_column
             from monitor_source
            where enabled and freshness_table is not null and freshness_column is not null
  loop
    rel := to_regclass(s.freshness_table);
    if rel is null then
      continue;                       -- registered but the table is gone: stays silent -> flagged
    end if;
    execute format('select max(%I)::timestamptz from %s', s.freshness_column, rel) into newest;
    if newest is null then
      continue;
    end if;
    insert into monitor_event (source_key, at, status, message, external_id)
    values (s.key, newest, 'ok',
            'newest ' || s.freshness_table || '.' || s.freshness_column || ' = ' || to_char(newest at time zone 'America/Chicago', 'Mon DD HH24:MI') || ' CT',
            'fresh:' || extract(epoch from newest)::bigint)
    on conflict (source_key, external_id) do nothing;
    if found then n := n + 1; end if;
  end loop;
  return n;
end;
$$;

revoke all on function public.monitor_freshness_tick() from public, anon, authenticated;

select cron.schedule('monitor-freshness', '*/10 * * * *', $$ select public.monitor_freshness_tick(); $$);
select cron.schedule('monitor-retention', '17 6 * * *',
  $$ delete from public.monitor_event where at < now() - interval '30 days' $$);

-- --------------------------------------------------------
-- Dirt OS jobs judged by data freshness (same database as this monitor)
-- --------------------------------------------------------
insert into public.monitor_source
  (key, tool, type, name, description, expected_interval_min, grace_min, severity, weekdays_only, freshness_table, freshness_column)
values
  ('dirtos:visionlink-sync','VisionLink','sync','VisionLink assets sync (hourly)','burns-dirt-os visionlink-sync.cjs, :10 past each hour. Judged by newest burns_dirt.visionlink_assets.synced_at.',60,90,'normal',false,'burns_dirt.visionlink_assets','synced_at'),
  ('dirtos:hcss-safety-sync','HCSS','sync','HCSS safety incidents sync','burns-dirt-os hcss-safety-sync.ts, 12:00 UTC. Judged by newest public.hcss_safety_incidents.synced_at.',1440,180,'normal',false,'public.hcss_safety_incidents','synced_at'),
  ('dirtos:finance-actuals-mirror','Dirt OS','sync','Finance actuals mirror (cost/AP/receipts)','burns-dirt-os sync-finance-actuals.ts, 10:30 UTC weekdays. Judged by newest public.job_cost_monthly.synced_at.',1440,180,'high',true,'public.job_cost_monthly','synced_at'),
  ('dirtos:weather-daily-log','Dirt OS','sync','Weather daily log','burns-dirt-os weather-daily-log.ts, 11:15 UTC. Judged by newest public.weather_log.created_at.',1440,180,'low',false,'public.weather_log','created_at')
on conflict (key) do nothing;

-- --------------------------------------------------------
-- Bids jobs (heartbeat evidence from the withMonitor wrapper)
-- --------------------------------------------------------
insert into public.monitor_source
  (key, tool, type, name, description, expected_interval_min, grace_min, severity, weekdays_only)
values
  ('bids:scrape-mdot','Bids','api','MDOT scraper','12:00 UTC daily. A run that completes with 0 new rows is OK; an exception or per-record errors are flagged.',1440,240,'normal',false),
  ('bids:scrape-aldot','Bids','api','ALDOT scraper','12:15 UTC daily',1440,240,'normal',false),
  ('bids:scrape-tdot','Bids','api','TDOT scraper','12:30 UTC daily',1440,240,'normal',false),
  ('bids:scrape-sam','Bids','api','SAM.gov scraper','13:00 UTC daily (no new rows since 2026-06-24 at time of writing)',1440,240,'normal',false),
  ('bids:scrape-planhouse','Bids','api','Planhouse scraper','13:15 UTC daily',1440,240,'normal',false),
  ('bids:scrape-questcdn','Bids','api','QuestCDN scraper','13:30 UTC daily',1440,240,'normal',false),
  ('bids:scrape-osarc','Bids','api','OSARC scraper','13:45 UTC daily',1440,240,'normal',false),
  ('bids:scrape-engplus','Bids','api','Engineering Plus scraper','14:00 UTC daily',1440,240,'normal',false),
  ('bids:scrape-state-aid','Bids','api','State-aid scraper','Every 6 hours',360,180,'normal',false),
  ('bids:poll-emails','Bids','api','Mailbox poll (Graph)','Every 15 min across estimator mailboxes',15,45,'high',false),
  ('bids:classify-bids','Bids','api','Bid classifier (Claude)','Every 5 min',5,25,'normal',false),
  ('bids:renew-graph-subscriptions','Bids','api','Graph subscription renewal','Every 12 h; a lapse silently stops webhook ingest',720,240,'high',false),
  ('bids:sweep-expired','Bids','sync','Sweep expired bids','14:30 UTC daily',1440,240,'low',false),
  ('bids:ingest-mrba-ads','Bids','sync','MRBA ads ingest','14:45 UTC daily',1440,240,'normal',false),
  ('bids:ingest-mrba-tabs','Bids','sync','MRBA bid tabs ingest','Wednesdays 15:30 UTC',10080,1440,'low',false),
  ('bids:sync-mdot-lettings','Bids','sync','MDOT lettings sync','1st of month 06:00 UTC',44640,2880,'low',false),
  ('bids:remind-estimators','Bids','sync','Estimator reminders (email)','13:00 UTC daily',1440,240,'normal',false),
  ('bids:solicitation-followups','Bids','sync','Solicitation follow-ups (email)','13:20 UTC daily',1440,240,'normal',false),
  ('bids:master-drift-watch','Bids','sync','Master data drift watch','Mondays 11:30 UTC',10080,1440,'low',false)
on conflict (key) do nothing;

-- --------------------------------------------------------
-- New state: 'pending' = registered less than one expected interval ago and has
-- not reported yet. Not a flag; becomes 'silent' (flagged) if it never reports.
-- --------------------------------------------------------
create or replace function public.monitor_status()
returns table (
  source_key text, tool text, type text, name text, description text, severity text,
  state text, reason text,
  last_run_at timestamptz, last_ok_at timestamptz,
  runs_24h integer, fails_24h integer,
  last_error text, last_duration_ms integer,
  expected_interval_min integer, recent jsonb
)
language sql
security definer
set search_path = public, cron, pg_temp
as $$
  with ev as (
    select s.key, d.start_time as at,
           case when d.status = 'succeeded' then 'ok' else 'error' end as status,
           (extract(epoch from (d.end_time - d.start_time)) * 1000)::int as ms,
           left(d.return_message, 300) as msg
      from monitor_source s
      join cron.job j on j.jobname = s.cron_jobname
      join cron.job_run_details d on d.jobid = j.jobid
     where s.sync_kind is null and d.start_time > now() - interval '14 days'
    union all
    select s.key, l.run_at,
           case l.status
             when 'success' then 'ok'
             when 'partial' then 'warn'
             when 'running' then case when l.run_at < now() - interval '30 minutes' then 'error' else 'ok' end
             else 'error' end,
           l.duration_ms,
           left(coalesce(l.error_message,
                         case l.status when 'running' then 'stuck in running state' end), 300)
      from monitor_source s
      join sync_log l on l.kind = s.sync_kind
       and (s.sync_trigger is null or l.trigger = s.sync_trigger)
       and (s.sync_filter  is null or l.details @> s.sync_filter)
     where l.run_at > now() - interval '14 days'
    union all
    select e.source_key, e.at, e.status, e.duration_ms, left(e.message, 300)
      from monitor_event e
     where e.at > now() - interval '14 days'
  ),
  ranked as (
    select ev.*, row_number() over (partition by key order by at desc) rn from ev
  ),
  agg as (
    select key,
           max(at) as last_run_at,
           max(at) filter (where status = 'ok') as last_ok_at,
           count(*) filter (where at > now() - interval '24 hours')::int as runs_24h,
           count(*) filter (where at > now() - interval '24 hours' and status = 'error')::int as fails_24h,
           count(*) filter (where rn <= 5 and status = 'error')::int as bad_of_last5,
           max(status) filter (where rn = 1) as last_status,
           max(msg)    filter (where rn = 1) as last_msg,
           max(ms)     filter (where rn = 1) as last_ms,
           (select r2.msg from ranked r2 where r2.key = ranked.key and r2.status = 'error'
             order by r2.at desc limit 1) as last_error,
           jsonb_agg(jsonb_build_object('at', at, 'status', status, 'ms', ms, 'msg', msg)
                     order by at desc) filter (where rn <= 10) as recent
      from ranked group by key
  )
  select s.key, s.tool, s.type, s.name, s.description, s.severity,
         x.state, x.reason,
         a.last_run_at, a.last_ok_at,
         coalesce(a.runs_24h, 0), coalesce(a.fails_24h, 0),
         a.last_error, a.last_ms,
         s.expected_interval_min, coalesce(a.recent, '[]'::jsonb)
    from monitor_source s
    left join agg a on a.key = s.key
    cross join lateral (
      select
        -- elapsed since last success; weekends removed for weekday-only sources
        case when s.weekdays_only then monitor_effective_gap(a.last_ok_at, now()) else now() - a.last_ok_at end as gap,
        (s.window_start_hour is null
         or extract(hour from now() at time zone 'utc')::int between s.window_start_hour and s.window_end_hour) as in_window
    ) g
    cross join lateral (
      select
        case
          when not s.enabled                                   then 'disabled'
          when a.key is null and s.created_at > now() - make_interval(mins => s.expected_interval_min + s.grace_min) then 'pending'
          when a.key is null                                   then 'silent'
          when a.last_status = 'error'                         then 'failing'
          when a.bad_of_last5 >= 3                             then 'failing'
          when a.last_ok_at is null                            then 'late'
          when g.gap > make_interval(mins => s.expected_interval_min + s.grace_min)
               and (g.in_window or g.gap > interval '36 hours') then 'late'
          when a.last_status = 'warn' or a.bad_of_last5 >= 1   then 'warn'
          else 'ok'
        end as state,
        case
          when not s.enabled                                   then 'Disabled in registry'
          when a.key is null and s.created_at > now() - make_interval(mins => s.expected_interval_min + s.grace_min) then 'Registered ' || to_char(s.created_at at time zone 'America/Chicago', 'Mon DD HH24:MI') || ' CT; waiting for its first run'
          when a.key is null                                   then 'No runs recorded in the last 14 days'
          when a.last_status = 'error'                         then 'Last run failed: ' || coalesce(a.last_msg, 'no message')
          when a.bad_of_last5 >= 3                             then a.bad_of_last5 || ' of the last 5 runs failed'
          when a.last_ok_at is null                            then 'No successful run in the last 14 days'
          when g.gap > make_interval(mins => s.expected_interval_min + s.grace_min)
               and (g.in_window or g.gap > interval '36 hours')
                                                               then 'No success since ' || to_char(a.last_ok_at at time zone 'America/Chicago', 'Mon DD HH24:MI') || ' CT (expected every ' || s.expected_interval_min || ' min' || case when s.weekdays_only then ', weekdays' else '' end || ')'
          when a.last_status = 'warn'                          then 'Last run partial: ' || coalesce(a.last_msg, 'see recent runs')
          when a.bad_of_last5 >= 1                             then 'Failed ' || a.bad_of_last5 || ' of the last 5 runs'
          else 'On schedule'
        end as reason
    ) x
   order by s.tool, s.name;
$$;

revoke all on function public.monitor_status() from public, anon;
grant execute on function public.monitor_status() to authenticated;
