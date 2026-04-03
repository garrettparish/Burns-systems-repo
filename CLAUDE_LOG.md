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
- **Collaborator:** Nic (suggested the GitHub + auto-deploy workflow)

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

### Project 1: Burns Systems
- **Repo:** https://github.com/garrettparish/Burns-systems-repo
- **Netlify site:** https://bdcprojectcontrols.netlify.app
- **Supabase project:** burns-project-controls (org: nic@burnsdirt.com)
- **Supabase URL:** https://sxzvlazmkxnbsoayhuln.supabase.co
- **Supabase ref:** sxzvlazmkxnbsoayhuln
- **DB table:** `jobs` (id TEXT PK, data JSONB, created_at, updated_at)
- **Stack:** Vanilla HTML/CSS/JS + SheetJS (xlsx.js) + Supabase (persistence)
- **Status:** Phase 1A complete — Import, Dashboard, Bid Items, Schedule, Global View, Mapping
- **Key files:** public/index.html (main app), netlify.toml, deploy.command, .github/workflows/deploy.yml

*(Add new project blocks here as we start them)*

---

## Current Focus

- **Active project:** Burns Systems — Project Controls App
- **Repo:** https://github.com/garrettparish/Burns-systems-repo
- **Branch:** main
- **Working on:** Phase 1A — Import & Dashboard (complete, ready to deploy)
- **Blocked on:** Nothing — app is in public/index.html, push to deploy
- **Priority:** Test all 3 jobs through import flow, then start Phase 2 (Supabase persistence, schedule→bid item mapping refinement)

---

## Session Log

### 2026-04-03 — Session 1
- **What we did:**
  - Created CLAUDE_LOG.md (this file) for cross-session context
  - Created SETUP_GUIDE.md with step-by-step deploy pipeline instructions
  - Created netlify.toml (build config, security headers, SPA support ready)
  - Created .github/workflows/deploy.yml (CI/CD pipeline, Supabase migration support)
  - Created deploy.command (one-click deploy button for Mac Desktop)
  - Set up GitHub account (garrettparish) and Burns-systems-repo
  - Connected repo to Netlify (project: bdcprojectcontrols, URL: bdcprojectcontrols.netlify.app)
  - Set up Git with Personal Access Token + osxkeychain credential helper
  - Verified deploy button works — full pipeline is live
  - Local repo lives at: ~/Desktop/Burns System Repo/
- **Decisions made:**
  - Multi-project setup (not monorepo) — each project gets its own repo
  - Push-to-main = production deploy (simple, standard)
  - CLAUDE_LOG.md lives in desktop workspace for persistence
  - GitHub Actions for CI (free tier, native integration)
  - Nic's suggestion: GitHub terminal with auto-deploy + Claude context log
- **Garrett's current state:**
  - Creating GitHub account right now
  - Already has Netlify and Supabase accounts
  - Working on multiple projects (not just one)
- **Open questions:**
  - What's the first project we're building?
  - GitHub username (need to update this log)
  - Supabase project name/ref
  - Netlify team/site name
- **Next steps:**
  - Garrett: finish GitHub setup, share username + repo URL
  - Connect repo to Netlify
  - Connect Supabase project
  - Set env vars (Supabase keys in Netlify)
  - First project kickoff

### 2026-04-03 — Session 2 (Cowork — multi-session)
- **What we did:**
  - Built complete Phase 1A project controls app (single-file HTML/CSS/JS, 837 lines, 67KB)
  - **Import system:** HeavyBid Activities parser, HeavyBid Bid Items parser, Smartsheet Schedule parser
  - **Import → Review → Confirm workflow** with inline edit/delete/add, checkboxes for row selection
  - **Schedule → Bid Item Mapping step:** auto-suggest via keyword matching + discipline inference, manual override dropdowns grouped by discipline, progress bar, confirm flow
  - **Job Dashboard:** KPI row (Contract, Direct, Overhead, Profit, Man Hours, Items, Duration), horizontal cost breakdown bars, discipline summary table, bid items table sorted by contract value, Gantt chart
  - **Global View:** multi-job timeline with discipline bars using real schedule dates (from taskMap or keyword fallback), job summary table
  - **Bid Items tab:** primary operational view with discipline filter chips, search, drill-down to child activities, variance detection
  - **Schedule tab:** Gantt chart + task list with edit capability
  - **Cost layer structure finalized:** Direct Cost + Overhead (Indirects + Addon/Bond) + Profit (Markup) = Contract (Takeoff Total)
  - **Contract auto-calculated** from bid items — no manual entry, removed from job creation modal
  - Moved app from Cowork outputs into `public/index.html` in the Burns System Repo
  - **Tested with 3 jobs:** SteelDriver 775 (15 bid items, 61 activities, 41 tasks), SteelPro 772 (19 bid items, 54 activities, 58 tasks), Stone Blvd 765 (103 bid items, 116 activities, 64 tasks)
  - Burns Dirt branding: Green #3E4D3E, Midnight #363636, Sand #B9AB99, Orange #F26722, Oswald + Source Serif 4 fonts
- **Decisions made:**
  - Bid items are the primary operational unit (not activities) — activities are audit/drill-down only
  - Data hierarchy: Activities → Bid Items → Phase Codes → Pay Items
  - Discipline derived from dominant activity code range (10000=General, 20000=Erosion, etc.)
  - Overhead = Indirects + Addon/Bond (combined), Profit = Markup, Contract = Takeoff Total
  - Schedule→Bid Item mapping happens as a setup step after import, not embedded in the views
  - Single-file HTML for Phase 1A; will split into src/ modules when adding Supabase
- **Key architecture:**
  - `Store = { jobs:{}, activeJob:null, crews:{}, staging:{} }` — all state in memory
  - Each job: `{ meta, activities[], bidItems[], schedule[], taskMap:{} }`
  - taskMap: `{ taskIndex: bidItemId }` — links schedule tasks to bid items
  - SheetJS (xlsx.js) for in-browser Excel parsing
  - All views re-render from Store on data changes
- **Files changed:**
  - `public/index.html` — complete Phase 1A app (replaced placeholder)
  - `CLAUDE_LOG.md` — updated with session context
- **Next steps:**
  - Push to main to deploy to bdcprojectcontrols.netlify.app
  - Test all 3 jobs end-to-end in deployed version
  - Connect Supabase for persistence (save/load jobs across sessions)
  - Phase 2 features: production tracking, percent complete, WIP reporting

---

## Open TODOs

- [x] Garrett: Finish creating GitHub account
- [x] Create first GitHub repo
- [x] Link repo to Netlify (auto-deploy on push to main)
- [x] Copy netlify.toml and .github/ into repo
- [x] First project kickoff — Phase 1A app built
- [ ] Push Phase 1A to main → deploy to bdcprojectcontrols.netlify.app
- [ ] Test all 3 jobs: SteelDriver 775, SteelPro 772, Stone Blvd 765
- [x] Link Supabase project for data persistence
- [x] Supabase client wired into app (auto-save on import/edit, auto-load on startup)
- [ ] Phase 2: Supabase integration (save/load jobs, auth)
- [ ] Phase 2: Refine schedule→bid item mapping with saved state
- [ ] Future: Phase Codes, Pay Items, billing module, WIP reporting

---

## Decisions & Rationale

| Decision | Rationale | Date |
|----------|-----------|------|
| Multi-project (separate repos) | Garrett working on multiple projects, cleaner separation | 2026-04-03 |
| CLAUDE_LOG.md on desktop | Persists across sessions, accessible to Claude always | 2026-04-03 |
| Push-to-main = production deploy | Simple, standard CI/CD — no complex branching needed yet | 2026-04-03 |
| GitHub Actions for CI | Free tier, native GitHub integration, easy to extend | 2026-04-03 |
| Netlify for frontend hosting | Already has account, great DX, auto-deploy built in | 2026-04-03 |
| Supabase for backend | Already has account, Postgres + auth + storage in one | 2026-04-03 |
| Bid items as primary unit | Activities are audit-only; bid items drive all views and tracking | 2026-04-03 |
| Overhead = Indirects + Addon/Bond | Combined into single bucket; Profit = Markup; Contract = Takeoff Total | 2026-04-03 |
| Schedule→Bid Item mapping as setup step | Post-import mapping step, not inferred at render time | 2026-04-03 |
| Single-file HTML for Phase 1A | Simple deploy, split into modules when adding Supabase | 2026-04-03 |

---

## Tech Preferences & Patterns

- **Default frontend:** HTML/CSS/JS (vanilla) unless otherwise specified
- **Preferred style:** Lightweight, clean, user-friendly
- **Approach:** Modular and easy to adjust (iterative workflow)
- **Garrett's role:** Product designer + builder
- **Claude's role:** Expert dev partner — proactive suggestions, challenge decisions

---

## Repo Template (for new projects)

```
project-name/
├── CLAUDE_LOG.md          ← symlink or copy of this file
├── netlify.toml           ← Netlify build config
├── .github/
│   └── workflows/
│       └── deploy.yml     ← CI/CD pipeline
├── public/                ← static assets + index.html
│   └── index.html
├── src/                   ← application source
│   ├── app.js
│   └── style.css
├── supabase/
│   └── migrations/        ← DB schema changes
├── package.json
└── .gitignore
```

---

## Useful Commands

```bash
# Clone a repo
git clone https://github.com/garrettparish/project-name.git

# Standard workflow
git add .
git commit -m "describe changes"
git push origin main          # triggers Netlify auto-deploy

# Supabase CLI
supabase login
supabase link --project-ref YOUR_REF
supabase db push              # push migrations
supabase db diff              # see pending changes

# Netlify CLI (optional)
netlify login
netlify link
netlify deploy --prod         # manual deploy
netlify open                  # open site in browser
```

---

## Notes for Claude

- **ALWAYS read this file first** when starting a new session
- **ALWAYS update the Session Log** before ending a session
- Keep "Current Focus" accurate — this is the quick-glance section
- When starting a new project, add it to the Projects section
- Track all decisions in the Decisions table with rationale
- If Garrett mentions Nic, he's a collaborator — note any of his suggestions
- Garrett prefers direct, practical communication — skip fluff
- Proactively suggest improvements, don't wait to be asked
- When multiple projects exist, always confirm which one we're working on
