# Burns Systems — Open Tasks

> Snapshot of in-flight work as of the Claude Code handoff (2026-05-01). Sorted in recommended build order. Task numbers match the prior session's tracker for cross-reference.

## Next up — sequence locked, do these in order

### #27 — Manual % complete with multi-source references
**Status:** pending. Recommended next.
Per cost code: `pctComplete_manual` field. **NOT forced.** Default value = best-of HJ qty %, billed %, cost % (or combo). Always editable by PM when field doesn't match.
- Display: manual value prominently (if set), HJ qty %, billed %, cost % as small reference numbers next to it
- Optional notes field (`pctComplete_notes`)
- Last-updated stamp + by-whom (`pctComplete_updatedAt`, `pctComplete_updatedBy`)
- UI: small inline edit in Production Tracker row (click % cell → input)
- Persisted on `job.actuals[code].pctComplete_manual`
- When set, this value drives `% Complete` everywhere it shows; reference values stay visible as references

### #28 — Leading indicators strip on Overview
**Status:** pending.
New Overview section with 4–6 tiles, each showing direction (↑↓) + caption:
1. **Productivity rate trend (qty/day)** — week-over-week direction. Absolute qty may be off, slope is real signal.
2. **Labor+Equip $/qty vs bid** — clean signal because labor/equip $ are gospel.
3. **Hours burn rate vs scheduled hours** — labor hours are gospel, schedule is set.
4. **Equipment activation lag** — codes scheduled to start with no equip hours posted after N days.
5. **Schedule-vs-actual divergence per task** — using JCS curve.
6. **HJ↔Spectrum convergence tracker** — shows when Spectrum catches up to HJ for each code.

### #29 — HJ data quality flags + cleanup queue
**Status:** pending.
Detect HJ data quality issues as leading indicators of bad data:
- **`$0 material likely missed`** — code ≥80% complete by qty AND actual mat$ < 10% of bid mat$
- **Foreman miscoding** — labor on $0-budget codes
- **Daily Detail anomalies** — qty>0 but $0, hours>14/day per foreman, equip hrs without labor hrs
- **HJ qty wildly diverging from billed qty**

Queue UI: per-job table, assignable, status (open/in HJ/fixed), notes, fixed-date stamp. Becomes the HJ cleanup project's to-do list. Direct loop into improving HJ — foremen get specific feedback ("you coded 8 hrs of dozer time to mob/demob this week — cost code probably wrong").

### #30 — Closeout reconciliation report (month-end view)
**Status:** pending.
Separate tab. Per-job report showing trusted-source actual:
- HJ Labor + HJ Equipment + Spectrum Material + Spectrum Subcontract = realistic actual
- Compare to billings = real margin to date
- Per-code breakdown with variance to bid
- Exportable to PDF/xlsx for leadership
- Lives alongside (not replacing) the operational live view
- Format matches what the team produces manually today — automating a manual process

### #31 — Pay-app forecast / draft generator
**Status:** pending.
Computes next pay-app draft per job:
- qty installed × bid unit price = projected billed amount
- Compare to last signed pay app
- Output: per-pay-item table showing prior amount, current period qty, current amount, %-of-contract
- Export to xlsx for re-entry into the prime GC's pay-app tool (Procore / ProjectSight / etc.)
- **NOT a replacement** for the prime's tool — a draft/forecast the PM reviews before submitting
- Catches under-billing as a leading revenue indicator

### #32 — Configurable 30-day blend cutover per job
**Status:** pending.
Job-level setting: blend cutover N days (default 30).
- HJ data <N days = LIVE (uncleaned)
- Spectrum trumps ≥N days
- Rationale: small jobs / material-only jobs may have faster Spectrum posting (15d)
- Stored on `job.meta.blendCutoverDays`
- Editable in Edit Job modal
- `blendedActualsByCode` already accepts asOf; needs to accept cutover days

### #23 — Daily Log feature (diaries + photos + docs)
**Status:** pending. Endpoints already validated working.

HCSS API exposes per-job per-day foreman notes, photos with GPS, and PDFs (auto-gen safety reports).

Build:
1. **Edge Function sync handlers:**
   - `POST /diaries/search` for foreman notes
   - `POST /attachment/advancedRequest` with `attachmentType: "diary"`, `fileType: "photos" | "pdf" | "all"`
2. **New Supabase tables:**
   - `hcss_diaries` (job_number, date, foreman_id, foreman_name, note, tags[], revision, last_changed_at, last_changed_by)
   - `hcss_attachments` (attachment_id, job_number, attachment_type, file_type, mime, name, attachment_url, thumbnail_url, latitude, longitude, reference_date, last_modified, employee_code)
3. **Front-end Daily Log timeline view** per job: date / foreman / note / photo gallery / docs
4. **Photo map view** — plot every photo on a satellite map per job, filterable by date or foreman. Lat/lng comes free from the API. **The killer feature.**

NOT available from API: weather. Only the captured fields are id/job/foreman/note/tags/date/revision/lastChangedBy.

## Lower priority — pull when ready

### #11 — Production Tracker dual-budget mismatch flag
Slim version: just a "HJ budget out of date" flag, not full dual display. Helps spot when HJ users adjust budgets out of sync from HeavyBid. Useful for unit price jobs where field qtys exceeded the bid.

### #5 — Activity → phase code mapping UI in Set Up
Many cost codes are unmapped today; cleanup tool would let user manually pair an activity to its correct phase. Particularly relevant for the placeholder `??<uuid>` codes in `hcss_job_costs`.

### #9 — Overview KPI strip with Spectrum month-start + HJ mid-month
Less urgent — most of what this would surface is already in Daily Insights.

### #12 — Burns-side Spectrum sync (don't wait on Nic)
Currently we read from Nic's `burns-finance` Supabase. Future hardening: independent sync into our own table. Only do this if cross-team latency becomes a real bottleneck.

## Operational follow-up (not code)

- **4,852 placeholder codes** in `hcss_job_costs` (`??<uuid>`) — investigate if total $ is material; may need master-cost-codes endpoint scan
- **Wire `syncJobCosts` into the daily 5am cron** — currently only manual trigger via Sync Costs (Live $) button
- **Stone Blvd 334120 underlying data still messy** — fixed in code via HeavyBid fallback, but the HCSS data could use cleanup
- **Closed-job filtering for HCSS sync** — closed jobs consume API quota; consider filtering them out

## Done (recent)

#26 Confidence-tagged source-aware cost merge (Labor/Equip from HJ, Mat/Sub from Spectrum-baseline + HJ-30d window, with pills + tooltips)
#25 Verification Layer 3 — daily scheduled self-test
#24 Daily Insights + Notifications foundation
#21 Pass 2 — Production Tracker reads fresh $ from hcss_job_costs
#20 Improve jobCosts mapping rate (33% → 100%)
#19 Pass 1 — Wire up syncJobCosts Edge Function mode
#22 Test HCSS diary + attachments endpoints
#18 Test new HCSS cost endpoints via Edge Function scanner
#17 Fix + re-upload Steel Driver Summary
#16 Add outlier cap + flag to Production Tracker rollup

Full history in `CLAUDE_LOG.md`.
