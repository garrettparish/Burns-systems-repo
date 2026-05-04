---
name: burns-systems
description: Burns Dirt project controls app — single-file vanilla JS HTML app at public/index.html, Supabase Edge Functions for HCSS sync, deploy via deploy.command. Use when working on this repo.
---

# Burns Systems

Single-file vanilla JS project controls app for Burns Dirt Construction.

## On startup

1. Read `CLAUDE.md` at the repo root — comprehensive orientation, conventions, gotchas, current focus.
2. Read `TODO.md` — open task list in priority order. Default to task #27 (Manual % complete) unless user directs otherwise.
3. Skim `CLAUDE_LOG.md` for the last 1–2 session entries — gives context on what just shipped.

## Slash commands available

- `/syntax-check` — run the Node syntax-check on `public/index.html` (same one `deploy.command` runs before push)
- `/selftest` — open the live site with `?selftest=1` and report pass/fail counts
- `/deploy` — front-end deploy (with confirmation prompt — Garrett's rule)
- `/deploy-edge` — Supabase Edge Function deploy (with confirmation prompt)

## Critical rules (don't trip these)

1. **Never deploy without explicit confirmation in chat.** Auto-commit between deploys is fine; auto-push is not.
2. **`job.actuals` is an array, not an object map.** Always use `Array.isArray()` + `for-of`. Mutation as a keyed object corrupted Steel Driver's data once already.
3. **30-day blend rule is HARD.** ≥30d ago = Spectrum is gospel. <30d = HJ-only, marked LIVE. Don't switch to greater-of.
4. **JCS variance > budget variance** for in-progress jobs. Cost variance = `JCS planned-to-date − actual`, NOT `budget − actual`.
5. **Every deploy must update `CLAUDE_LOG.md`** in the same push (Session Log entry + Recently Shipped + bump "as of" date).

## Stack at a glance

- **Front-end:** `public/index.html`, ~12k lines, one inline `<script>`. Deployed via `deploy.command` (git push → Netlify auto-build).
- **Edge Function:** `supabase/functions/hcss-sync-actuals/index.ts`, Deno runtime. Deployed via `supabase functions deploy hcss-sync-actuals --no-verify-jwt`.
- **DB:** Supabase (project `sxzvlazmkxnbsoayhuln`). HCSS data in `hcss_jobs`, `hcss_cost_codes`, `actuals_detail_sync`, `hcss_job_costs`. Read Spectrum from Nic's `burns-finance` Supabase via `sbSpectrum` client.
- **Verification:** in-app self-test (`?selftest=1`), pre-deploy gate, daily 6:07am scheduled task (currently in Cowork).
