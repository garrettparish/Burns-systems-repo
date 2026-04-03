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
- **Netlify site:** [TBD — connect after repo setup]
- **Supabase project:** [TBD]
- **Stack:** [TBD]
- **Status:** Repo created — ready to connect pipeline
- **Key files:** [TBD]

*(Add new project blocks here as we start them)*

---

## Current Focus

- **Active project:** Burns Systems
- **Repo:** https://github.com/garrettparish/Burns-systems-repo
- **Branch:** main
- **Working on:** Connect repo to Netlify + Supabase, push config files
- **Blocked on:** Nothing
- **Priority:** Get the deploy pipeline working end-to-end

---

## Session Log

### 2026-04-03 — Session 1
- **What we did:**
  - Created CLAUDE_LOG.md (this file) for cross-session context
  - Created SETUP_GUIDE.md with step-by-step deploy pipeline instructions
  - Created netlify.toml (build config, security headers, SPA support ready)
  - Created .github/workflows/deploy.yml (CI/CD pipeline, Supabase migration support)
  - Discussed workflow: GitHub → Netlify auto-deploy, GitHub → Supabase
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

---

## Open TODOs

- [ ] Garrett: Finish creating GitHub account
- [ ] Create first GitHub repo
- [ ] Link repo to Netlify (auto-deploy on push to main)
- [ ] Link Supabase project
- [ ] Set environment variables (Supabase URL, anon key, service role key)
- [ ] Copy netlify.toml and .github/ into repo
- [ ] First project kickoff
- [ ] Decide on project naming conventions

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
