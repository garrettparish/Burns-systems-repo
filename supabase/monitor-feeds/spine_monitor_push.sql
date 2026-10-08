-- ============================================================================
-- spine_monitor_push.sql — apply to the SPINE project (fcadwdbbbijuutrhzewv).
-- NOT a Project Controls migration; lives here beside the monitor it feeds.
--
-- Every 15 minutes, summarises the spine's pg_cron runs and any non-2xx HTTP
-- responses into 15-minute buckets and POSTs them to monitor-report. Buckets are
-- keyed (source_key, external_id) so re-sending is harmless.
--
-- One-time setup (token never lands in a file or chat):
--   select vault.create_secret('<MONITOR_TOKEN>', 'monitor_token');
--
-- Limits, stated plainly:
--  * HTTP cron jobs (net.http_post) are judged "fired" by cron.job_run_details;
--    the function's real outcome is only visible in aggregate through
--    spine:http-errors (net._http_response keeps ~6 h and carries no job name).
--  * Pure-SQL jobs (scb_*, log-*) are judged by their real run status.
-- ============================================================================

create or replace function public.monitor_push(lookback_hours int default 2)
returns bigint
language plpgsql
security definer
set search_path = public, cron, net, vault, pg_temp
as $$
declare
  token  text;
  events jsonb;
  req    bigint;
begin
  select decrypted_secret into token from vault.decrypted_secrets where name = 'monitor_token' limit 1;
  if token is null then
    raise exception 'monitor_token missing from vault';
  end if;

  with bounds as (
    -- only complete 15-minute buckets
    select to_timestamp(floor(extract(epoch from now()) / 900) * 900) as hi,
           to_timestamp(floor(extract(epoch from now() - make_interval(hours => lookback_hours)) / 900) * 900) as lo
  ),
  runs as (
    select j.jobname,
           to_timestamp(floor(extract(epoch from d.start_time) / 900) * 900) as bucket,
           d.start_time, d.status, d.return_message,
           (extract(epoch from (d.end_time - d.start_time)) * 1000)::int as ms
      from cron.job_run_details d
      join cron.job j on j.jobid = d.jobid, bounds b
     where d.start_time >= b.lo and d.start_time < b.hi
  ),
  cron_ev as (
    select 'spine:' || jobname as source_key,
           case when count(*) filter (where status <> 'succeeded') > 0 then 'error' else 'ok' end as status,
           max(start_time) as at,
           max(ms) as duration_ms,
           case when count(*) filter (where status <> 'succeeded') > 0
                then left(max(return_message) filter (where status <> 'succeeded'), 300)
                else count(*) || ' run(s)' end as message,
           'cron:' || jobname || ':' || extract(epoch from bucket)::bigint as external_id
      from runs group by jobname, bucket
  ),
  http_ev as (
    -- Error = a real non-2xx response. A pg_net timeout (default 5 s) only means the
    -- caller stopped waiting; the function keeps running, so it is noted, not flagged.
    select 'spine:http-errors' as source_key,
           case when count(*) filter (where r.status_code is not null and r.status_code not between 200 and 299) > 0
                then 'error' else 'ok' end as status,
           max(r.created) as at,
           null::int as duration_ms,
           case when count(*) filter (where r.status_code is not null and r.status_code not between 200 and 299) > 0
                then count(*) filter (where r.status_code is not null and r.status_code not between 200 and 299)
                     || ' of ' || count(*) || ' HTTP calls returned non-2xx (last: '
                     || coalesce((array_agg(r.status_code order by r.created desc)
                                  filter (where r.status_code is not null and r.status_code not between 200 and 299))[1]::text, '?')
                     || ' ' || coalesce((array_agg(left(r.content, 100) order by r.created desc)
                                  filter (where r.status_code is not null and r.status_code not between 200 and 299))[1], '') || ')'
                else (count(*) - count(*) filter (where r.timed_out)) || ' HTTP calls ok'
                     || case when count(*) filter (where r.timed_out) > 0
                             then ', ' || count(*) filter (where r.timed_out) || ' timed out waiting (function may still have succeeded)'
                             else '' end end as message,
           'http:' || extract(epoch from to_timestamp(floor(extract(epoch from r.created) / 900) * 900))::bigint as external_id
      from net._http_response r, bounds b
     where r.created >= b.lo and r.created < b.hi
     group by to_timestamp(floor(extract(epoch from r.created) / 900) * 900)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'source_key', source_key, 'status', status, 'at', at,
           'duration_ms', duration_ms, 'message', message, 'external_id', external_id)), '[]'::jsonb)
    into events
    from (select * from cron_ev union all select * from http_ev) e;

  if jsonb_array_length(events) = 0 then
    return null;
  end if;

  select net.http_post(
    url     := 'https://sxzvlazmkxnbsoayhuln.supabase.co/functions/v1/monitor-report',
    headers := jsonb_build_object('Authorization', 'Bearer ' || token, 'Content-Type', 'application/json'),
    body    := jsonb_build_object('events', events)
  ) into req;
  return req;
end;
$$;

revoke all on function public.monitor_push(int) from public, anon, authenticated;

select cron.schedule('monitor-push', '*/15 * * * *', $$ select public.monitor_push(); $$);
