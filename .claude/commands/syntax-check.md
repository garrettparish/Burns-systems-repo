---
description: Run the Node syntax check on public/index.html (same as deploy.command's pre-deploy gate)
---

Run the same syntax-check Node script that `deploy.command` runs before pushing. Catches unbalanced braces, typos, partial edits.

```bash
cd ~/Desktop/Burns\ System\ Repo && node -e '
const fs=require("fs");
const html=fs.readFileSync("public/index.html","utf8").replace(/<!--[\s\S]*?-->/g,"");
const scripts=[...html.matchAll(/<script\b(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
let errors=0;
scripts.forEach((m,i)=>{
  try { new Function(m[1]); console.log("  block " + i + ": OK (" + m[1].length + " chars)"); }
  catch (e) {
    errors++;
    const lineMatch = e.stack && e.stack.match(/<anonymous>:(\d+):(\d+)/);
    const loc = lineMatch ? "line " + lineMatch[1] + ":" + lineMatch[2] : "?";
    console.error("  block " + i + ": SYNTAX ERROR (" + loc + ") " + e.message);
  }
});
console.log(errors ? "FAIL: " + errors + " syntax error(s)" : "OK: " + scripts.length + " script block(s) parsed clean");
process.exit(errors ? 1 : 0);
'
```

Report the result. If FAIL, identify the line + show 5 lines of context around the error using `sed -n` so the user can see what to fix.
