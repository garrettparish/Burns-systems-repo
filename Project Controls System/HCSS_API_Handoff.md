# HCSS HeavyJob API — Integration Handoff

> Self-contained reference for building an HCSS HeavyJob API integration from scratch. Captures every working endpoint, every failed endpoint and why, the auth flow, pagination quirks, rate-limit behavior, and known data shapes. Last verified 2026-04-28 against Burns Dirt's HCSS account.

---

## TL;DR

HCSS exposes a REST API at `https://api.hcssapps.com` with OAuth2 client-credentials auth. The HeavyJob (`/heavyjob/api/v1/`) namespace is the workhorse for project controls. With the right scopes + endpoint paths, you can pull:

- Jobs, cost codes, employees
- Timecards (two-step fetch: list summaries, then detail per ID)
- **Per (date × cost code × foreman) BELMOS dollars + hours + qty** via `POST /jobCosts/advancedRequest` — labor, equipment, material, subcontract, trucking, plus quantities and hours
- Per-code cost code progress (qty by date range)
- Job-level cost rollups
- Material and subcontract budgets per job

Equipment360 (E360) endpoints exist in the docs but **are not provisioned for our account** — every E360 path returns 404 with "E360 service may not exist or may be down." You may have a different provisioning, but assume HeavyJob endpoints first.

---

## 1. Auth — OAuth2 Client Credentials

**Token endpoint:**
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
  "scope": "..."
}
```

**Use:** Add `Authorization: Bearer <access_token>` to every API call.

### Scope rules — these matter

The token request fails with `invalid_scope` if you ask for any scope the OAuth server doesn't recognize. **Two scopes that look valid but break the token request:**
- `setups:` (bare, no suffix) — invalid
- `myField:admin` — invalid

Stick to `product:read` / `product:write` / `product:feature:read`. Burns' working set:
```
heavyjob:read heavyjob:write timecards:read e360:read e360:timecards:read
```

Full list of available scopes (from the developer portal):
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

---

## 2. Base URL + Business Unit

**Base:** `https://api.hcssapps.com`

Every HeavyJob query needs a `businessUnitId` (UUID, not the code). Get it from the BU list:

```
GET /heavyjob/api/v1/businessUnits
```

Returns:
```json
[
  {
    "id": "152ef093-de97-4fea-a0c7-e632f1002847",
    "code": "MANAGER",
    "description": "Burns Dirt Construction"
  }
]
```

The `code` is human-readable, the `id` is what other endpoints want. Many endpoints fail silently or 403 if you pass the code instead of the UUID.

---

## 3. Working Endpoints (Confirmed 200)

All paths under `/heavyjob/api/v1/`. Use `Authorization: Bearer <token>` + `Accept: application/json`.

### 3.1 Reference data

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/businessUnits` | List BUs (small response, no pagination needed) |
| GET | `/jobs?businessUnitId={uuid}` | All jobs for a BU. Cursor-paginated. |
| GET | `/costCodes?jobId={uuid}` | Cost codes for a job. Cursor-paginated. **Returns `id` (UUID), `code`, `description`, `unit`, plus full BELMOS budgets per code.** |
| GET | `/employees` | Employees. Cursor-paginated. |

### 3.2 Time + cost data

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/timeCardInfo?jobId={uuid}&startDate=YYYY-MM-DD` | Timecard summaries (id, date, foremanId only). Cursor-paginated. |
| GET | `/timeCards/{id}` | Full timecard detail — see two-step pattern below. |
| GET | `/jobs/{jobId}/costs` | Job-level cost rollup. Query params: `effectiveDate`, `startDate`. |
| **POST** | `/jobCosts/advancedRequest` | **The big one** — per (date × cost code × foreman) BELMOS dollars. See body shape below. |
| **POST** | `/costCode/progress/advancedRequest` | Quantities by date range, per cost code. |

### 3.3 Budgets

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/jobs/{jobId}/advancedBudgets/material` | Material budgets per cost code. |
| GET | `/jobs/{jobId}/advancedBudgets/subcontract` | Subcontract budgets per cost code. |

### 3.4 Daily Log — Diaries + Attachments

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/diaries/search` | Per-(job × foreman × date) free-text notes. Body filters: `businessUnitId`, `jobIds[]`, `foremanIds[]`, `startDate`, `endDate`, `cursor`, `limit`. Returns `{id, job, foreman, note, tags[], date, revision, lastChangedBy, lastChangedDateTime}`. **No weather field — HCSS API does not expose weather.** |
| POST | `/attachment/advancedRequest` | Photos + PDFs attached to diaries. Body needs `attachmentType: "diary"` and `fileType: "photos" \| "pdf" \| "all"`. Returns rows with `attachmentUrl` (signed download URL ~440 chars), `thumbnailUrl`, dimensions, `mimeType`, `lastModified`, `referenceDate`, `name`, `note`, employee + job context. **Photos include `latitude` + `longitude`** — usable for site-photo maps. PDFs include auto-generated safety reports / meeting reports / signed forms. |

### 3.4 Confirmed 404 / not provisioned (don't waste time)

- All E360 paths (`/e360/api/v1/...`) — service not provisioned
- `/heavyjob/api/v1/equipment` — not exposed; equipment data is embedded in timecard details instead
- `/heavyjob/api/v1/quantities` — endpoint doesn't exist; qty is in timecard detail and `jobCosts/advancedRequest`
- `/heavyjob/api/v1/dailies`, `/dailyLogs`, `/foremen`, `/tags`, `/costTypes`
- `/heavyjob/api/v1/jobs/{id}/costAdjustments`
- `/heavyjob/api/v1/jobs/{id}/costCodeTransactions`
- `/heavyjob/api/v1/costCodeTransactions/advancedRequest`
- `/heavyjob/api/v1/jobs/{id}/advancedBudgets/customCostType`
- `/heavyjob/api/v1/accounting/rateSets`, `/accounting/rateSetGroups`
- `/heavyjob/api/v1/payClasses` — returns 403 with `heavyjob:read` scope; may need `setups:read`

The HCSS developer portal lists endpoints that don't exist for non-E360 accounts. Treat the docs as a starting point, then verify.

---

## 4. Pagination — Cursor, NOT skip/limit

Every list endpoint uses **cursor pagination**, not `skip`/`offset`. Mistakes here cost us a week.

**Pattern:**
```
GET /heavyjob/api/v1/jobs?businessUnitId=<uuid>&limit=1000
```
Returns:
```json
{
  "results": [...],
  "metadata": { "nextCursor": "AIC19_V_nwghici-odtNS48xAd-hUYsb=" }
}
```

If `nextCursor` is present, fetch the next page:
```
GET /heavyjob/api/v1/jobs?businessUnitId=<uuid>&limit=1000&cursor=AIC19_V_...
```

Keep going until `nextCursor` is missing or `results` is empty. Some response shapes nest under `results`, others under `items` or `data`, or sometimes return a bare array — handle all four.

**Default `limit`** is 1000. Higher values (e.g. 5000) sometimes work, sometimes silently cap.

---

## 5. Two-Step Timecard Fetch

`/timeCardInfo` returns SUMMARIES only — id, date, foremanId, no cost codes or hours. To get the full breakdown:

```
1. GET /timeCardInfo?jobId=<uuid>&startDate=YYYY-MM-DD  → list of {id, date, foremanCode, foremanDescription}
2. For each: GET /timeCards/{id}  → full detail
```

**Detail response shape:**
```json
{
  "id": "...",
  "date": "2026-04-15T00:00:00",
  "foremanCode": "1042",
  "foremanDescription": "Austin",
  "costCodes": [
    {
      "timeCardCostCodeId": "tcc-uuid",
      "costCodeCode": "312310",
      "quantity": 144,
      "unitOfMeasure": "CY",
      "isTm": false
    }
  ],
  "employees": [
    {
      "employeeCode": "1042",
      "employeeDescription": "Austin",
      "payClassCode": "OPERATOR",
      "regularHours":  [{ "timeCardCostCodeId": "tcc-uuid", "hours": 8.0 }],
      "overtimeHours": [{ "timeCardCostCodeId": "tcc-uuid", "hours": 1.0 }],
      "doubleOvertimeHours": [...],
      "costAdjustments": [{ "timeCardCostCodeId": "tcc-uuid", "amount": 0 }]
    }
  ],
  "equipment": [
    {
      "equipmentCode": "DZ-12",
      "equipmentDescription": "Dozer 12",
      "totalHours":     [{ "timeCardCostCodeId": "tcc-uuid", "hours": 8.0 }],
      "operatingHours": [{ "timeCardCostCodeId": "tcc-uuid", "hours": 7.5 }]
    }
  ]
}
```

To roll up per (date × cost code × foreman), build a `timeCardCostCodeId → costCodeCode` map from the `costCodes[]` array, then sum employee/equipment hours by that key.

---

## 6. The Big One — `POST /jobCosts/advancedRequest`

This is where dollars come from. Returns per (date × cost code × foreman) BELMOS dollars + hours + qty in a single paginated call.

**Request:**
```
POST https://api.hcssapps.com/heavyjob/api/v1/jobCosts/advancedRequest
Authorization: Bearer <token>
Content-Type: application/json

{
  "jobIds":         ["<job-uuid>"],          // optional — omit for all
  "jobTagIds":      [],                      // optional
  "foremanIds":     [],                      // optional
  "costCodeIds":    [],                      // optional
  "businessUnitId": "<bu-uuid>",
  "startDate":      "2026-01-01",            // optional
  "endDate":        "2026-04-28",            // optional
  "modifiedSince":  null,                    // optional, RFC-3339
  "cursor":         null,                    // for pagination
  "limit":          1000
}
```

**Response (per row):**
```json
{
  "costCodeId":      "aabbf5b2-...",
  "foremanId":       "e3786ed5-...",
  "date":            "2026-04-15T00:00:00",
  "quantity":        144.0,
  "laborHours":      20.3,
  "laborCost":       810.89,
  "equipmentHours":  2.0,
  "equipmentCost":   130.6,
  "materialCost":    720.0,
  "subcontractCost": 0,
  "truckingCost":    0
}
```

Wrapped in `{ results: [...], metadata: { nextCursor: "..." } }`.

**Important:** `costCodeId` here is the cost code's UUID. To translate to the human-readable code (e.g., "312310"), join against `/costCodes?jobId=...` which returns `{ id, code, description, ... }`. Note: jobCosts may reference codes that don't appear in the costCodes endpoint for that job — likely soft-deleted or BU-shared codes. Plan for unmapped UUIDs (we use a `??<uuid8>` placeholder and backfill later).

---

## 7. Cost Codes Response — Way Richer Than Docs Suggest

The docs only show a handful of fields, but the real `/costCodes?jobId=<uuid>` response includes per-code BUDGETS for free:

```json
{
  "id":          "db7eb22a-3164-49a5-bb9d-a4a89d7eb3a7",
  "code":        "990000",
  "description": "CONVERSION COST",
  "unit":        "EA",
  "unitOfMeasure": "EA",
  "businessUnitId":   "152ef093-...",
  "businessUnitCode": "MANAGER",
  "jobId":   "78de2286-...",
  "jobCode": "100",
  "status":            "active",
  "isHiddenFromMobile": false,
  "isDeleted":          false,
  "isCapExpected":      true,
  "isTm":               false,
  "quantityDrivingEntityType": "none",
  "isPayItemDriver":    false,
  "payItemFactor":      1,
  "quantity":           0,
  "laborHours":         0,
  "equipmentHours":     0,
  "laborDollars":       0,
  "equipmentDollars":   0,
  "materialDollars":    0,
  "subcontractDollars": 0,
  "supplyDollars":      0,
  "customCostTypeDollars": [],
  "historicalActivityCode": "",
  "historicalBiditem":     "",
  "heavyBidEstimateCode":  "",
  "jobDescription":        "SHOP"
}
```

So per cost code you get budgeted qty, budgeted labor/equipment hours, and the full BELMOS-style budget split (`laborDollars`, `equipmentDollars`, `materialDollars`, `subcontractDollars`, `supplyDollars`). Plus optional links back to HeavyBid (`heavyBidEstimateCode`, `historicalActivityCode`, `historicalBiditem`).

This means you may not need `/advancedBudgets/material` at all — the per-code budget is right here.

---

## 8. Rate Limits — 429 with retry hint

HCSS responds with HTTP 429 when you burst:
```json
{
  "statusCode": 429,
  "message": "Rate limit is exceeded. Try again in 14 seconds."
}
```

The `Retry-After` header is sometimes set, sometimes not. The body's "Try again in N seconds" is the reliable signal.

**Burns' retry helper:**
```typescript
async function hcssRequest(method, url, token, body) {
  for (let attempt = 1; attempt <= 4; attempt++) {
    const res = await fetch(url, {
      method,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Accept': 'application/json',
        ...(method === 'POST' ? { 'Content-Type': 'application/json' } : {}),
      },
      ...(method === 'POST' && body ? { body: JSON.stringify(body) } : {}),
    });

    if (res.status === 429 && attempt < 4) {
      const txt = await res.text();
      const m = txt.match(/(\d+)\s*seconds?/i);
      const waitSec = m ? Math.min(60, parseInt(m[1], 10) + 2) : Math.min(60, 5 * attempt);
      await new Promise(r => setTimeout(r, waitSec * 1000));
      continue;
    }
    if (!res.ok) throw new Error(`${method} ${url} → ${res.status}`);
    return await res.json();
  }
  throw new Error('exhausted retries');
}
```

**Proactive throttle:** When iterating jobs (51 active jobs in our case, calling `jobCosts/advancedRequest` per job), add a 250ms `setTimeout` between iterations so the loop doesn't burst. With both proactive throttle + retry, Burns ran a 51-job × full-history backfill in 25 seconds with zero errors.

---

## 9. Gotchas + Lessons Learned

1. **Wrong path AND wrong ID type both 404.** The original mistake at Burns: we used `/heavyjob/api/v1/timeCards` (wrong path — should be `/timeCardInfo`) AND passed `jobId=775` (wrong — should be the UUID). Both errors return 404, and HCSS doesn't tell you which one is wrong. Verify with the developer portal.

2. **Case matters in URL paths.** `/heavyjob/api/v1/businessUnits` works. `/heavyjob/api/v1/BusinessUnit` returns 404.

3. **The developer portal occasionally lies.** HCSS support initially told us `businessUnits` was under `/setups/`. It's actually under `/heavyjob/`. Always verify with a real call.

4. **403 ≠ scope problem.** It can also be wrong product prefix. `/setups/api/v1/BusinessUnit` returns 403 even with `setups:write` scope — because there's a different working path under `/heavyjob/`.

5. **`/employees` doesn't expose pay rates.** You'll need a separate source for labor cost calculations if you can't use `jobCosts/advancedRequest` (which delivers labor $ pre-computed).

6. **Equipment master list is missing.** Use the `equipment[]` array embedded in timecard details to discover equipment codes/descriptions over time.

7. **POST endpoints with cursor pagination** put cursor in the BODY, not the URL. Different from GET endpoints which use `?cursor=`.

---

## 10. Suggested Sync Architecture

Pulling from experience at Burns:

1. **Metadata sync (run on demand, low frequency):** Pull all jobs + cost codes for ALL jobs (not just active). Inactive jobs still have historical data referencing their codes. Without this you'll drop ~67% of cost rows as "unmapped." Cache the `id → code` mapping locally.

2. **Timecard sync (daily cron):** Use the two-step pattern (`/timeCardInfo` → `/timeCards/{id}`) for the last N days. This gives hours, qty, equipment usage. Lookback ~14-30 days to handle late approvals.

3. **Cost sync (daily cron):** `POST /jobCosts/advancedRequest` per active job. Same lookback. This is what gets you fresh BELMOS dollars without waiting on accounting.

4. **Budget sync (run on demand):** Either pull `/costCodes?jobId=` (already has budgets in the response) or `/jobs/{jobId}/advancedBudgets/{material|subcontract}` for explicit budget values.

5. **Run them in this order on first deploy:** Metadata → Timecards → Costs → Budgets. Metadata first so the others can translate UUIDs.

---

## 11. Useful URLs

- **API base:** `https://api.hcssapps.com`
- **Developer portal:** `https://developer.hcssapps.com` (login required)
- **API reference:** `https://developer.hcssapps.com/hcss/reference`
- **Token troubleshooting:** `https://developer.hcssapps.com/getting-started/troubleshoot-unauthorized`
- **403 troubleshooting:** `https://developer.hcssapps.com/getting-started/troubleshoot-forbidden`
- **Bad-request troubleshooting:** `https://developer.hcssapps.com/getting-started/troubleshoot-bad-request`

---

## 12. Quick-Start Checklist

For a fresh Claude in a new project, do these in order:

- [ ] Get HCSS client_id + client_secret from your HCSS account contact
- [ ] Mint a token at `/identity/connect/token` with the working scope set above. Confirm you get a 200 with an `access_token`.
- [ ] Call `GET /heavyjob/api/v1/businessUnits` and capture your BU `id` (UUID).
- [ ] Call `GET /heavyjob/api/v1/jobs?businessUnitId=<uuid>` and confirm you see your jobs. Skip the placeholder job with `jobCode: "0"`.
- [ ] Pick one real job. Get its `id`.
- [ ] Call `GET /heavyjob/api/v1/costCodes?jobId=<uuid>`. Inspect the response — you should see per-code budgets baked in.
- [ ] Call `GET /heavyjob/api/v1/timeCardInfo?jobId=<uuid>&limit=5`. You should see summary records.
- [ ] Pick one timecard id. Call `GET /heavyjob/api/v1/timeCards/{id}` and confirm you get full detail with `costCodes[]`, `employees[]`, `equipment[]`.
- [ ] Call `POST /heavyjob/api/v1/jobCosts/advancedRequest` with `{ jobIds: ["<uuid>"], businessUnitId: "<bu-uuid>", limit: 5 }`. You should see per (date × cost code × foreman) rows with BELMOS dollars.
- [ ] Implement the cursor pagination loop, the 429 retry, and the two-step timecard fetch.

Once those eight calls return 200 with real data, you've cleared every gotcha that took Burns weeks to figure out.
