# Dev Workflow Setup Guide

## Overview

```
Push code → GitHub → Auto-deploy to Netlify (frontend)
                   → Auto-deploy to Supabase (DB migrations)
```

---

## Step 1: Create GitHub Repo

1. Go to https://github.com/new
2. Name your repo (e.g., `my-app`)
3. Set to **Private** (recommended) or Public
4. Check **"Add a README"**
5. Click **Create repository**
6. Copy the repo URL (e.g., `https://github.com/YOUR_USERNAME/my-app.git`)

**Come back and tell me the repo URL — I'll update the log and configs.**

---

## Step 2: Connect Netlify to GitHub

1. Go to https://app.netlify.com
2. Click **"Add new site" → "Import an existing project"**
3. Select **GitHub** as your Git provider
4. Authorize Netlify to access your GitHub account
5. Select your repo
6. Configure build settings:
   - **Build command:** (leave blank for static, or `npm run build` for frameworks)
   - **Publish directory:** `public/` (or `dist/` or `build/` depending on framework)
7. Click **Deploy site**

Once connected, every push to `main` will auto-deploy to Netlify.

---

## Step 3: Connect Supabase

1. Go to https://supabase.com/dashboard
2. Open your existing project (or create one)
3. Go to **Settings → API** and copy:
   - `Project URL`
   - `anon/public` key
   - `service_role` key (keep this secret!)
4. Add these as **environment variables** in Netlify:
   - Go to Netlify → Site settings → Environment variables
   - Add:
     - `SUPABASE_URL` = your project URL
     - `SUPABASE_ANON_KEY` = your anon key
     - `SUPABASE_SERVICE_ROLE_KEY` = your service role key

---

## Step 4: Local Setup (One-time)

Run these commands in your terminal:

```bash
# Clone your repo
git clone https://github.com/garrettparish/my-app.git
cd my-app

# Copy the config files into the repo
# (netlify.toml and .github/workflows/deploy.yml are already prepped)

# Install Supabase CLI (optional, for DB migrations)
npm install -g supabase

# Link to your Supabase project
supabase login
supabase link --project-ref YOUR_PROJECT_REF
```

---

## Step 5: Daily Workflow

```bash
# Make changes
git add .
git commit -m "describe your changes"
git push origin main
# → Netlify auto-deploys
# → GitHub Actions runs checks
```

---

## Environment Variables Checklist

| Variable | Where to set | Source |
|----------|-------------|--------|
| `SUPABASE_URL` | Netlify env vars | Supabase dashboard → Settings → API |
| `SUPABASE_ANON_KEY` | Netlify env vars | Supabase dashboard → Settings → API |
| `SUPABASE_SERVICE_ROLE_KEY` | Netlify env vars | Supabase dashboard → Settings → API |

---

## Useful Links

- GitHub repo: *(update after creation)*
- Netlify dashboard: https://app.netlify.com
- Supabase dashboard: https://supabase.com/dashboard
- Netlify deploy logs: *(available after first deploy)*
