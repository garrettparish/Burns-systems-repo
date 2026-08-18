-- Fix hcss-sync-job-costs-batch-0/1/2 cron auth (same stale-vault-secret bug
-- as hcss-sync-metadata-nightly, fixed 2026-08-14 in
-- 20260814220000_fix_hcss_metadata_sync_secret.sql).
--
-- Found 2026-08-18: all three batch crons (jobid 11/12/13, scheduled
-- 10:30/10:35/10:40 UTC) were 401ing daily -- confirmed via net._http_response
-- (status_code=401, three rows, same three timestamps, going back at least to
-- 2026-08-11 based on hcss_job_costs.synced_at going stale exactly then).
-- vault.decrypted_secrets['hcss_sync_secret'] does not match the Edge
-- Function's real HCSS_SYNC_TOKEN secret (same root cause as the metadata
-- cron: the vault entry was never updated when the token was rotated/set for
-- real on 2026-08-14, see "Set real HCSS_SYNC_TOKEN shared secret" commit).
--
-- Also found: the three batch crons all pass {batchIndex, batchCount} in
-- their body, but hcss-sync-actuals/index.ts's syncJobCosts handler has NO
-- code that reads batchIndex/batchCount at all -- every one of the three
-- "batches" was actually running the FULL active-job list, three times a
-- day, for zero benefit (and 3x the HCSS API load/rate-limit risk). Rather
-- than implement real batching (a code change + Edge Function redeploy),
-- consolidated to one daily job with the corrected literal token and a
-- generous 300s timeout (matching the metadata-nightly pattern, which
-- already handles a comparable full-account loop within that budget).
--
-- Verified live 2026-08-18: manually fired the new job, got a 200, and
-- hcss_job_costs picked up 177 new rows across 2 new jobs, current through
-- the prior day -- the default 35-day lookback in the sync (LOOKBACK_DAYS)
-- meant no explicit backfill call was needed to recover the ~7-day gap.
--
-- If real per-batch splitting is ever wanted (e.g. HCSS rate-limiting starts
-- biting on ~140 jobs in one call), that requires adding batchIndex/
-- batchCount handling to the syncJobCosts block in index.ts and redeploying
-- the Edge Function -- confirm with Garrett before doing that, per this
-- repo's deploy rules.

select cron.unschedule('hcss-sync-job-costs-batch-0');
select cron.unschedule('hcss-sync-job-costs-batch-1');
select cron.unschedule('hcss-sync-job-costs-batch-2');

select cron.schedule(
  'hcss-sync-job-costs-daily',
  '30 10 * * *',
  $cron$
    select net.http_post(
      url     := 'https://sxzvlazmkxnbsoayhuln.functions.supabase.co/hcss-sync-actuals',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer e280d37966ad12898d76f30e4282e11a88ea7c3f85921a233f4089af4375273f'
      ),
      body    := jsonb_build_object('syncJobCosts', true, 'trigger', 'cron'),
      timeout_milliseconds := 300000
    );
  $cron$
);
