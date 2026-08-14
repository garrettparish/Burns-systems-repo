-- ============================================================
-- HCSS Metadata Sync — fix the secret so the nightly cron actually works
-- Burns Project Controls
-- ============================================================
-- Nic reported new HeavyJob projects weren't showing up in hcss_jobs.
-- There already was a nightly cron for this (hcss-sync-metadata-nightly,
-- 2am UTC) — pg_cron's cron.job_run_details showed it "succeeded" every
-- night for 10+ days straight. That's misleading: pg_net's http_post is
-- async, so "succeeded" only means the request was queued, not that it got
-- a 200 back. The real response (net._http_response) showed 401
-- Unauthorized on every single call — this job builds its Authorization
-- header from vault.decrypted_secrets, but that value is stale/wrong. The
-- edge function's actual current secret is a literal hardcoded token,
-- confirmed working right now via the sibling hcss-sync-actuals-daily cron
-- (jobid 18) — same function, different job, correctly configured.
--
-- Fixed hcss-sync-metadata-nightly in place with that same known-working
-- URL + token, and widened net.http_post's timeout to 5 min (default 5s is
-- nowhere near enough for a full jobs + per-job-cost-codes pull across
-- ~140 jobs with HCSS's required 250ms inter-request pause).
--
-- Verified live before considering this fixed (not just "should work"):
-- manually fired the corrected net.http_post once and watched hcss_jobs go
-- from 141 -> 143 rows in real time. The 2 new rows were real, active
-- HeavyJob projects (792 Tronox road repair, 793 Prairie Property) that had
-- been sitting unsynced since whenever they were created in HeavyJob.
-- ============================================================

select cron.schedule(
  'hcss-sync-metadata-nightly',
  '0 2 * * *',
  $cron$
    select net.http_post(
      url     := 'https://sxzvlazmkxnbsoayhuln.functions.supabase.co/hcss-sync-actuals',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer e280d37966ad12898d76f30e4282e11a88ea7c3f85921a233f4089af4375273f'
      ),
      body    := jsonb_build_object('syncMetadata', true, 'trigger', 'cron'),
      timeout_milliseconds := 300000
    );
  $cron$
);
