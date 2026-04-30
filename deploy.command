#!/bin/bash
# Burns Systems — One-Click Deploy
# Double-click this file to push changes to GitHub → Netlify auto-deploys

# Get the directory where this script lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

cd "$REPO_DIR" || { echo "❌ Can't find repo at $REPO_DIR"; echo "Press any key to close..."; read -n 1; exit 1; }

echo "🚀 Burns Systems — Deploy"
echo "========================="
echo ""

# ─────────────────────────────────────────────────────────────────
# PRE-DEPLOY GATE — fail the push if public/index.html is broken.
# Cheapest validation layer: parse the embedded JS for syntax errors.
# Catches unbalanced braces, typos, partial edits — anything that
# would otherwise ship a blank page to Netlify and 404 everyone.
# ─────────────────────────────────────────────────────────────────
INDEX_FILE="$REPO_DIR/public/index.html"
if [ -f "$INDEX_FILE" ]; then
    echo "🔎 Pre-deploy syntax check on public/index.html..."
    if command -v node >/dev/null 2>&1; then
        # Extract every <script> block (no src attr) and try to parse it as JS.
        # Uses Function() constructor — catches every syntax error V8 catches.
        SYNTAX_RESULT=$(node -e '
          const fs = require("fs");
          const html = fs.readFileSync("'"$INDEX_FILE"'", "utf8");
          // Strip HTML comments before splitting so commented-out <script> tags
          // do not confuse the regex.
          const stripped = html.replace(/<!--[\s\S]*?-->/g, "");
          const scripts = [...stripped.matchAll(/<script\b(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
          if (scripts.length === 0) { console.log("OK: no inline scripts"); process.exit(0); }
          let errors = 0;
          scripts.forEach((m, i) => {
            const code = m[1];
            try {
              new Function(code);
            } catch (e) {
              errors++;
              const lineMatch = e.stack && e.stack.match(/<anonymous>:(\d+):(\d+)/);
              const loc = lineMatch ? "block " + i + " line " + lineMatch[1] + ":" + lineMatch[2] : "block " + i;
              console.error("SYNTAX ERROR (" + loc + "): " + e.message);
            }
          });
          if (errors > 0) {
            console.error("FAIL: " + errors + " syntax error(s) — aborting deploy");
            process.exit(1);
          }
          console.log("OK: " + scripts.length + " script block(s) parsed clean");
        ' 2>&1)
        SYNTAX_EXIT=$?
        echo "$SYNTAX_RESULT"
        if [ $SYNTAX_EXIT -ne 0 ]; then
            echo ""
            echo "❌ Aborting deploy — fix the syntax error above and try again."
            echo "   (If this is a false positive, run with SKIP_SYNTAX_CHECK=1 to bypass.)"
            if [ "$SKIP_SYNTAX_CHECK" != "1" ]; then
                echo ""
                echo "Press any key to close..."
                read -n 1
                exit 1
            fi
            echo "⚠️  SKIP_SYNTAX_CHECK=1 set — proceeding despite syntax errors."
        fi
    else
        echo "⚠️  Node not found — skipping syntax check (install Node to enable)."
    fi
    echo ""
fi

# Clean up any stale git lock files (from crashed processes or interrupted operations)
for LOCK in .git/index.lock .git/HEAD.lock .git/config.lock; do
    if [ -f "$LOCK" ]; then
        # Only remove if older than 60 seconds (avoid clobbering an active git process)
        if [ -z "$(find "$LOCK" -newermt '60 seconds ago' 2>/dev/null)" ]; then
            echo "🧹 Removing stale lock: $LOCK"
            rm -f "$LOCK"
        else
            echo "⚠️  Lock $LOCK is recent — another git process may be running. Aborting."
            echo "   Wait a moment and try again, or run 'rm $LOCK' manually if you're sure."
            echo ""
            echo "Press any key to close..."
            read -n 1
            exit 1
        fi
    fi
done

# Show what's changed
echo "📋 Changes detected:"
git status --short
echo ""

# Check for unpushed commits
UNPUSHED=$(git log origin/main..HEAD --oneline 2>/dev/null)

# Check if there are changes to commit
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    if [ -z "$UNPUSHED" ]; then
        echo "✅ Nothing new to deploy — you're up to date!"
        echo ""
        echo "Press any key to close..."
        read -n 1
        exit 0
    else
        echo "📦 No new changes, but found unpushed commits:"
        echo "$UNPUSHED"
        echo ""
    fi
else
    # Stage all changes
    git add -A

    # Commit with timestamp
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
    git commit -m "Deploy: $TIMESTAMP"
fi

# Push to GitHub (triggers Netlify auto-deploy)
echo ""
echo "📤 Pushing to GitHub..."
git push origin main

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Deployed! Netlify will build your site in ~30 seconds."
    echo "🌐 Check: https://bdcprojectcontrols.netlify.app"
else
    echo ""
    echo "❌ Push failed — check your internet connection or GitHub auth."
fi

echo ""
echo "Press any key to close..."
read -n 1
