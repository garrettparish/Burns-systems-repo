# Claude Project Log

> **Purpose:** Claude reads this file at the start of every session to pick up context.
> **Location:** Garrett's desktop workspace — persists across sessions.
> **Rule:** Update this log before ending ANY session.

---

## Owner

- **Name:** Garrett Parish
- **Email:** garrett.parish@gmail.com
- **GitHub:** garrettparish (https://github.com/garrettparish)
- **Netlify:** Active account (existing)
- **Supabase:** Active account (existing)
- **Collaborator:** Nic Parish (brother) — runs burns-finance Supabase, uses Spectrum accounting

---

## Infrastructure

- **Source control:** GitHub
- **Frontend hosting:** Netlify (auto-deploy on push to main)
- **Backend/DB:** Supabase
- **CI/CD:** GitHub Actions + Netlify build hooks
- **Deploy model:** Push to `main` → auto-deploy to production
- **Config files:** `netlify.toml`, `.github/workflows/deploy.yml`

---

## Projects

### Project 1: Burns Systems — Project Controls App
- **Repo:** https://github.com/garrettparish/Burns-systems-repo
- **Netlify site:** https://bdcprojectcontrols.netlify.app
- **Supabase project:** burns-project-controls (org: nic@burnsdirt.com)
- **Supabase URL:** https://sxzvlazmkxnbsoayhuln.supabase.co
- **Supabase ref:** sxzvlazmkxnbsoayhuln
- **DB tables:** `jobs` (JSONB), `hcss_jobs`, `hcss_cost_codes`, `hcss_equipment`, `actuals_detail_sync`, `sync_log`
- **Stack:** Vanilla HTML/CSS/JS + SheetJS (xlsx.js) + Supabase (persistence) + Supabase Edge Functions (Deno)
- **Key files:** `public/index.html` (main app — ~9000+ lines), `supabase/functions/hcss-sync-actuals/index.ts`

### Nic's Finance Dashboard (read-only access)
- **Supabase project:** burns-finance (`bodcpnytvonucefnbmyz.supabase.co`)
- **Netlify site:** burns-finance.netlify.app
- **Schema:** `burns_dirt` (Spectrum accounting data — jobs, phase codes, actuals)
- **Our app reads from this** via second Supabase client with `db: { schema: 'burns_dirt' }`

---

## Current App State (as of 2026-04-20)

### Working Features
- **Import System:** HeavyBid Activities, HeavyBid Bid Items, Smartsheet Schedule parsers
- **Schedule & Financials tab:** Overview, Pay Items, EVA, Forecast, Pay Apps, Cash Flow, Job Cost (Spectrum)
- **Production tab:** Planning (Weekly Planner + 16-week Resource View with Crews/Equipment mode toggle), Schedule (Gantt + task table), Job Cost Schedule, Production Tracker, Settings (Crew Roster + Fleet Roster + Subcontractors)
- **Global View:** Multi-job timeline, resource view
- **HCSS Auto-Sync:** Edge Function syncs timecards from HeavyJob API into Supabase. Daily 5am cron + manual sync. 102 rows across 10 jobs confirmed working.
- **Spectrum Job Cost:** Reads from Nic's burns-finance Supabase. 88 Spectrum jobs, phase codes with Current Estimate, JTD Actual, etc.
- **Crew Planner:** Auto-discovers crews from HCSS foreman data. Weekly day-by-day planner with suggestion engine. 16-week resource outlook. Click-to-assign popovers.
- **Equipment Planner:** Manual fleet roster with categories. Weekly day-by-day planner (mirrors crew planner layout). 16-week equipment outlook. Click-to-assign popovers. Fleet roster table with current location tracking.

### Data Storage Pattern
- **Supabase:** Jobs (JSONB), HCSS sync tables, Spectrum (read-only from burns-finance)
- **localStorage:** Crews (`bdc_crews`, `bdc_crew_name_map`, `bdc_crew_history`, `bdc_crew_plan`), Subs (`bdc_subs`), Equipment (`bdc_equipment`, `bdc_equip_plan`)

### HCSS API Integration (RESOLVED & WORKING)
- **Auth:** OAuth2 Client Credentials → `https://api.hcssapps.com/identity/connect/token`
- **Working endpoints:** `/heavyjob/api/v1/businessUnits`, `/jobs`, `/costCodes`, `/employees`, `/timeCardInfo` (list), `/timeCards/{id}` (detail)
- **Two-step timecard fetch:** List summaries via `/timeCardInfo?jobId=`, then detail via `/timeCards/{id}` for each
- **Pagination:** Cursor-based (`cursor` + `limit`), NOT offset-based
- **All IDs must be HCSS UUIDs**, not job codes
- **Equipment list endpoint:** Returns 404 (not provisioned), but equipment data IS embedded in timecard details
- **Quantities endpoint:** Returns 404, but quantity per cost code is in timecard detail

### Pending / Not Yet Done
- **Backfill All:** Has not been run yet — only 7 days of HCSS timecard history synced. Now that equipment auto-discovery is wired in, running Backfill will populate the Fleet Roster across the full history in one pass.
- **HCSS API Setup Guide:** Generated as `HCSS_API_Setup_Guide.docx` for Nic — complete

### Recently Shipped
- **Production Tracker — outlier cap + Summary-preservation fix (2026-04-20):** Bad qty imports (e.g., Stone Blvd Hydroexcavation budget=1 DY / actual=114.5 DY → 11,450% complete) were blowing up KPI rollups (Productivity 416%, Hours Variance +10,370 hrs). Fix in `renderProductionTracker` (public/index.html ~line 9862): any row with `qtyPct > 500` is flagged `isOutlier`, and its `earnedHrs` is capped at `1.5 × budgetHrs` for the totals rollup only. Cost-weighted % Complete falls back to `actualCost/budgetCost` (capped at 100%) for outlier rows so a single bad qty can't dominate the job. UI: red banner above the KPI tiles counting flagged rows, plus per-row red left-border and `BAD QTY` badge. Commit `3191437`. Second commit `595e485` fixes `rollupActualsDetail` (public/index.html ~line 4747): was only creating `byCode` entries for cost codes present in the Detail file's forEach, which dropped Summary-only codes (e.g., Steel Driver loaded 9 of 33 rows after Detail overwrote the Summary merge). Now seeds `byCode` with every prior Summary code BEFORE the detail loop so Summary budgets are never lost when Detail is layered on top. Live on bdcprojectcontrols.netlify.app.
- **Planning tab crew/equipment toggle + Settings tab (2026-04-17):** Consolidated the old Crews and Equipment sub-tabs. Planning now has a Resource toggle at the top (`Crews` / `Equipment`) that re-renders into the same `#planningContent` div — persisted to `localStorage` as `bdc_planning_mode`. New `sub-settings` panel under Production holds all cross-job rosters in one place: Crew Roster (with Clear All / Clear History / + Assign to Job), Legacy Crew Name Mapping, Fleet Roster (identical UI to the old Equipment tab roster — HCSS badges + ⚠ Set Category chips), Subcontractors. `renderEquipmentPlanner(ctx)` now takes a context arg; `ctx==='planning'` targets `#planningContent`, prepends the mode toggle, and skips the Fleet Roster (roster lives in Settings only). Shared callbacks from modals/popovers route through a new `refreshEquipUI()` helper that picks Planning / Settings / legacy Equipment based on `_activeSubTab`. `renderCrews()` short-circuits to `renderSettings()` when Settings is active, so all the shared `persistCrews();renderCrews();` / `persistSubs();renderCrews();` call sites keep working. Nav: `NAV_GROUPS.production = ['planning','schedule','jcs','production','settings']`; legacy `sub-crews` / `sub-equipment` panels retained but hidden (`display:none`) for backward compat.
- **Equipment auto-discovery from HCSS (2026-04-17):** `hcss-sync-actuals` Edge Function now extracts `equipmentCode` + `equipmentDescription` from every timecard detail and upserts into new `public.hcss_equipment` table. Front-end fetches it on startup via `loadHcssEquipment()` and merges into `Store.equipment`, flagging new entries with `_needsCategory:true` and `source:'hcss'`. Fleet Roster table shows an orange `HCSS` badge + a yellow "⚠ Set Category" prompt next to uncategorized machines — clicking opens the existing Edit modal. `getEquipLastKnownLocation()` now falls back to `hcssLastSeenJob`/`hcssLastSeenDate` so the Current Location column auto-populates. Migration: `supabase/migrations/20260417_hcss_equipment.sql`. Merge rules: user-assigned fields (category/notes/manual location) never touched by sync; HCSS only owns code/description/last-seen.
- **Schedule sub-tab on Financials nav (2026-04-17):** Added Schedule button to `subNav-financials` and added `'schedule'` to `NAV_GROUPS.financials` (also backfilled `'jobcost'` and `'equipment'` which were missing from their respective groups). Same `sub-schedule` panel is shared between Financials and Production — both routes call `renderSchedule()` via the existing dispatcher. Verified live.
- **Equipment Planner deployed (2026-04-17):** Production > Equipment sub-tab live — weekly planner + 16-week outlook (mirrors crew planner). Verified live.

---

## Key Architecture

- `Store = { jobs:{}, activeJob:null, crews:{}, crewNameMap:{}, crewHistory:[], crewPlan:{}, subs:{}, staging:{}, _pinAuth:{}, equipment:{}, equipPlan:{} }`
- Each job: `{ meta, activities[], bidItems[], schedule[], taskMap:{}, actualsDetail[], actuals:{} }`
- Single-file app: `public/index.html`
- Edge Function: `supabase/functions/hcss-sync-actuals/index.ts` (Deno runtime)
- Rendering: `renderActiveSubTab()` dispatches to per-tab render functions
- Sub-tab nav: `navSub(group, sub)` — groups are `financials` and `production`
- Equipment Planner: `renderEquipmentPlanner()` — mirrors `renderPlanning()` pattern exactly

---

## Key File Reference

| File | Purpose |
|------|---------|
| `public/index.html` | Main app — all UI, logic, state management (~9000+ lines) |
| `supabase/functions/hcss-sync-actuals/index.ts` | HCSS API sync Edge Function |
| `supabase/migrations/20260409_hcss_sync.sql` | Creates `actuals_detail_sync`, `sync_log`, cron |
| `supabase/migrations/20260414_hcss_metadata_sync.sql` | Creates `hcss_jobs`, `hcss_cost_codes` |
| `HCSS_API_Reference.md` | Full HCSS API documentation |
| `HCSS_API_Setup_Guide.docx` | Complete walkthrough doc for Nic |
| `CLAUDE_LOG.md` | This file — session context |
| `deploy.command` | One-click deploy script (Mac) |
| `netlify.toml` | Netlify build config |

---

## Decisions & Rationale

| Decision | Rationale | Date |
|----------|-----------|------|
| Multi-project (separate repos) | Garrett working on multiple projects | 2026-04-03 |
| Push-to-main = production deploy | Simple CI/CD | 2026-04-03 |
| Bid items as primary unit | Activities are audit-only; bid items drive views | 2026-04-03 |
| Single-file HTML app | Simple deploy, keeps everything together | 2026-04-03 |
| localStorage for crews/equipment | No deploy needed, instant, mirrors in-memory Store | 2026-04-14 |
| Two-step HCSS timecard fetch | `/timeCardInfo` = summaries only; `/timeCards/{id}` = full detail | 2026-04-16 |
| Cursor-based pagination for HCSS | HCSS doesn't support skip/limit — must use cursor + limit | 2026-04-16 |
| Equipment planner mirrors crew planner | User specifically requested same layout as Planning tab | 2026-04-17 |
| Read Spectrum via second Supabase client | Nic's burns-finance project has accounting data we need | 2026-04-14 |

---

## User Preferences (Garrett)

- **Communication:** Direct, practical, skip fluff. Don't give little updates — work silently and report final results.
- **Role:** Product designer + builder, experienced with construction project controls
- **Collaborator Nic:** Brother, handles finance/accounting side, uses Spectrum
- **Deploy workflow:** Pushes front-end via GitHub (auto-deploys to Netlify). Edge Functions via `supabase functions deploy`.
- **Proactive suggestions welcome** — challenge decisions when a better approach exists

---

## Session Log

### 2026-04-03 — Sessions 1-3
- Built complete Phase 1A project controls app
- Set up GitHub, Netlify, Supabase infrastructure
- Import system, Dashboard, Bid Items, Schedule, Global View
- Fixed date serialization, parser bugs, Supabase table creation

### 2026-04-14 — Sessions 4-5
- Built HCSS API integration (Edge Function)
- Discovered correct endpoints after extensive troubleshooting with HCSS support
- Built Spectrum Job Cost integration (reads from Nic's burns-finance Supabase)
- Added Weekly Crew Planner, Resource View, Production Tracker

### 2026-04-16 — Session 6
- Fixed HCSS timecard sync (was 404 → now working: 102 rows, 10 jobs)
- Three root causes: wrong paths, wrong ID format, wrong pagination
- Implemented two-step fetch (timeCardInfo → timeCards/{id})
- Tested Spectrum integration live (88 jobs, 300 phase codes confirmed)

### 2026-04-17 — Session 7 (Current)
- Generated HCSS_API_Setup_Guide.docx for Nic
- Built Equipment Planner tab (Production → Equipment)
  - First version: custom grid + gantt views
  - Rewrote to match Planning tab pattern per user feedback
  - Weekly Equipment Planner (day-by-day, click-to-assign popovers)
  - 16-week Equipment Outlook (resource view)
  - Fleet Roster with category grouping and location tracking
- User requested: Schedule view on Financials tab — NOT YET BUILT
- Updated CLAUDE_LOG.md and all reference docs for session handoff

### 2026-04-17 — Session 8
- Added Schedule sub-tab to Schedule & Financials nav (same `renderSchedule()` / `sub-schedule` panel used by Production > Schedule)
- Updated `NAV_GROUPS`: added `schedule` + `jobcost` to financials, added `equipment` to production (these were missing and would have reset the sub-tab when switching top tabs)
- Deployed Equipment Planner and the Schedule-in-Financials change via `deploy.command` (commits 90f55c1 + 90d719a on main)
- Verified live on bdcprojectcontrols.netlify.app — Financials → Schedule renders KPIs + Gantt; Production → Equipment renders weekly planner + 16-week outlook

### 2026-04-17 — Session 9 (Current)
- **HCSS equipment auto-discovery** end-to-end:
  - Migration: `supabase/migrations/20260417_hcss_equipment.sql` creates `public.hcss_equipment`
  - Edge Function: `hcss-sync-actuals` extracts `equipmentCode`/`equipmentDescription` from every timecard detail, tracks most recent job+date per machine, upserts in 50-row chunks. Response now includes `equipmentDiscovered` + `equipmentUpserted`
  - Front-end: new `loadHcssEquipment()` merges discovered machines into `Store.equipment` with `_needsCategory:true`, `source:'hcss'`, default category `Other`. Fleet Roster shows HCSS badge + "⚠ Set Category" chip until user confirms via the Edit modal. `getEquipLastKnownLocation()` falls back to `hcssLastSeenJob`/`hcssLastSeenDate`.
- **Planning tab refactor + Settings tab:**
  - Planning now has a Resource toggle at the top (Crews / Equipment), persisted in `localStorage.bdc_planning_mode`. Equipment mode calls `renderEquipmentPlanner('planning')` which targets `#planningContent` and skips the Fleet Roster.
  - New Production > Settings sub-tab (`sub-settings` / `settingsContent`). Houses: Crew Roster (reuses `renderCrewSettings`), Legacy Crew Name Mapping, Fleet Roster, Subcontractors — all cross-job rosters consolidated in one place.
  - Removed Crews and Equipment buttons from `subNav-production`. `NAV_GROUPS.production = ['planning','schedule','jcs','production','settings']`. Legacy `sub-crews`/`sub-equipment` panels kept hidden for backward-compatible render calls.
  - New `refreshEquipUI()` helper routes refreshes to Planning / Settings / legacy based on `_activeSubTab`. `renderCrews()` short-circuits to `renderSettings()` when Settings is active.
- **Pending deploy:** new migration + Edge Function + front-end changes — run `supabase db push`, `supabase functions deploy hcss-sync-actuals`, then `deploy.command` to push front-end.

### 2026-04-20 — Session 10
- **Production Tracker KPI blowout diagnosed and fixed (commit `3191437`, deployed):** Stone Blvd had a Hydroexcavation row imported with budget=1 DY and actual=114.5 DY (user qty-entry error at the source — will get cleaned up down the road). That one row produced `earnedHrs ≈ 13,110` and dominated the rollup: Productivity 416%, Hours Variance +10,370 hrs. Added outlier detection in `renderProductionTracker` (public/index.html ~line 9862): rows with `qtyPct > 500` are flagged `isOutlier`; their `earnedHrs` is capped at `1.5 × budgetHrs` for the totals rollup only (per-row display still shows the real number so the bad data is visible, not hidden). Cost-weighted % Complete falls back to `min(100, actualCost/budgetCost*100)` for outliers instead of `qtyPct`. UI: red banner above KPI tiles counting flagged rows, plus per-row red left-border and `BAD QTY` badge. Verified live — Stone Blvd now reads Productivity 22%, Hours Variance −2,567.6 hrs, Hydroexcavation tagged with BAD QTY.
- **Summary-preservation fix in `rollupActualsDetail` (commit `595e485`):** Steel Driver only surfaced 9 of 33 cost codes after uploading Summary then Detail. Root cause: `rollupActualsDetail` at public/index.html ~line 4747 built `byCode` from the Detail file's forEach loop, so any Summary-only cost code was dropped when Detail layered on top. Fix: seed `byCode` with every entry from `prevByCode` (prior Summary actuals) BEFORE processing `detail`, preserving all budget fields + `_prevActualLabor`-style fallbacks + `_hasSummaryBudget` flag. Detail rows then merge on top instead of replacing.
- **Feedback captured to memory:** `feedback_claude_log.md` — every `deploy.command` press is the trigger to update `CLAUDE_LOG.md` in the same push. Applied for the first time on this session with this entry.
- **Pending deploy:** commit `595e485` (rollup fix) + this CLAUDE_LOG update queued locally — Garrett double-clicks `deploy.command` to ship. After deploy, re-upload Steel Driver Summary then Detail and confirm 33 rows render in Production Tracker.

### Still pending after this session
- Production Tracker — dual-budget display + mismatch flag + extra drill-down columns (task #11)
- Activity → phase-code mapping UI in Set Up (task #5)
- Overview tab — variance/KPI strip (Spectrum month-start + HJ mid-month) (task #9)
- Spectrum sync — Burns-side import (task #12)

### 2026-04-28 — Session 11
- **Verified the Production Tracker fixes live on Steel Driver:** uploaded fresh Cost Code Summary `(44).xlsx` and Detail `(40).xlsx`. Setup card jumped from "9 actuals" → "35 actuals" (was the bug — Detail loop was overwriting Summary-only codes). Production Tracker now shows 35 active codes, 2 BAD QTY rows flagged, KPIs sane (48.1% complete, 50% productivity, −1,288.5 hrs variance). Both `595e485` (Summary preservation) and `3191437` (outlier cap) confirmed working.
- **Discovered an entire suite of HeavyJob cost endpoints we never tested.** Original endpoint scan tried flat paths (`/heavyjob/api/v1/quantities`, `/heavyjob/api/v1/costCodeProgress`) — all 404. The HCSS developer portal docs show the working pattern is nested + uses POST for the rich queries. Confirmed paths from docs:
  - `POST /heavyjob/api/v1/jobCosts/advancedRequest` — costs and hours per cost code (Summary xlsx replacement)
  - `POST /heavyjob/api/v1/costCode/progress/advancedRequest` — qty by date range
  - `GET /heavyjob/api/v1/jobs/{jobId}/costs` — per-job cost rollup
  - `GET /heavyjob/api/v1/jobs/{jobId}/advancedBudgets/{material|subcontract|customCostType}` — per-code budgets (the budget-side bridge)
  - Plus CostAdjustment, CostCodeTransaction, Accounting, PayClass endpoints
- **Why this matters — bridges the Spectrum lag for $:** today's blended-actuals only blends *hours* (Spectrum ≥30d + HJ <30d). For *dollars*, we have no fresh source — Spectrum's 30-day lag means recent-month Production Tracker $ are stale. If `jobCosts/advancedRequest` works under our scopes, that's the bridge: fresh per-code BELMOS dollars for the rolling 30 days.
- **Extended the Edge Function endpoint scanner** with 12 new candidates covering the cost suite (mix of GET and POST; POST sends a minimal filter body). Added as a Phase 3 in the existing `scanEndpoints` mode (`supabase/functions/hcss-sync-actuals/index.ts` ~line 274). Output adds a new `costEndpointResults` array.
- **Scan results (post-deploy):** 5 of 12 endpoints returned 200 — `GET /jobs/{id}/costs`, `POST /jobCosts/advancedRequest`, `POST /costCode/progress/advancedRequest`, `GET /jobs/{id}/advancedBudgets/material`, `GET /jobs/{id}/advancedBudgets/subcontract`. The big one (`jobCosts/advancedRequest`) returned full per-(date × cost code × foreman) BELMOS rows: `{costCodeId, foremanId, date, quantity, laborHours, laborCost, equipmentHours, equipmentCost, materialCost, subcontractCost, truckingCost}`. This solves the bridge problem — fresh $ daily, no Spectrum lag.
- **Pass 1 built (deploy pending):**
  - Migration `supabase/migrations/20260428_hcss_job_costs.sql` — creates `public.hcss_job_costs` table (per-row BELMOS dollars) + adds `cost_code_id` column to `hcss_cost_codes` so we can join API rows back to local cost codes.
  - Edge Function: extended `syncMetadata` to capture `cc.id` into the new column. New mode `syncJobCosts` (POST `{syncJobCosts:true}`) iterates active jobs, paginates `/jobCosts/advancedRequest` via cursor, maps `costCodeId → cost_code` from local table (hot-loads from API if not yet captured), upserts into `hcss_job_costs`. Lookback honors `lookbackDays` (default 14) and `fullHistory:true`.
- **Deploy steps:**
  1. Apply migration: `cd ~/Desktop/Burns\ System\ Repo && supabase db push`
  2. Deploy function: `supabase functions deploy hcss-sync-actuals --no-verify-jwt`
  3. Re-run `{syncMetadata:true}` once to backfill `cost_code_id` for all 938 cost codes.
  4. Run `{syncJobCosts:true}` to populate `hcss_job_costs` for the last 14 days.
- **Pass 1 status (mid-deploy):** Edge Function syncJobCosts is working — probe upsert returns the inserted row with all BELMOS fields populated (e.g., Steel Driver code 312321: `qty:144, labor_hours:20.3, labor_cost:$810.89, equip_cost:$130.60, mat_cost:$720`). But anon/authenticated SELECT returned 0 rows because the 20260428 migration created `hcss_job_costs` with the old anon-only RLS pattern; the 20260420 auth-RLS migration had switched all the other HCSS tables to authenticated. Patched with `20260428b_hcss_job_costs_auth_rls.sql` (drop the anon policy, add `auth users select hcss job costs`). Run `supabase db push` to apply, then re-query.
- **Mapping rate fix (#20) shipped:**
  - `syncMetadata` now pulls cost codes for ALL 135 jobs, not just the 51 active ones. Inactive jobs still have historical jobCosts data referencing their codes, so we need the full mapping to translate costCodeId → cost_code without dropping rows.
  - `syncJobCosts` no longer drops unmapped rows — uses `??<uuid8>` placeholder for `cost_code` so data lands. A subsequent metadata sync that captures the missing code will let us backfill the readable string via `cost_code_id`.
- **Pass 2 wired (front-end, deploy pending):** `public/index.html`
  - New `loadHcssJobCosts(jobCode)` reads from `hcss_job_costs` into `job.hcssJobCosts`.
  - New `applyHcssJobCostsToActuals(job)` rolls up the per-(date × code × foreman) rows by code and merges totals into `job.actuals[code]` using the existing rollup schema (`actualLabor`, `actualEquip`, `actualMat`, `actualSub`, `actualCost`, `actualHours`, `actualEquipHrs`, `qtyInstalled`). Greater-of policy on dollars so a 14-day partial sync can't downgrade a full xlsx Summary that already has costs-to-date. Trucking $ rolls into `actualSub`.
  - New `hcssSyncJobCosts({fullHistory})` button handler. Two new buttons in Set Up: **Sync Costs (Live $)** (orange, last 14 days) and **Backfill Costs** (full history, prompts confirm).
  - `hcssLoadIntoActiveJob` now also runs `loadHcssJobCosts` + `applyHcssJobCostsToActuals` so dollars land in memory whenever a job becomes active.
- **Pending deploy (one push for everything):**
  1. Edge Function: `cd ~/Desktop/Burns\ System\ Repo && supabase functions deploy hcss-sync-actuals --no-verify-jwt`
  2. Front-end: `deploy.command` to push `public/index.html` changes
  3. In the app: hit **Sync Jobs & Codes** (re-runs metadata sync — now covers all 135 jobs), then **Backfill Costs** (one-time full history pull). After that, daily 5am cron + the standard Sync Now is enough.
- **Validation gate before Pass 2 finalize:** confirm Steel Driver Production Tracker $ totals roughly match the Cost Code Summary xlsx numbers. If they do, the Summary upload box can be retired.
- **Rate-limit hardening:** Backfill All hit a 429 on first re-pull ("Rate limit is exceeded. Try again in 14 seconds."). Wrapped all HCSS API calls in `hcssRequest()` which auto-parses the wait-time hint, sleeps, and retries up to 4 attempts. Also added a 250ms pause between job iterations in `syncJobCosts` so a 51-job loop doesn't burst into a 429 in the first place.
- **Validation results (deployed end-to-end):**
  - Backfill Costs ran clean — `8,559 rows fetched, 8,559 upserted, 0 errors, 25s` for 51 active jobs / full history. 429 retry never triggered (the 250ms pause was enough). Total `hcss_job_costs` table size: 8,624 rows.
  - **Mapping rate climbed 33% → 100%** after the two fixes (pull all-jobs cost codes + relax skip with `??<uuid8>` placeholder).
  - 4,852 of 8,624 rows are placeholder codes (`??...`). These reference costCodeIds that the costCodes endpoint doesn't return for the job they appear under — likely historical, BU-shared, or soft-deleted codes. Followup: add a "rename placeholder → real code" UI or hit a master-cost-codes endpoint without the jobId filter.
  - Steel Driver life-of-job from API: **$308k** total ($103k labor + $59k equip + $147k mat). Production Tracker still shows $328k from the xlsx Summary upload (greater-of policy preserved it). When we drop the Summary upload, Production Tracker will read $308k from the API automatically.
- **Pass 2 complete.** Bridge problem solved: fresh per-(date × cost code × foreman) BELMOS dollars are flowing from HCSS API into Supabase into front-end rollup, with rate-limit retry and inter-job throttle. The Cost Code Summary xlsx upload box can be retired in Pass 3 once we're confident the API data is the canonical source.
- **Diary + Attachment endpoints discovered + tested 200:**
  - `POST /heavyjob/api/v1/diaries/search` — per-(job × foreman × date) free-text foreman notes. Sample: foreman "Lee (Dean) Sullivan" on job #100 on 2026-04-28: "Did some work Mac needed done at office on fifth street." Fields: `{id, job{id,code,description}, foreman{id,code,firstName,lastName}, note, tags[], date, revision, lastChangedBy, lastChangedDateTime}`. **No weather field — HCSS API does not expose weather.**
  - `POST /heavyjob/api/v1/attachment/advancedRequest` — photos + PDFs attached to diaries. Body: `{attachmentType:"diary", fileType:"photos"|"pdf"|"all", businessUnitId, jobIds[], foremanIds[], startDate, endDate, cursor, limit}`. Response includes `attachmentUrl` (signed download URL ~440 chars), `thumbnailUrl`, dimensions, `mimeType`, `lastModified`, `referenceDate`, `name`, `note`, plus employee + job context. **Photos include `latitude` + `longitude`** — site-photo map view is feasible. PDFs include auto-generated safety reports.
  - HCSS_API_Handoff.md updated with both endpoints for Nic.
  - Created task #23 for the Daily Log feature build (Edge Function sync + Supabase tables + per-job timeline UI with photo gallery + map view).
- **Daily Insights + Notifications foundation shipped (front-end, deploy pending):** `public/index.html`
  - **Computational helpers (pure, no DOM):** `computeJobScheduleDivergence(job)` (slip days from sched% vs actual%), `computeJobForecastEnd(job)` (predicted finish date from current burn rate), `computeStuckCodes(job, daysThreshold)` (cost codes with no qty entry in N+ days), `computeBidVsActualUnitCost(job, opts)` (worst $/unit drift codes), `scanDiariesForAttention(diaries)` (keyword-based diary triage with severity tags), `computeUpcomingWorkAlerts(allJobs, settings)` (per-horizon list of upcoming tasks). All under a `// DAILY INSIGHTS — computational helpers` section just before `renderDashboard`.
  - **Overview tab — Daily Insights panel:** four tiles (Pace, Forecast Finish, Stuck Work count, Unit Cost Mismatches) plus an inline Top-5 stuck-codes table. Renders inside `renderDashboard` immediately after the existing alerts strip.
  - **Top-bar bell icon (🔔)** with a live badge showing the total upcoming-work alert count across all jobs. Click toggles a 380px popover panel grouped by horizon. Click-outside dismisses. Background `setInterval` refresh every 60s. Sub tasks get a purple SUB badge.
  - **Settings → Notifications card:** configurable day-out thresholds (default 30/15/5, up to 6, range 1–365), Add/Save buttons, "Subs only" filter toggle, current-state preview (alert count per horizon). Persisted to `localStorage.bdc_notif_settings`. Internal alerts only — no external messaging anywhere.
  - **Sub callouts reframed:** instead of texting subs, the system pre-warns Burns staff via the bell. "Subs only" filter narrows the queue to sub-driven tasks for upcoming-work review.
- **Pending deploy (front-end only):** `deploy.command` to push `public/index.html` changes. After Netlify rebuilds, refresh and the bell should appear top-right with a number; Overview shows the new Daily Insights panel; Settings has a Notifications section.
- **Still pending in this 9-feature build:** auto pay-app draft, full bid-vs-actual drill-down detail view, weather overlay (NOAA/OpenWeather + GPS), photo map view (Daily Log #23), dual-budget mismatch flag on Production Tracker rows.
- **Pace metric upgraded to use Job Cost Schedule (JCS), not linear time:** Garrett caught that the original implementation compared total cost to time elapsed, which is wrong for front- or back-loaded jobs. New approach: `computeJCSPlannedAt(job, refDate)` walks every activity's date envelope (built via `buildActivityEnvelopes` reusing the same precedence as `renderJobCostSchedule`) and pro-rates each activity's `directTotal` between its start/finish for any reference date. Pace tile now shows: Planned $ to date, Actual $ to date, $ variance vs plan, plus days "ahead/behind plan" computed by binary-searching the JCS curve for the date when planned would equal actual. Front-loaded jobs that haven't ramped won't read as "behind"; back-loaded jobs that just started won't read as "ahead." Helper `findJCSDateAt(job, targetCost)` provides the crossover date.
- **Scope-adjusted plan toggle (unit price jobs):** Strict mode uses HeavyBid directTotals as-bid. Scope-adjusted mode multiplies each activity's directTotal by `max(1, qtyInstalled/qtyBid)` per phase code, so a job that installed 14,000 CY against a 10,000 CY bid gets a 1.4× scope factor on every activity in that phase. The Pace tile gets a toggle (top-right of the tile, "as-bid" / "scope-adj"), persisted in `localStorage.bdc_pace_scope_adjusted`. When scope-adj is on and any phase is bumped, an orange caption shows "N phases scope-bumped (+$X)" so the user sees how much the budget grew. Implementation touches `buildActivityEnvelopes`, `computeJCSPlannedAt`, `findJCSDateAt`, `computeJobScheduleDivergence` — all accept an `opts.scopeAdjusted` flag. Steel Driver (lump-sum) will read identically in both modes since field qtys typically don't exceed bid; Stone Blvd (unit price) will diverge wherever scope grew.
