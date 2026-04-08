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
    echo "🌐 Check: https://burns-systems.netlify.app"
else
    echo ""
    echo "❌ Push failed — check your internet connection or GitHub auth."
fi

echo ""
echo "Press any key to close..."
read -n 1
