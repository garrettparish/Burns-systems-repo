# Burns Systems — Project Controls App · Claude Handoff

**You are picking up work on Burns Dirt's project controls web app, mid-build.** This file is the orientation doc — read it first, then `CLAUDE_LOG.md` for the rolling history. Don't skim; the gotchas section will save you a session.

---

## 0. Quick start

**Repo root:** `~/Desktop/Burns System Repo`
**Live site:** `https://bdcprojectcontrols.netlify.app`
**Owner:** Garrett Parish (`garrett.parish@gmail.com`) — construction project controls builder at Burns Dirt
**Brother / collab:** Nic Parish — runs `burns-finance` Supabase, owns Spectrum side
**Stack:** single-file vanilla JS HTML app + SheetJS + Supabase + Supabase Edge Functions (Deno)
**Deploy:** double-click `deploy.command` (auto-stages, syntax-checks, commits, pushes; Netlify auto-builds)
**Edge Function deploy:** `cd ~/Desktop/Burns\ System\ Repo && supabase functions deploy hcss-sync-actuals --no-verify-jwt`

**Key files:**
- `public/index.html` — entire front-end (~12k lines, one inline `<script>`)
- `supabase/functions/hcss-sync-actuals/index.ts` — Deno Edge Function for HCSS sync
- `supabase/migrations/*.sql` — DB schema migrations
- `CLAUDE_LOG.md` — rolling session log, append entry on every deploy
- `HCSS_API_Reference.md` — full HCSS API docs (working endpoints, gotchas)
- `Project Controls System/HCSS_API_Handoff.md` — self-contained API guide for Nic's separate project
- `deploy.command` — one-click deploy script (Mac, includes pre-deploy syntax gate)

---

## 1. Working with Garrett — communication style

- **Be direct, practical, terse.** Don't narrate; do the work and report results. Verbosity feedback is in memory at `~/Library/Application Support/Claude/.../memory/feedback_verbosity.md`.
- **Suggest improvements proactively.** If his approach works but isn't ideal, say so with a one-line reason and a better alternative.
- **Push back when he's wrong.** Don't blindly agree. Multiple times this session his pushback corrected my over-engineering — he's good at catching bad assumptions.
- **Match existing UI patterns exactly.** New features should look like adjacent ones. Reference: `feedback_ui_pattern.md` in memory.
- **Mapping hierarchy — never skip levels:** Task → Bid Item → Activity. Require bid-item mapping before activity-level. Reference: `feedback_mapping_hierarchy.md`.
- **CLAUDE_LOG.md must be updated WITH every deploy, not at session end.** Trigger = Garrett presses `deploy.command`. Add a session-log bullet + Recently Shipped entry + bump the "Current App State (as of YYYY-MM-DD)" header date in the same push. Reference: `feedback_claude_log.md`.

---

## 2. Current focus — open work, ordered

The right next-feature sequence (decided 2026-04-30 to 2026-05-01 after an architectural reframing — see "Source-aware data model" below):

| # | Feature | Why it's prioritized |
|---|---|---|
| **#27** | Manual % complete with multi-source references | Replaces fake-confident HJ-qty-driven %. Optional override (NOT forced). Defaults to best-of HJ-qty / billed / cost. PM owns the override field. |
| **#28** | Leading indicators strip on Overview | Productivity rate trend, $/qty vs bid (clean signal), hours burn vs sched, equipment activation lag, schedule-vs-actual divergence, HJ↔Spectrum convergence. |
| **#29** | HJ data quality flags + cleanup queue | Surfaces foreman miscoding patterns, $0-material-likely-missed, hours>14/day, qty>0-but-$0. Becomes the to-do list for the upstream HJ cleanup project. |
| **#30** | Closeout reconciliation report | HJ Labor + HJ Equip + Spectrum Mat + Spectrum Sub = realistic actual. Compare to billings = real margin. Exportable. Automates a manual month-end process. |
| **#31** | Pay-app forecast / draft generator | qty installed × bid unit price → next pay app. Not a replacement for ProjectSight/Procore — a draft for review. Catches under-billing as leading revenue indicator. |
| **#32** | Configurable 30-day blend cutover per job | `job.meta.blendCutoverDays`, default 30, range 15–60. Editable in Edit Job. |
| **#23** | Daily Log build (diaries + photos + docs) | `POST /diaries/search` + `POST /attachment/advancedRequest` already validated working. Photos have GPS lat/lng → killer photo-map view. |
| #11 | Dual-budget mismatch flag (HJ-side vs HeavyBid budgets) | Slim version: just a flag, not full dual display. Helps spot when HJ users adjust budgets out of sync. |
| #5  | Activity → phase code mapping UI in Set Up | Many cost codes are unmapped today; cleanup tool would fix it. |
| #9  | Overview KPI strip with Spectrum month-start + HJ mid-month | Less urgent — most of what this would surface is already in Daily Insights. |
| #12 | Spectrum sync (Burns-side import, don't wait on Nic) | Future hardening — currently we read from Nic's burns-finance project. Independent fallback. |

**Default to #27 next** unless Garrett says otherwise. Do them ONE at a time. Ship small, validate, move on.

---

## 3. Architectural decisions you must respect

### 3.1 HJ data trust hierarchy (the most important rule)

| Field | Source | Trust |
|---|---|---|
| Labor $ + hours | HJ HeavyJob | **Gospel** — drives payroll, audited weekly |
| Equipment $ + hours | HJ HeavyJob | **Gospel** |
| Material $ | Spectrum (when posted) → HJ-30d (live) | Spectrum is gold; HJ-30d is "live but uncleaned, judgment required" |
| Subcontract $ | Spectrum (when posted) → HJ-30d (live) | Same |
| Production qty | HJ qty (reference) + manual override | HJ qty is reference only; foremen often enter wrong UOM or skip entries. PM judgment overrides. |
| % Complete | Manual field (default = best-of refs) | NEVER lock to a single source. Don't auto-calc from billings (lagging). |

### 3.2 30-day blend rule — hard cutover

```
≥30 days old: Spectrum is gospel
<30 days old: HJ-30d only — LIVE tag, judgment required
```

Garrett's exact words: *"set a hard 'these numbers are good if everything in spectrum' at 30 days and then everything less than 30 days with HJ is up for judgement and discretion."*

Implemented as Approach 2 (explicit time-window split):
```
actualMat = Spectrum.jtd_mat + HJ_jobCosts_where_date_>=_(today-30d).mat
            ↑ baseline (>30d, posted)    ↑ recent (HJ-only, not yet in Spectrum)
```

**Don't switch to greater-of.** Garrett pushed back on it explicitly — undercounts. Always use the explicit time-window split.

### 3.3 Confidence tagging — every $ shows its trust level

Per cost code, per BELMOS component:
- `clean` — HJ Labor or Equipment (gospel)
- `reconciled` — Spectrum has it, posted
- `mixed` — both Spectrum and HJ-30d contributed
- `live` — HJ-30d only, uncleaned, judgment required
- `flagged` — data quality issue
- `none` — no data

Worst-of-row → `confidenceGrade` shown as a colored pill next to the cost code in Production Tracker. Hover for per-component breakdown. Aggregate banner above the table: "$X CLEAN · $Y RECONCILED · $Z LIVE · ..."

Helpers: `confidencePill(grade, tooltipHtml)`, `confidenceTooltipFor(actualsRow)`. Defined just before `computeJobScheduleDivergence` in `index.html`.

### 3.4 Leading vs lagging — the whole point of the app

Garrett: *"we need a leading indicator not a lagging. The whole point of this is to use and digist most up todate data to give us leading indicators to fix, solve, predict problems or gains."*

What this means for design choices:
- For LIVE views (Production Tracker, Overview, Daily Insights): fresh > clean. HJ data even when dirty wins because Spectrum is too lagging to be useful in the moment.
- For CLOSEOUT views (#30 reconciliation report): clean > fresh. Use the trusted-source blend (HJ Labor+Equip + Spectrum Mat+Sub).
- Never replace a fresh-but-dirty value with a clean-but-lagging one in the live view. Tag it as LIVE, surface confidence, let the PM decide.

### 3.5 JCS variance > budget variance for in-progress jobs

Cost variance = `JCS Plan to date − Actual` (NOT budget − actual).

Helper: `computeJCSPlannedByCode(job, refDate)` returns map of phaseCode → planned $. Per-activity pro-rata between `_barStart` and `_barEnd` at refDate, bucketed by phaseCode. Used by Production Tracker + the JCS Variance KPI tile. Garrett's words: *"the cost variance is pretty much usless, it needs to show cost we should have accrued based of the JCS vs what we acutally have right?"*

Bid-vs-spent variance is fine for closeout but useless in-progress (it just means "you haven't spent it all yet").

---

## 4. Code conventions

### 4.1 Single-file front-end

Everything lives in `public/index.html`:
- One inline `<script>` block (~12k lines)
- No build step — pure script tag
- No npm — libs loaded from `cdnjs.cloudflare.com` via `<script src=...>`
- `Store` (line ~740): the in-memory state. NOT on `window` (closure-scoped const). Access via the helper functions in scope.

### 4.2 Don't expose closure state to `window`

`Store`, `_currentUser`, `_activeSubTab`, etc. are inside the script closure. Don't try to access them via `window.Store` from `javascript_tool` — won't work. Use the helper functions that ARE on window:
- `hcssLoadIntoActiveJob()` — the active-job refresh
- `applyHcssJobCostsToActuals(job)` — confidence-tagged merge
- `runSelfTest()`, `renderSelfTestBanner()` — diagnostics
- `computeJCSPlannedAt`, `computeJCSPlannedByCode` — JCS math
- `blendedActualsByCode(job, asOf)` — source-aware blend

### 4.3 Function declarations, not arrow expressions, at top level

Top-level `function foo() {}` becomes accessible (e.g., for DOM `onclick=` handlers). Top-level `const foo = () => {}` does NOT. Don't change existing function declarations.

### 4.4 Inline styles + CSS classes

Mix of both throughout. Match the surrounding pattern. Tailwind/utility frameworks are NOT used — write CSS inline or add to the `<style>` block at the top.

### 4.5 Defensive shape handling

`job.actuals` is an **array** of `{code, ...}` rows (built by `rollupActualsDetail` via `Object.values(byCode)`). Defensive readers should normalize:
```js
const arr = Array.isArray(job.actuals) ? job.actuals : Object.values(job.actuals||{});
for(const a of arr){ if(!a||!a.code) continue; ... }
```
A subtle bug treating it as a keyed map silently corrupted Steel Driver mid-session — see Gotchas below.

---

## 5. Gotchas — the 6-pack you'll trip over otherwise

1. **`job.actuals` is an ARRAY, not an object map.** Mutating it via numeric-string cost-code keys (`obj["190000"] = ...`) inflates the array length to 190,001 with sparse nulls. `loadJobs` now sanitizes on load (drops non-objects, dedupes by `code`, ensures Array shape) but new code must follow array conventions. Always use `Array.isArray` + `for-of`.

2. **HCSS endpoint paths are nested + POST for the rich queries.** Don't try flat paths like `/heavyjob/api/v1/quantities` — they'll 404. The pattern that works: `POST /heavyjob/api/v1/jobCosts/advancedRequest` with `{jobIds, businessUnitId, startDate, limit}` body. Use the `?scanEndpoints=1` mode of the Edge Function to test new candidates before building on them.

3. **HCSS rate-limits with a "try in N seconds" body.** `hcssRequest()` helper auto-parses + retries up to 4 times. Don't write fresh `fetch()` calls in the Edge Function — route everything through `hcssRequest()`. Add a 250ms inter-job pause for any per-job loop or you'll burst into a 429.

4. **New Supabase tables must use `to authenticated`, not `to anon`, for read RLS.** The `20260420_auth_rls.sql` migration switched all HCSS read tables. New tables that use `to anon` will be invisible to logged-in users (data lands but doesn't show). Reference pattern: `20260420_auth_rls.sql`.

5. **Migration filenames: pure 14-digit timestamp.** `20260428b_foo.sql` is rejected by Supabase CLI. Use `YYYYMMDDHHMMSS_name.sql`.

6. **JCS planned curve uses activity envelopes, not linear time elapsed.** Front-loaded jobs ramp before mid-point; back-loaded jobs spike late. `computeJCSPlannedAt` walks `buildActivityEnvelopes(job)` (which mirrors the JCS view's logic) and pro-rates. Don't go back to `(elapsedDays/totalDays)` — Garrett pushed back on it explicitly.

---

## 6. Deployment & verification flow

### Front-end deploy

```bash
cd ~/Desktop/Burns\ System\ Repo
# Edit public/index.html, save
# Then double-click deploy.command (or run it from terminal)
```

`deploy.command` does:
1. **Pre-deploy syntax gate** (Node parses every inline `<script>` block; aborts on syntax error). Bypass with `SKIP_SYNTAX_CHECK=1` if needed.
2. `git add -A && git commit -m "Deploy: YYYY-MM-DD HH:MM" && git push origin main`
3. Netlify auto-builds in ~30s.

### Edge Function deploy

```bash
cd ~/Desktop/Burns\ System\ Repo
supabase functions deploy hcss-sync-actuals --no-verify-jwt
```

Front-end and Edge Function are deployed independently. Front-end changes → `deploy.command`. Edge Function changes → `supabase functions deploy`.

### After every deploy

1. Update `CLAUDE_LOG.md` (Session Log entry + Recently Shipped bullet + bump the "as of" date).
2. Verify the change live (e.g., `https://bdcprojectcontrols.netlify.app/?selftest=1` runs the in-app self-test).
3. If touching the data model, run `runSelfTest()` from the Settings → Diagnostics button.

### Verification — three-layer toolkit

| Layer | Trigger | What it does |
|---|---|---|
| 1. In-app self-test | `?selftest=1` URL flag, or Settings → Diagnostics → Run Self-Test | 15 invariants on data shape, helper presence, math tie-outs, confidence tagging integrity. Banner top of page. Last run cached in `localStorage.bdc_selftest_last`. |
| 2. Pre-deploy gate | Built into `deploy.command` | Node syntax-check on `public/index.html`; aborts push on error. |
| 3. Daily scheduled | Cowork scheduled task `burns-systems-daily-self-test`, daily 6:07am | Hits live site with `?selftest=1`, alerts on failures only. Runs autonomously after first "Run now" approval. |

---

## 7. Data sources

### 7.1 HeavyBid (xlsx imports)

User uploads three files in Set Up:
- **Activities xlsx** → `job.activities[]` (each: code, phaseCode, biditem, description, quantity, units, productivityRate, directTotal, manHours, calculatedDays, labor/burden/eqp/mat/subs/trucking)
- **Bid Items xlsx** → `job.bidItems[]` (each: biditem, description, type, units, bidQuantity, takeoffTotal, directTotal, indirects, addonBond, markup)
- **Smartsheet Schedule xlsx** → `job.schedule[]` (each: id, name, start, finish, crews, predecessors)

`directTotal` from activities is the **canonical budget** for each cost code. Use it whenever Summary xlsx + Detail Expected fail (see 334120 fix in `rollupActualsDetail`).

### 7.2 HCSS HeavyJob API

**Auth:** OAuth2 client credentials at `https://api.hcssapps.com/identity/connect/token`. Scopes: `heavyjob:read heavyjob:write timecards:read e360:read e360:timecards:read`. Secrets in Supabase env: `HCSS_CLIENT_ID`, `HCSS_CLIENT_SECRET`, `HCSS_BUSINESS_UNIT_CODE=MANAGER`.

**Working endpoints** (validated 2026-04-28):

| Endpoint | Method | Purpose |
|---|---|---|
| `/heavyjob/api/v1/businessUnits` | GET | BU list |
| `/heavyjob/api/v1/jobs?businessUnitId=...` | GET | Job list |
| `/heavyjob/api/v1/costCodes?jobId=...` | GET | Cost codes per job (rich response — includes laborDollars/equipmentDollars/materialDollars/subcontractDollars budgets) |
| `/heavyjob/api/v1/employees` | GET | Employee list |
| `/heavyjob/api/v1/timeCardInfo?jobId=...&startDate=...` | GET | Timecard summaries |
| `/heavyjob/api/v1/timeCards/{id}` | GET | Timecard detail (costCodes[], employees[], equipment[]) |
| `/heavyjob/api/v1/jobs/{jobId}/costs` | GET | Per-job cost rollup |
| `/heavyjob/api/v1/jobCosts/advancedRequest` | **POST** | Per (date × code × foreman) BELMOS dollars — the live $ source |
| `/heavyjob/api/v1/costCode/progress/advancedRequest` | **POST** | Quantities by date range |
| `/heavyjob/api/v1/jobs/{jobId}/advancedBudgets/material` | GET | Material budgets |
| `/heavyjob/api/v1/jobs/{jobId}/advancedBudgets/subcontract` | GET | Subcontract budgets |
| `/heavyjob/api/v1/diaries/search` | **POST** | Foreman daily notes (no weather field — HCSS doesn't expose weather) |
| `/heavyjob/api/v1/attachment/advancedRequest` | **POST** | Photos (with GPS lat/lng) + PDFs |

**Confirmed not provisioned (don't waste time):** All `/e360/*` paths (E360 service not provisioned), `/heavyjob/api/v1/equipment` (use embedded equip in timecards), `/heavyjob/api/v1/quantities` (use jobCosts), `/heavyjob/api/v1/dailies`, `/foremen`, `/payClasses` (403 with current scopes).

Pagination is **cursor-based**, not offset. Response shape: `{ results: [...], metadata: { nextCursor: "..." } }`. Some endpoints nest under `items` or `data`. Helper `hcssGetPaginated()` handles all four.

### 7.3 Supabase tables (project: `sxzvlazmkxnbsoayhuln`)

- `jobs` — JSONB blob per job, RLS authenticated
- `hcss_jobs` — HCSS job list (135 rows)
- `hcss_cost_codes` — cost codes per job. Has `cost_code_id` UUID for joins. ~2,373 rows.
- `actuals_detail_sync` — timecard-driven actuals
- `hcss_job_costs` — `/jobCosts/advancedRequest` data, 8,624 rows. Per (job_number, date, cost_code, foreman_id) BELMOS.
- `hcss_equipment` — equipment master discovered from timecards
- `hcss_equipment_history` — per-day equipment usage
- `sync_log` — audit trail
- `job_edits` — multi-user audit log

### 7.4 Spectrum (`burns_dirt` schema in Nic's `burns-finance` Supabase)

Read-only via `sbSpectrum` client (separate URL, separate anon key — both inline in `index.html`).

- `spectrum_jobs` — job header info (contract amount, customer, etc.)
- `spectrum_phases` — per-phase JTD totals. Columns: `job_number, phase_code, cost_type` (single-letter L/E/M/S/B), `jtd_actual_dollars`, `jtd_quantity`, `jtd_hours`, `current_estimate_dollars`, `projected_dollars`, `start_date`, `end_date`.
- **No transaction history / posting date.** Only the running JTD as of `synced_at`. This is why we use Approach 2 time-window split, not perfect overlap detection.

Helper: `classifySpectrumCostType(ct)` maps `L/B/E/M/S` → `labor/equip/mat/sub` (B rolls into labor per construction accounting convention).

---

## 8. Memory references

These persist across sessions. Read on startup if continuing this project.

- `~/Library/Application Support/Claude/.../memory/MEMORY.md` — index
- `feedback_verbosity.md` — work silently, report final results
- `feedback_ui_pattern.md` — match existing patterns exactly
- `feedback_mapping_hierarchy.md` — Task → Bid Item → Activity, never skip levels
- `feedback_claude_log.md` — every deploy = update CLAUDE_LOG.md in same push
- `project_burns_systems.md` — project state
- `reference_supabase.md` — both Supabase projects
- `reference_hcss_api.md` — working endpoints, two-step timecard fetch

---

## 9. Active scheduled tasks

- **`burns-systems-daily-self-test`** — daily 6:07am via Cowork. Hits `?selftest=1`, alerts only on failures. Pre-approved Chrome tools.
- **HCSS Auto-Sync cron** — daily 5am via Supabase Edge Function `hcss-sync-actuals`, lookback 14 days, upserts to `actuals_detail_sync` + `hcss_equipment` + `hcss_equipment_history`. Does NOT yet auto-run `syncJobCosts` (the Pass 1 path) — manually triggered via Setup tab "Sync Costs (Live $)" button or the front-end calls the Edge Function with `{syncJobCosts:true}`. **Wiring `syncJobCosts` into the daily cron is a tracked TODO.**

### 9.1 Migrating the daily self-test off Cowork (when ready)

The daily 6:07am self-test currently runs in Cowork because it needs a real browser to execute the page's JS. Two paths to move it elsewhere:

- **Path A — keep browser-based, swap host.** Run a headless Chrome via GitHub Actions (free tier covers it) on a `cron: '7 11 * * *'` (UTC). Uses Playwright to open `?selftest=1`, reads `localStorage.bdc_selftest_last`, fails the action if any check failed. Closest to current behavior. ~60 lines of YAML + Playwright script.
- **Path B — server-side check, no browser.** Rewrite the most important invariants as a Supabase Edge Function (`selftest-supabase`) that hits the DB tables directly: row counts, no-negative-budget query, RLS policy presence, etc. Schedule via Supabase `pg_cron` calling `pg_net.http_get` on the function URL. More reliable, doesn't need a logged-in session, but only covers DB-side invariants — won't catch front-end JS bugs.

Recommend Path B for the data-quality checks (the 334120-style finds), Path A as a follow-up if front-end regressions become a worry. Both can run in parallel.

Until then, the Cowork task is fine. It's autonomous, free, and works.

---

## 10. Conventions for new work

- **Ship small.** One feature per push. Validate, then move on.
- **Always run `runSelfTest()` after touching the data model.**
- **Always update `CLAUDE_LOG.md`** with the deploy.
- **Match the source-aware confidence model** for new $ surfaces. Don't introduce new merges that bypass `blendedActualsByCode`.
- **Don't add external messaging.** Notifications are in-app only (bell icon, banner). No email/SMS/Slack/Teams unless explicitly approved.
- **Don't auto-modify production data on the user's behalf** without confirmation. Read-only verification is fine; data correction is a separate authorized step.
- **Tooltips over modals.** Hover for detail; click only for substantive actions.
- **The bell badge live-refreshes every 60s.** Don't poll faster.

### 10.1 Deploy & commit policy (Garrett's explicit rules)

- **NEVER auto-deploy.** Never run `deploy.command` or `supabase functions deploy` without explicit confirmation in chat. Stage edits, run the local syntax check, summarize what's about to ship, and ASK before pushing. Garrett wants the human in the loop on every release.
- **Auto-commit is fine** between deploys. You can `git add` + `git commit` as you work without confirmation, as long as you don't `git push` until Garrett approves a deploy. Commit messages should be plain and reference the task # if there is one.
- **`deploy.command` is the deploy gate, not just a push.** It runs the syntax check, commits, AND pushes. Treat triggering it as the equivalent of "ship to prod." Same rule applies: confirm before running.
- **Edge Function deploys** (`supabase functions deploy hcss-sync-actuals --no-verify-jwt`) — same rule: confirm before running.
- **CLAUDE_LOG.md updates** can ride along with the user's deploy. Don't push the log change separately.

---

## 11. Open architectural questions

- 4,852 of 8,624 `hcss_job_costs` rows are `??<uuid>` placeholders (codes not in our `hcss_cost_codes` for the job they appear under — likely deleted/historical/BU-shared). If their $ is material, need a master-cost-codes scan or manual rename UI.
- Path B blend (daily Spectrum snapshots into `spectrum_snapshots` table) only worth building if the Approach-2 overlap risk monitor starts firing high. Not built yet.
- Closed-job filtering — closed jobs still consume HCSS API quota. Should `syncJobCosts` skip them?
- Stone Blvd 334120 negative-budget root cause is fixed in code, but the underlying HCSS data is still messy. Tracking that cleanup is operational work for the team.

---

## 12. Recent work — last 10 deploys (full history in `CLAUDE_LOG.md`)

1. **JCS-based cost variance + sticky columns** (Production Tracker now shows Budget $ | JCS Plan $ | Actual $ | JCS Var; first 3 columns sticky on horizontal scroll)
2. **Confidence-tagged source-aware merge** (replaces greater-of; Labor/Equip from HJ gospel, Mat/Sub from Spectrum baseline + HJ-30d window; pills + tooltip on every Production Tracker row)
3. **334120 negative-budget fix** (`rollupActualsDetail` accepts HeavyBid activities as canonical fallback when budgetCost ≤ 0; rejects negative `_detailBudget*` fallback values)
4. **Verification toolkit Layers 1-3** (in-app self-test, pre-deploy gate, daily scheduled task)
5. **Scope-adjusted plan toggle** (multiplies activity directTotals by `max(1, qtyInstalled/qtyBid)` per phase for unit-price jobs)
6. **JCS-based Pace metric** (replaces linear time elapsed)
7. **Daily Insights + Notifications foundation** (Pace, Forecast Finish, Stuck Work, Unit Cost Mismatches tiles + bell icon + Settings horizons)
8. **Diary + attachments endpoints validated** (foreman notes + photos with GPS + PDFs — queued for Daily Log build #23)
9. **Pass 2 — front-end merge of `hcss_job_costs`** (greater-of policy preserved any higher xlsx number)
10. **Pass 1 — `syncJobCosts` Edge Function mode + `hcss_job_costs` table** (8,624 rows full-history backfill; mapping rate 33% → 100%)

---

**You're caught up. Read `CLAUDE_LOG.md` for the rolling story, then start on task #27 (Manual % complete with multi-source references) unless Garrett directs otherwise.**
