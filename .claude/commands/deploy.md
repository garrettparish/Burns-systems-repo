---
description: Deploy front-end changes to Netlify via deploy.command (with confirmation prompt)
---

You are about to ship Burns Systems front-end changes to production at `bdcprojectcontrols.netlify.app`. **Confirm with the user before running anything.**

## Procedure

1. **Show the user what's about to ship.** Run:
   - `git status --short` — list modified/added files
   - `git diff --stat` — show line counts changed
   - If `public/index.html` is in the diff, also run a local syntax check first:
     ```bash
     node -e '
       const fs=require("fs");
       const html=fs.readFileSync("public/index.html","utf8").replace(/<!--[\s\S]*?-->/g,"");
       const scripts=[...html.matchAll(/<script\b(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
       let errors=0;
       scripts.forEach((m,i)=>{ try{new Function(m[1])}catch(e){errors++;console.error("block",i,":",e.message)} });
       process.exit(errors?1:0);
     '
     ```
     If it fails, abort and show the user the error — do not proceed.

2. **Confirm CLAUDE_LOG.md is updated** with a new Session Log entry covering the changes about to ship. If it isn't, update it first (per the rule in `CLAUDE.md` §1: "deploy.command press = update CLAUDE_LOG.md in the same push").

3. **Ask the user explicitly:** "Ready to deploy these changes? I'll run `deploy.command` which will commit + push to GitHub → Netlify auto-builds in ~30s. Reply 'yes' or 'go' to proceed."

4. **Only after the user confirms,** run from the repo root:
   ```bash
   cd ~/Desktop/Burns\ System\ Repo && ./deploy.command
   ```

5. **After the push succeeds,** wait ~30 seconds then verify the live site:
   - Navigate to `https://bdcprojectcontrols.netlify.app/?selftest=1`
   - Read `localStorage.bdc_selftest_last` to confirm the new code loaded
   - Report passed/failed counts to the user

## Do not

- Run `deploy.command` without explicit confirmation in this turn.
- Skip the syntax check.
- Skip the CLAUDE_LOG.md update.
- Push directly via `git push` to bypass `deploy.command`'s syntax gate.
