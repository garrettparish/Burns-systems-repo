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

## Current App State (as of 2026-04-17)

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
