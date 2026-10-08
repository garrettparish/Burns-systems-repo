-- ============================================================================
-- 20261008120000_system_monitor.sql
-- System Health monitor: one registry of every sync / cron / API / MCP /
-- webhook, one status function that judges each against its expected cadence.
--
-- Evidence sources (a registry row picks exactly one):
--   * sync_kind set   -> public.sync_log rows (the REAL outcome of an Edge
--                        Function; pg_cron only proves net.http_post was queued)
--   * cron_jobname    -> cron.job_run_details (pure-SQL cron jobs)
--   * neither         -> public.monitor_event heartbeats pushed by the
--                        `monitor-report` Edge Function (external APIs, MCP
--                        servers, box jobs, Netlify scheduled functions)
--
-- States: ok | warn | failing | late | silent | disabled.  Anything but ok is
-- a flag.  Read-only for authenticated users; writes are service-role only.
-- ============================================================================

create table if not exists public.monitor_source (
  key                   text primary key,                 -- e.g. 'hcss:actuals-sync'
  tool                  text not null,                    -- HCSS, Spectrum, Samsara, ...
  type                  text not null check (type in ('cron','sync','api','mcp','edge','webhook')),
  name                  text not null,
  description           text,
  expected_interval_min integer not null check (expected_interval_min > 0),
  grace_min             integer not null default 60,
  window_start_hour     smallint,                         -- UTC; null = runs around the clock
  window_end_hour       smallint,
  severity              text not null default 'normal' check (severity in ('low','normal','high')),
  enabled               boolean not null default true,
  cron_jobname          text,                             -- evidence: cron.job.jobname
  sync_kind             text,                             -- evidence: sync_log.kind
  sync_trigger          text,                             -- optional sync_log.trigger filter
  sync_filter           jsonb,                            -- optional sync_log.details @> filter
  created_at            timestamptz not null default now()
);

create table if not exists public.monitor_event (
  id          bigserial primary key,
  source_key  text not null references public.monitor_source(key) on delete cascade,
  at          timestamptz not null default now(),
  status      text not null check (status in ('ok','warn','error')),
  duration_ms integer,
  message     text,
  detail      jsonb
);
create index if not exists idx_monitor_event_source_at on public.monitor_event(source_key, at desc);

alter table public.monitor_source enable row level security;
alter table public.monitor_event  enable row level security;

drop policy if exists monitor_source_read on public.monitor_source;
create policy monitor_source_read on public.monitor_source for select to authenticated using (true);
drop policy if exists monitor_event_read on public.monitor_event;
create policy monitor_event_read  on public.monitor_event  for select to authenticated using (true);

-- --------------------------------------------------------
-- Status function. SECURITY DEFINER because `cron` is not readable by
-- authenticated users.
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
    -- pure-SQL cron
    select s.key, d.start_time as at,
           case when d.status = 'succeeded' then 'ok' else 'error' end as status,
           (extract(epoch from (d.end_time - d.start_time)) * 1000)::int as ms,
           left(d.return_message, 300) as msg
      from monitor_source s
      join cron.job j on j.jobname = s.cron_jobname
      join cron.job_run_details d on d.jobid = j.jobid
     where s.sync_kind is null and d.start_time > now() - interval '14 days'
    union all
    -- Edge Function syncs, judged by what they logged
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
    -- pushed heartbeats
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
           (select msg from ranked r2 where r2.key = ranked.key and r2.status = 'error'
             order by at desc limit 1) as last_error,
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
        case
          when not s.enabled                                   then 'disabled'
          when a.key is null                                   then 'silent'
          when a.last_status = 'error'                         then 'failing'
          when a.bad_of_last5 >= 3                             then 'failing'
          when a.last_ok_at is null
            or now() - a.last_ok_at > make_interval(mins => s.expected_interval_min + s.grace_min)
            and (s.window_start_hour is null
                 or extract(hour from now() at time zone 'utc')::int between s.window_start_hour and s.window_end_hour
                 or now() - a.last_ok_at > interval '36 hours')  then 'late'
          when a.last_status = 'warn' or a.bad_of_last5 >= 1   then 'warn'
          else 'ok'
        end as state,
        case
          when not s.enabled                                   then 'Disabled in registry'
          when a.key is null                                   then 'No runs recorded in the last 14 days'
          when a.last_status = 'error'                         then 'Last run failed: ' || coalesce(a.last_msg, 'no message')
          when a.bad_of_last5 >= 3                             then a.bad_of_last5 || ' of the last 5 runs failed'
          when a.last_ok_at is null                            then 'No successful run in the last 14 days'
          when now() - a.last_ok_at > make_interval(mins => s.expected_interval_min + s.grace_min)
               and (s.window_start_hour is null
                    or extract(hour from now() at time zone 'utc')::int between s.window_start_hour and s.window_end_hour
                    or now() - a.last_ok_at > interval '36 hours')
                                                               then 'No success since ' || to_char(a.last_ok_at at time zone 'America/Chicago', 'Mon DD HH24:MI') || ' CT (expected every ' || s.expected_interval_min || ' min)'
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
-- Seed: only sources verified against the live project on 2026-10-08
-- (cron.job + sync_log kinds). Other tools register themselves by inserting a
-- monitor_source row and pushing heartbeats to the monitor-report function.
-- --------------------------------------------------------
insert into public.monitor_source
  (key, tool, type, name, description, expected_interval_min, grace_min, window_start_hour, window_end_hour, severity, cron_jobname, sync_kind, sync_trigger, sync_filter)
values
  ('hcss:actuals-sync',      'HCSS',      'sync', 'Timecard actuals sync',      '6 batches 10:00-10:15 UTC, logged per batch', 1440, 120, null, null, 'high',   null, 'actuals', 'cron', '{"mode":"sync"}'),
  ('hcss:job-costs-sync',    'HCSS',      'sync', 'Job costs sync (live $)',    'jobCosts/advancedRequest, 10:30 UTC',         1440, 120, null, null, 'high',   null, 'actuals', 'cron', '{"mode":"jobCosts"}'),
  ('hcss:metadata-nightly',  'HCSS',      'cron', 'Metadata sync (nightly)',    'Jobs / cost codes; cron fires the Edge Function, no sync_log row', 1440, 180, null, null, 'normal', 'hcss-sync-metadata-nightly', null, null, null),
  ('finance:actuals',        'Spectrum',  'sync', 'Finance actuals pull',       'Spectrum JTD/AP/receipts from burns-finance', 1440, 120, null, null, 'high',   null, 'finance-actuals', 'cron', null),
  ('spectrum:jobs',          'Spectrum',  'sync', 'Spectrum jobs',              '08:30 UTC daily',                              1440, 180, null, null, 'normal', null, 'spectrum', null, null),
  ('spectrum:phases',        'Spectrum',  'sync', 'Spectrum phases',            'Daily JTD by phase',                           1440, 180, null, null, 'normal', null, 'spectrum_phases', null, null),
  ('crew:bamboo-sync',       'BambooHR',  'sync', 'Crew scheduler roster sync', '07:00 UTC daily',                              1440, 180, null, null, 'normal', null, 'crew-scheduler-bamboo-sync', null, null),
  ('lookahead:weekly',       'Lookahead', 'sync', 'Lookahead build',            'Weekly, Thursday 12:00 UTC',                  10080, 1440, null, null, 'normal', null, 'lookahead', 'cron', null),
  ('scorecard:weekly',       'Scorecards','sync', 'PM/SM scorecard snapshot',   'Weekly',                                      10080, 1440, null, null, 'normal', null, 'scorecard', 'cron', null),
  ('scorecard:opr',          'Scorecards','sync', 'OPR scorecard snapshot',     'Weekly',                                      10080, 1440, null, null, 'normal', null, 'opr_scorecard', 'cron', null),
  ('visionlink:snapshot',    'VisionLink','cron', 'VisionLink daily snapshot',  'burns_dirt.vl_take_snapshot(), 23:45 UTC',     1440, 120, null, null, 'normal', 'visionlink-daily-snapshot', null, null, null),
  ('equipment:alerts',       'Equipment', 'cron', 'Equipment alerts',           'f_generate_equipment_alerts(), 11:00 UTC',     1440, 120, null, null, 'normal', 'equipment-alerts-daily', null, null, null),
  ('samsara:positions-day',  'Samsara',   'api',  'Positions poll (workday)',   'Every 10 min, 11:00-23:59 UTC',                  10,  25, 11, 23, 'normal', 'samsara-positions-workday', null, null, null),
  ('samsara:positions-night','Samsara',   'api',  'Positions poll (overnight)', 'Hourly, 00:00-10:59 UTC',                        60,  30,  0, 10, 'low',    'samsara-positions-overnight', null, null, null)
on conflict (key) do nothing;
