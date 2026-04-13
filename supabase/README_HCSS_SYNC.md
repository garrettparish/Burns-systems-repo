# HCSS Sync — Phase 1 Deploy Guide

Automatic daily pull of HeavyJob actuals into Burns Project Controls.
Runs every day at **05:00 CT** via `pg_cron`, or on-demand from the app.

---

## What this deploys

| File | What it does |
|---|---|
| `supabase/migrations/20260409_hcss_sync.sql` | Creates `actuals_detail_sync`, `sync_log`, `sync_status` view, and the `pg_cron` job |
| `supabase/functions/hcss-sync-actuals/index.ts` | Edge Function that mints HCSS tokens, pulls time cards + quantities, upserts into the table |

Both are idempotent — safe to re-run.

---

## One-time setup

Install the Supabase CLI if you don't have it:
```bash
brew install supabase/tap/supabase
```

Link the repo to your project (only needed once — will prompt for the project ref `sxzvlazmkxnbsoayhuln`):
```bash
cd "Burns System Repo"
supabase login
supabase link --project-ref sxzvlazmkxnbsoayhuln
```

---

## Step 1 — Set the HCSS secrets

Paste your **new, rotated** HCSS credentials. Nothing ever goes in git.
```bash
supabase secrets set HCSS_CLIENT_ID=<your_new_client_id>
supabase secrets set HCSS_CLIENT_SECRET=<your_new_client_secret>
# Optional until you know your BU code — leave unset for discovery mode.
# supabase secrets set HCSS_BUSINESS_UNIT_CODE=BURNS
# Optional tweaks:
# supabase secrets set HCSS_LOOKBACK_DAYS=14
# supabase secrets set HCSS_SCOPES='heavyjob:read setups:read'
```

---

## Step 2 — Run the SQL migration

Open the Supabase dashboard → **SQL Editor** → paste the contents of
`supabase/migrations/20260409_hcss_sync.sql` → Run.

After it succeeds, **set the two pg_cron dispatch settings** (one-time, in the same SQL editor):
```sql
alter database postgres set "app.hcss_sync_url"
  = 'https://sxzvlazmkxnbsoayhuln.functions.supabase.co/hcss-sync-actuals';
alter database postgres set "app.hcss_sync_secret"
  = '<your service_role JWT from Dashboard → Settings → API>';
```

> These are required for the daily cron to POST to the Edge Function. Without them the cron line will no-op silently.

Re-run the `cron.schedule` block at the bottom of the migration after you set those values, so the scheduled job picks them up.

---

## Step 3 — Deploy the Edge Function

```bash
supabase functions deploy hcss-sync-actuals --no-verify-jwt
```

`--no-verify-jwt` is required because `pg_cron` dispatches without a Supabase user JWT.

---

## Step 4 — Discovery run (find your Business Unit code)

```bash
curl -X POST \
  'https://sxzvlazmkxnbsoayhuln.functions.supabase.co/hcss-sync-actuals' \
  -H 'Authorization: Bearer <your service_role JWT>' \
  -H 'Content-Type: application/json' \
  -d '{"discover": true}'
```

You'll get back a list of every business unit your HCSS client can see. Pick the Burns one and set it:
```bash
supabase secrets set HCSS_BUSINESS_UNIT_CODE=<picked_code>
```

---

## Step 5 — First real sync (full-history backfill)

The first run should pull full history so every job has every row from day one.
After this, the daily 5am cron sticks to the 14-day rolling window.

**Easiest:** open the app → click **Backfill All** in the green HCSS Auto-Sync banner.

**Or via curl:**
```bash
curl -X POST \
  'https://sxzvlazmkxnbsoayhuln.functions.supabase.co/hcss-sync-actuals' \
  -H 'Authorization: Bearer <your service_role JWT>' \
  -H 'Content-Type: application/json' \
  -d '{"trigger": "manual", "fullHistory": true}'
```

For a routine rolling-window sync (what the cron runs):
```bash
curl -X POST \
  'https://sxzvlazmkxnbsoayhuln.functions.supabase.co/hcss-sync-actuals' \
  -H 'Authorization: Bearer <your service_role JWT>' \
  -H 'Content-Type: application/json' \
  -d '{"trigger": "manual"}'
```

Expected response:
```json
{
  "ok": true,
  "status": "success",
  "jobsSynced": 12,
  "rowsUpserted": 4713,
  "errors": [],
  "durationMs": 18422
}
```

---

## Step 6 — Verify

In the SQL editor:
```sql
select * from sync_status;
select job_number, count(*) from actuals_detail_sync group by 1 order by 2 desc;
select * from sync_log order by run_at desc limit 5;
```

You should see Stone 765 with ~272+ rows and ~30 cost codes. If you only see 1 or 2 codes, that's an endpoint-shape mismatch — check the `errors` array in the response and `sync_log.details`.

---

## What happens next

- **Every morning at 05:00 CT** the cron job fires and refreshes the last 14 days.
- The front-end reads `public.sync_status` for the "Last synced" banner and can POST to the Edge Function with `{"trigger":"manual"}` to force an immediate sync.
- The existing XLSX drop zone still works as a fallback when HCSS is down or you're onboarding a job that hasn't been created in HJ yet.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Token mint failed (401)` | Client ID or secret is wrong. Re-run `supabase secrets set ...`. |
| `GET .../business-units → 404` | HCSS moved the endpoint path. Edit `EP` at the top of `index.ts` and redeploy. |
| `HCSS_BUSINESS_UNIT_CODE='X' not found` | Re-run discovery mode, pick a code that appears in the list. |
| Cron row doesn't appear in `cron.job` | You didn't set `app.hcss_sync_url` / `app.hcss_sync_secret` before re-running the `cron.schedule` block. |
| Rows have `0` for every cost | HCSS time-card JSON has different key names than expected. Check `sync_log.details.errors` and update the `pick()` arrays in `mergeJobRows`. |

---

## Rotate secrets any time

```bash
supabase secrets set HCSS_CLIENT_SECRET=<new_secret>
# no redeploy needed — the function reads env vars on every invocation
```
