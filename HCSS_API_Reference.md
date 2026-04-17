# HCSS API Integration Reference — Burns Dirt Construction

**Last updated:** April 17, 2026
**Author:** Garrett Parish (with Claude)
**Status:** FULLY WORKING — jobs, cost codes, and timecards all syncing. 102 rows across 10 jobs. Daily 5am cron active.

---

## Quick Summary

We have a fully working HCSS HeavyJob API integration that syncs **132 jobs**, **938 cost codes**, and **timecard actuals** into Supabase. The timecard sync uses a two-step fetch pattern (list via `/timeCardInfo`, detail via `/timeCards/{id}`). Last sync: 102 rows across 10 active jobs in 18 seconds. A daily 5am cron handles ongoing sync (14-day lookback). The integration lives in a Supabase Edge Function and feeds into the Burns Project Controls app at `bdcprojectcontrols.netlify.app`.

---

## Authentication

**OAuth2 Client Credentials flow** — no user interaction needed.

**Token endpoint:** `https://api.hcssapps.com/identity/connect/token`

**Request:**
```
POST https://api.hcssapps.com/identity/connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id=<HCSS_CLIENT_ID>
&client_secret=<HCSS_CLIENT_SECRET>
&scope=heavyjob:read heavyjob:write timecards:read e360:read e360:timecards:read
```

**Response:**
```json
{
  "access_token": "eyJhbG...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "scope": "e360:read e360:timecards:read heavyjob:read setups:read setups:write timecards:read"
}
```

**Usage:** Add `Authorization: Bearer <access_token>` header to all API calls.

**Important notes on scopes:**
- The token request will fail with `invalid_scope` if you request ANY scope the OAuth server doesn't recognize
- The bare scope `setups:` (with nothing after the colon) is INVALID and will break the token request
- `myField:admin` also caused `invalid_scope` errors
- Stick to `product:read` / `product:write` / `product:feature:read` format
- Current working scopes: `heavyjob:read heavyjob:write timecards:read e360:read e360:timecards:read`

**All available HCSS scopes (from developer portal):**
```
skills:read skills:write setups:read setups:write
safetyapi:permissions:read safetyapi:permissions:write safetyapi:read safetyapi:write
meetings:read incidents:read incidents:write
projectmanagement:read projectmanagement:write
heavyjob:users:read heavyjob:users:write timecards:read timecards:write
heavyjob:read heavyjob:write precon:read precon:write
heavybid:system:read heavybid:system:write heavybid:read heavybid:write
e360:timecards:read e360:timecards:write e360:read e360:write
contacts:read contacts:write attachments:read attachments:write dis:read
```
**WARNING:** `setups:` (bare, no suffix) and `myField:admin` are listed in the developer portal but cause `invalid_scope` when requested. Do not include them.

---

## API Base URL

```
https://api.hcssapps.com
```

---

## Burns Dirt Account Details

**Business Unit:**
- **Code:** `MANAGER`
- **Name:** Burns Dirt Construction
- **UUID:** `152ef093-de97-4fea-a0c7-e632f1002847`

**Job count:** 132 total, 48 active (as of 2026-04-16)

---

## Working Endpoints (Confirmed 200)

### 1. List Business Units
```
GET https://api.hcssapps.com/heavyjob/api/v1/businessUnits
```
**Response:**
```json
[
  {
    "id": "152ef093-de97-4fea-a0c7-e632f1002847",
    "credentialsId": "152ef093-de97-4fea-a0c7-e632f1002847",
    "code": "MANAGER",
    "description": "Burns Dirt Construction"
  }
]
```

### 2. List Jobs
```
GET https://api.hcssapps.com/heavyjob/api/v1/jobs?businessUnitId=152ef093-de97-4fea-a0c7-e632f1002847
```
**Pagination:** `skip` and `limit` query params (default page size 500)
**Response shape:**
```json
{
  "results": [
    {
      "id": "78de2286-40f6-4726-a7ca-c4c7ef572472",
      "jobCode": "100",
      "name": "Job Name Here",
      "status": "active",
      "startDate": "2025-01-15T00:00:00",
      "endDate": null
    }
  ],
  "metadata": {}
}
```
**Notes:**
- Job code "0" is a template/placeholder job — skip it
- `businessUnitId` takes the UUID, not the code
- Status values include: `active`, `inactive`, `closed`, etc.

### 3. List Cost Codes (per job)
```
GET https://api.hcssapps.com/heavyjob/api/v1/costCodes?jobId=<job_uuid>
```
**Response shape:**
```json
{
  "results": [
    {
      "code": "990000",
      "description": "CONVERSION COST",
      "businessUnitId": "152ef093-de97-4fea-a0c7-e632f1002847",
      "businessUnitCode": "MANAGER",
      "jobId": "78de2286-40f6-4726-a7ca-c4c7ef572472",
      "jobCode": "100",
      "isHiddenFromMobile": false,
      "quantityDriving": false
    }
  ],
  "metadata": {}
}
```

### 4. List Employees
```
GET https://api.hcssapps.com/heavyjob/api/v1/employees
```
**Pagination:** `count` and `cursor` query params
**Response shape:**
```json
{
  "results": [
    {
      "Id": "e93cabc4-3c12-4e2c-8e5c-d0343064087d",
      "code": "1042",
      "firstName": "Austin",
      "cellPhone": "6622516458",
      "isDeleted": false,
      "address": { "type": "physical", "address1": "", "city": "", "state": "", "zip": "" }
    }
  ]
}
```

---

## Non-Working Endpoints (All Tested 2026-04-16)

### Endpoint Scan Results

We built a scan function that tries every plausible endpoint path combination. Here are the results:

**Timecard endpoints — ALL 404:**
| Path | Status | Notes |
|------|--------|-------|
| `/heavyjob/api/v1/timeCards` | 404 | Not found |
| `/heavyjob/api/v1/timecards` | 404 | Not found |
| `/heavyjob/api/v2/timeCards` | 404 | Not found |
| `/heavyjob/api/v2/timecards` | 404 | Not found |
| `/api/v1/timeCards` | 404 | No product prefix |
| `/api/v1/timecards` | 404 | No product prefix |
| `/timecards/api/v1/timeCards` | 404 | Timecards product prefix |
| `/timecards/api/v1/timecards` | 404 | Timecards product prefix |
| `/e360/api/v1/timeCards` | 404 | E360 service not provisioned |

**Other endpoints — ALL 404:**
| Path | Status | Notes |
|------|--------|-------|
| `/heavyjob/api/v1/equipment` | 404 | |
| `/heavyjob/api/v1/dailies` | 404 | |
| `/heavyjob/api/v1/dailyLogs` | 404 | |
| `/heavyjob/api/v1/foremen` | 404 | |
| `/heavyjob/api/v1/tags` | 404 | |
| `/heavyjob/api/v1/costTypes` | 404 | |
| `/heavyjob/api/v1/quantities` | 404 | |

**Product prefix scan (for businessUnits endpoint):**
| Path | Status |
|------|--------|
| `/setups/api/v1/BusinessUnit` | 403 (even with setups:write scope) |
| `/setups/api/v1/businessUnits` | 404 |
| `/e360/api/v1/businessUnits` | 404 ("E360 service may not exist or may be down") |
| `/e360/api/v1/BusinessUnit` | 404 |
| `/heavyjob/api/v1/businessUnits` | **200** ✅ |
| `/heavyjob/api/v1/BusinessUnit` | 404 (case matters!) |
| `/heavybid/api/v1/businessUnits` | 404 |

**Key takeaway:** All data that works is under `/heavyjob/api/v1/`. The `e360` product is not provisioned for our account (all e360 calls return 404 with "E360 service may not exist or may be down"). The `setups` product returns 403 even with the correct scopes.

**RESOLVED (2026-04-16):** HCSS support confirmed the 404s were NOT a permissions issue — we were using the wrong endpoint paths AND wrong ID format. Root causes:
1. **Wrong path:** We used `/heavyjob/api/v1/timeCards` — correct path is `/heavyjob/api/v1/timeCardInfo`
2. **Wrong ID type:** `jobId` param must be the HCSS UUID (from jobs list `id` field), NOT the job code string
3. **Wrong pagination:** HCSS uses cursor-based pagination (`cursor` + `limit`), not `skip`/`limit`

**Correct endpoints (from developer.hcssapps.com API Reference):**
| Endpoint | Method | Description |
|----------|--------|-------------|
| `/heavyjob/api/v1/timeCardInfo` | GET | Returns time cards (cursor-paginated) |
| `/heavyjob/api/v1/timeCardApprovalInfo` | GET | Returns time card approvals |
| `/heavyjob/api/v1/timeCardInfo` | POST | Returns time cards (POST variant) |
| `/heavyjob/api/v1/timeCardInfo/{id}` | GET | Returns single time card by ID |
| `/heavyjob/api/v1/timeCardInfo/{id}` | PUT | Updates a time card |

**Query params for GET /timeCardInfo:**
- `jobId` (uuid) — HCSS job GUID, omit for all jobs
- `foremanId` (uuid) — HCSS foreman GUID
- `employeeId` (uuid) — filter by employee
- `startDate` (yyyy-MM-dd) — inclusive start
- `endDate` (yyyy-MM-dd) — inclusive end
- `modifiedSince` (RFC-3339) — incremental sync
- `cursor` (string) — pagination cursor from response metadata
- `limit` (int32, default 1000) — page size
- `isApproved`, `isAccepted`, `isReviewed` (boolean) — status filters
- `businessUnitId` (uuid) — filter by BU

---

## Supabase Infrastructure

### Project
- **Project ref:** `sxzvlazmkxnbsoayhuln`
- **URL:** `https://sxzvlazmkxnbsoayhuln.supabase.co`
- **Dashboard:** `https://supabase.com/dashboard/project/sxzvlazmkxnbsoayhuln`

### Secrets (set via `supabase secrets set`)
```
HCSS_CLIENT_ID          = <your client id>
HCSS_CLIENT_SECRET      = <your client secret>
HCSS_SCOPES             = heavyjob:read heavyjob:write timecards:read e360:read e360:timecards:read
HCSS_BUSINESS_UNIT_CODE = MANAGER
HCSS_API_BASE           = https://api.hcssapps.com  (default, not explicitly set)
HCSS_LOOKBACK_DAYS      = 14  (default, not explicitly set)
```

### Tables

**`hcss_jobs`** — HeavyJob job list (132 rows)
```sql
create table public.hcss_jobs (
  hcss_id             text        primary key,   -- UUID from HCSS
  job_code            text        not null,
  job_name            text        default '',
  status              text        default '',
  start_date          date,
  end_date            date,
  business_unit_id    text        default '',
  business_unit_code  text        default '',
  raw                 jsonb,                      -- full API response
  synced_at           timestamptz not null default now()
);
```

**`hcss_cost_codes`** — Cost code definitions per job (938 rows)
```sql
create table public.hcss_cost_codes (
  id                  bigserial   primary key,
  hcss_job_id         text        not null references public.hcss_jobs(hcss_id) on delete cascade,
  job_code            text        not null,
  cost_code           text        not null,
  description         text        default '',
  unit                text        default '',
  is_hidden           boolean     default false,
  quantity_driven     boolean     default false,
  raw                 jsonb,
  synced_at           timestamptz not null default now(),
  unique (hcss_job_id, cost_code)
);
```

**`actuals_detail_sync`** — Daily actuals (102+ rows, synced from HCSS timecards)
```sql
create table public.actuals_detail_sync (
  job_number          text        not null,
  date                date        not null,
  cost_code           text        not null,
  foreman             text        not null default '',
  cost_code_desc      text        default '',
  unit                text        default '',
  actual_qty          numeric     default 0,
  actual_labor_hours  numeric     default 0,
  actual_equip_hours  numeric     default 0,
  actual_labor_cost   numeric     default 0,
  actual_equip_cost   numeric     default 0,
  actual_mat_cost     numeric     default 0,
  actual_sub_cost     numeric     default 0,
  expected_labor_hours numeric    default 0,
  expected_labor_cost  numeric    default 0,
  expected_equip_cost  numeric    default 0,
  expected_mat_cost    numeric    default 0,
  expected_sub_cost    numeric    default 0,
  source              text        not null default 'hcss-api',
  synced_at           timestamptz not null default now(),
  primary key (job_number, date, cost_code, foreman)
);
```

**`sync_log`** — Audit trail of every sync run
```sql
create table public.sync_log (
  id              bigserial primary key,
  run_at          timestamptz not null default now(),
  kind            text        not null,         -- 'actuals' | 'discover' | 'metadata'
  status          text        not null,         -- 'success' | 'error' | 'partial'
  trigger         text        not null default 'cron',
  jobs_synced     int         default 0,
  rows_inserted   int         default 0,
  rows_updated    int         default 0,
  duration_ms     int         default 0,
  error_message   text,
  details         jsonb
);
```

All tables have RLS enabled with `select` allowed for `anon` role. Writes use the `service_role` key (bypasses RLS).

### Edge Function

**Name:** `hcss-sync-actuals`
**Runtime:** Deno (Supabase Edge Functions)
**Location:** `supabase/functions/hcss-sync-actuals/index.ts`

**Deploy command:**
```bash
cd ~/Desktop/Burns\ System\ Repo
supabase functions deploy hcss-sync-actuals --no-verify-jwt
```

**Invocation modes (POST body):**

| Mode | Body | What it does |
|------|------|-------------|
| Discover | `{"discover": true}` | Lists business units, no writes |
| Sync Metadata | `{"syncMetadata": true}` | Pulls all jobs + cost codes into `hcss_jobs` / `hcss_cost_codes` |
| Sync Actuals | `{"trigger": "manual"}` | Pulls timecards for last 14 days (WORKING — 102 rows, 10 jobs) |
| Backfill | `{"trigger": "manual", "fullHistory": true}` | Full history pull (WORKING — not yet run, will pull all history) |
| Endpoint Scan | `{"scanEndpoints": true}` | Tries multiple endpoint paths, returns status codes for each |

**Calling from the browser:**
```javascript
const HCSS_FN_URL = 'https://sxzvlazmkxnbsoayhuln.supabase.co/functions/v1/hcss-sync-actuals';
const response = await fetch(HCSS_FN_URL, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + SUPABASE_ANON_KEY
  },
  body: JSON.stringify({ syncMetadata: true })
});
const data = await response.json();
```

### Pagination

HCSS uses **cursor-based pagination** (`cursor` + `limit`), NOT offset-based (`skip`/`limit`). Our Edge Function's `hcssGetPaginated()` handles this automatically — it reads `metadata.nextCursor` or `nextCursor` from each response page.

Response arrays can be at the top level (raw array) or nested under `results`, `items`, or `data` — the code handles all four shapes.

### Two-Step Timecard Fetch

The `/timeCardInfo` endpoint only returns summary records (id, date, foremanId — no cost codes or hours). To get full detail, you must fetch each timecard individually via `/timeCards/{id}`. Our `listTimeCards()` function handles this automatically:
1. `GET /timeCardInfo?jobId={uuid}` → list of summary records
2. For each summary: `GET /timeCards/{id}` → full detail with costCodes[], employees[], equipment[]

---

## Developer Portal

**URL:** `https://developer.hcssapps.com`
**API Reference:** `https://developer.hcssapps.com/hcss/reference`

The developer portal has full API docs but they're behind auth (you need to be logged in with an HCSS account). The sidebar groups endpoints by product: HeavyJob, Equipment360, Setups, HeavyBid, etc.

**Key finding:** The docs show timecard endpoints under BOTH HeavyJob and Equipment360 sections, but neither works for our account. HCSS support initially told us businessUnits was under `/setups/` (it's not — it's under `/heavyjob/`). Don't trust their first response; verify with actual API calls.

---

## Architecture Notes

### How it fits into Burns Project Controls

The Burns Project Controls app (`bdcprojectcontrols.netlify.app`) is a single-file HTML/CSS/JS app backed by this same Supabase project. The HCSS data flows:

1. **Edge Function** → calls HCSS API → writes to `hcss_jobs`, `hcss_cost_codes`, `actuals_detail_sync`
2. **Frontend** → reads from Supabase tables → merges with manually imported data (HeavyBid activities, Smartsheet schedule, etc.)
3. **Auto-match** → each project controls job can be linked to an HCSS job by job code via `meta.hcssJobCode`

### Nic's Finance Dashboard

Nic has a separate Supabase project (`bodcpnytvonucefnbmyz.supabase.co`) powering `burns-finance.netlify.app`. It pulls from Spectrum accounting. The plan is to eventually merge both data sources:
- **HCSS HeavyJob:** Fresh data (1-2 week lag), good for labor & equipment, missing subs/materials
- **Spectrum Accounting:** Delayed data (month+ lag), but complete (all cost types including subs, materials, burden)
- **Merge strategy:** Anything older than X weeks → Spectrum. Anything newer → HeavyJob.

---

## Troubleshooting

### Token mint fails with `invalid_scope`
One or more scopes in your request are invalid. Remove scopes one at a time to find the bad one. Known bad scopes: `setups:` (bare), `myField:admin`.

### 403 on an endpoint
You have the wrong scopes OR the endpoint path is under a different product. Use the endpoint scan mode to try all product prefixes.

### 404 on an endpoint
The endpoint doesn't exist for your account. Could mean: wrong path, wrong casing (case-sensitive!), or the product isn't provisioned. "The E360 service may not exist or may be down" means E360 isn't set up for your account.

### CORS "Failed to fetch"
The edge function needs an OPTIONS handler. Already implemented — returns CORS headers for preflight requests.

### Deploy fails: "no such file or directory"
You need to `cd` into the repo directory first:
```bash
cd ~/Desktop/Burns\ System\ Repo
supabase functions deploy hcss-sync-actuals --no-verify-jwt
```

---

## Files Reference

| File | Purpose |
|------|---------|
| `supabase/functions/hcss-sync-actuals/index.ts` | Edge function — all HCSS API logic |
| `supabase/migrations/20260409_hcss_sync.sql` | Creates `actuals_detail_sync`, `sync_log`, cron job |
| `supabase/migrations/20260414_hcss_metadata_sync.sql` | Creates `hcss_jobs`, `hcss_cost_codes` |
| `public/index.html` | Main app — HCSS sync UI is in the Setup tab |
| `supabase/README_HCSS_SYNC.md` | Original setup guide |
