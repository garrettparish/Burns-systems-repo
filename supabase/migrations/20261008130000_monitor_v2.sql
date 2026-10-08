-- ============================================================================
-- 20261008130000_monitor_v2.sql
-- System Health v2: weekday-aware lateness, batch-friendly heartbeats, and the
-- cross-project registry (Finance sync_log + spine pg_cron).
--
-- Feeds (all PUSH to the monitor-report Edge Function with MONITOR_TOKEN, so no
-- project credentials leave their home project):
--   finance:*  <- burns-finance lib/supabase-client.ts heartbeat on complete/fail
--   spine:*    <- spine function public.monitor_push() every 15 min
--                 (supabase/monitor-feeds/spine_monitor_push.sql)
-- ============================================================================

alter table public.monitor_source add column if not exists weekdays_only boolean not null default false;
alter table public.monitor_event  add column if not exists external_id text;
alter table public.monitor_event  drop constraint if exists monitor_event_source_external_uniq;
alter table public.monitor_event  add  constraint monitor_event_source_external_uniq unique (source_key, external_id);

-- Elapsed time between a and b with Saturday/Sunday (UTC) removed.
create or replace function public.monitor_effective_gap(a timestamptz, b timestamptz)
returns interval language sql immutable as $$
  select (b - a) - coalesce((
    select sum(least(b, d + interval '1 day') - greatest(a, d))
      from generate_series(date_trunc('day', a at time zone 'utc') at time zone 'utc',
                           date_trunc('day', b at time zone 'utc') at time zone 'utc',
                           interval '1 day') d
     where extract(dow from d at time zone 'utc') in (0, 6)
  ), interval '0');
$$;

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

-- --------------------------------------------------------
-- Registry: sources reported by other projects (heartbeat evidence).
-- --------------------------------------------------------
insert into public.monitor_source
  (key, tool, type, name, description, expected_interval_min, grace_min, window_start_hour, window_end_hour, severity, weekdays_only)
values
  ('spine:http-errors','Control Plane','edge','Spine edge-function HTTP errors','Aggregate of non-2xx responses to spine pg_cron HTTP calls (timeouts excluded), 15-min buckets. An error here means one of the fired-only spine jobs failed.',15,30,null,null,'high',false),
  ('spine:cost-sync-daily','Control Plane','edge','Ramp cost sync','cost-sync Edge Function, 11:00 UTC [fired-only: HTTP outcome is judged by spine:http-errors]',1440,180,null,null,'normal',false),
  ('spine:cp-bug-fix-notify-retry','Control Plane','edge','Bug fix notify retry','Every 5 min; reported as 15-min buckets [fired-only: HTTP outcome is judged by spine:http-errors]',15,30,null,null,'low',false),
  ('spine:health-digest','Control Plane','edge','Health digest email','12:10 UTC [fired-only: HTTP outcome is judged by spine:http-errors]',1440,180,null,null,'normal',false),
  ('spine:driver-roster-sync-daily','Logistics','edge','Driver roster sync','13:00 UTC [fired-only: HTTP outcome is judged by spine:http-errors]',1440,180,null,null,'normal',false),
  ('spine:dtd-daily-reconcile','Logistics','sync','DTD daily reconcile','10:00 UTC [fired-only: HTTP outcome is judged by spine:http-errors]',1440,180,null,null,'high',false),
  ('spine:dtd-invoice-sync','Logistics','sync','DTD invoice sync (nightly)','09:00 UTC [fired-only: HTTP outcome is judged by spine:http-errors]',1440,180,null,null,'high',false),
  ('spine:dtd-invoice-sync-hourly','Logistics','sync','DTD invoice sync (hourly)','Hourly 12:00-23:00 UTC [fired-only: HTTP outcome is judged by spine:http-errors]',60,60,12,23,'normal',false),
  ('spine:eia-fuel-price-weekly','Logistics','api','EIA fuel price','Tuesdays 09:50 UTC [fired-only: HTTP outcome is judged by spine:http-errors]',10080,1440,null,null,'low',false),
  ('spine:fmcsa-safer-sync-daily','Logistics','api','FMCSA SAFER sync','09:40 UTC [fired-only: HTTP outcome is judged by spine:http-errors]',1440,180,null,null,'normal',false),
  ('spine:log-aggregates-refresh','Logistics','cron','Log aggregates refresh','Materialized views, every 15 min',15,30,null,null,'normal',false),
  ('spine:log-dvir-defects-nightly','Logistics','cron','DVIR defects extract','09:30 UTC',1440,180,null,null,'normal',false),
  ('spine:log-recon-weekly','Logistics','sync','Logistics recon (weekly)','Wednesdays 12:00 UTC [fired-only: HTTP outcome is judged by spine:http-errors]',10080,1440,null,null,'normal',false),
  ('spine:samsara-daily-sync','Samsara','api','Fleet daily sync (spine copy)','09:00 UTC; roster+fuel, duplicates the Finance and Dirt OS copies [fired-only: HTTP outcome is judged by spine:http-errors]',1440,180,null,null,'normal',false),
  ('spine:samsara-trailer-sync-daily','Samsara','api','Trailer sync','09:10 UTC [fired-only: HTTP outcome is judged by spine:http-errors]',1440,180,null,null,'normal',false),
  ('spine:samsara-dvir-sync-daily','Samsara','api','DVIR sync','09:20 UTC [fired-only: HTTP outcome is judged by spine:http-errors]',1440,180,null,null,'normal',false),
  ('spine:people-roster-mirror-daily','People OS','sync','Roster mirror to Logistics','09:05 UTC [fired-only: HTTP outcome is judged by spine:http-errors]',1440,180,null,null,'normal',false),
  ('spine:waste-weekly-sync','Waste','edge','Waste weekly sync','Mondays 06:30 UTC [fired-only: HTTP outcome is judged by spine:http-errors]',10080,1440,null,null,'normal',false),
  ('spine:scb-apply-status-hourly','Scorecards','cron','SCB apply status (hourly)','12:25-23:25 UTC',60,60,12,23,'low',false),
  ('spine:scb-apply-status-nightly','Scorecards','cron','SCB apply status (nightly)','12:00 UTC',1440,180,null,null,'low',false),
  ('spine:scb-auto-calc-nightly','Scorecards','cron','SCB auto calc','10:30 UTC',1440,180,null,null,'normal',false),
  ('spine:scb-billed-revenue-hourly','Scorecards','cron','SCB billed revenue (hourly)','12:20-23:20 UTC',60,60,12,23,'low',false),
  ('spine:scb-billed-revenue-nightly','Scorecards','cron','SCB billed revenue (nightly)','09:20 UTC',1440,180,null,null,'normal',false),
  ('spine:scb-billed-revenue-deep-sweep','Scorecards','cron','SCB billed revenue deep sweep','Sundays 12:00 UTC',10080,1440,null,null,'low',false),
  ('spine:scb-dvir-nightly','Scorecards','cron','SCB DVIR','11:35 UTC',1440,180,null,null,'normal',false),
  ('spine:scb-fleet-count-nightly','Scorecards','cron','SCB fleet count','09:15 UTC',1440,180,null,null,'normal',false),
  ('spine:scb-fmcsa-nightly','Scorecards','cron','SCB FMCSA','11:45 UTC',1440,180,null,null,'normal',false),
  ('spine:scb-fuel-calc-daily','Scorecards','cron','SCB fuel','10:35 UTC',1440,180,null,null,'normal',false),
  ('spine:scb-inspection-totals-nightly','Scorecards','cron','SCB inspection totals','10:58 UTC',1440,180,null,null,'normal',false),
  ('spine:scb-intel-brief-weekly','Scorecards','api','SCB intel brief','Tuesdays 20:00 UTC, calls Logistics OS Netlify [fired-only: HTTP outcome is judged by spine:http-errors]',10080,1440,null,null,'low',false),
  ('spine:scb-open-defects-nightly','Scorecards','cron','SCB open defects','11:40 UTC',1440,180,null,null,'normal',false),
  ('spine:scb-pct-goal-nightly','Scorecards','cron','SCB pct goal','10:40 UTC',1440,180,null,null,'normal',false),
  ('spine:scb-recruiting-nightly','Scorecards','cron','SCB recruiting','10:55 UTC',1440,180,null,null,'normal',false),
  ('spine:scb-revenue-mix-daily','Scorecards','cron','SCB revenue mix','10:37 UTC',1440,180,null,null,'normal',false),
  ('spine:scb-samsara-nightly','Scorecards','cron','SCB Samsara','11:30 UTC',1440,180,null,null,'normal',false),
  ('finance:qbo','Finance','sync','QuickBooks (Burns Waste)','burns_shared.sync_log source qbo, weekdays only',1440,180,null,null,'high',true),
  ('finance:qbo-payments','Finance','sync','QuickBooks payments','burns_shared.sync_log source qbo-payments, weekdays only',240,120,null,null,'normal',true),
  ('finance:spectrum','Finance','sync','Spectrum jobs (Finance copy)','burns_shared.sync_log source spectrum, weekdays only',1440,180,null,null,'high',true),
  ('finance:spectrum_phases','Finance','sync','Spectrum phases (Finance copy)','burns_shared.sync_log source spectrum_phases, weekdays only',1440,180,null,null,'high',true),
  ('finance:bw_actuals','Finance','sync','Burns Waste actuals','burns_shared.sync_log source bw_actuals, weekdays only',1440,180,null,null,'high',true),
  ('finance:samsara','Finance','sync','Samsara fleet (Finance copy)','burns_shared.sync_log source samsara',1440,180,null,null,'normal',false),
  ('finance:pctl-cashflow','Finance','sync','Project Controls cash flow mirror','burns_shared.sync_log source pctl-cashflow, weekdays only',1440,180,null,null,'normal',true),
  ('finance:project-flags','Finance','sync','Project flags','burns_shared.sync_log source project-flags, weekdays only',1440,180,null,null,'normal',true),
  ('finance:percent-complete','Finance','sync','Percent complete engine','burns_shared.sync_log source percent-complete, weekdays only',1440,180,null,null,'normal',true),
  ('finance:material-deliveries','Finance','sync','Material deliveries loader','burns_shared.sync_log source material-deliveries',1440,180,null,null,'normal',false),
  ('finance:pit-periods','Finance','sync','Pit period cost pools','burns_shared.sync_log source pit-periods',1440,180,null,null,'normal',false),
  ('finance:forecast_ledger','Finance','sync','Forecast accuracy ledger','burns_shared.sync_log source forecast_ledger, weekdays only',1440,180,null,null,'normal',true),
  ('finance:data_health','Finance','sync','Data-health check (freshness + integrity)','burns_shared.sync_log source data_health',1440,180,null,null,'high',false),
  ('finance:blo-scorecard','Finance','sync','BLO scorecard sync','burns_shared.sync_log source blo-scorecard, weekdays only',60,60,11,23,'normal',true),
  ('finance:snapshot-wip','Finance','sync','WIP snapshot (monthly)','burns_shared.sync_log source snapshot-wip',44640,2880,null,null,'normal',false)
on conflict (key) do nothing;
