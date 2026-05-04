---
description: Deploy the Supabase Edge Function (hcss-sync-actuals) — with confirmation
---

You are about to deploy the Supabase Edge Function. **Confirm with the user before running.**

## Procedure

1. Show what changed in `supabase/functions/hcss-sync-actuals/index.ts`:
   - `git diff --stat supabase/functions/hcss-sync-actuals/index.ts`
   - Brief summary of what the change does

2. Ask: "Ready to deploy the Edge Function? I'll run `supabase functions deploy hcss-sync-actuals --no-verify-jwt`. Reply 'yes' or 'go' to proceed."

3. Only after confirmation:
   ```bash
   cd ~/Desktop/Burns\ System\ Repo && supabase functions deploy hcss-sync-actuals --no-verify-jwt
   ```

4. After successful deploy, ask the user if they want to test it. Common smoke tests:
   - `{"scanEndpoints": true}` — endpoint health scan
   - `{"syncJobCosts": true, "jobNumber": "775"}` — single-job test sync
   - `{"discover": true}` — list business units
