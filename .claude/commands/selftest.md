---
description: Run the in-app self-test against the live site and report results
---

Verify Burns Systems is healthy.

## Procedure

1. Open `https://bdcprojectcontrols.netlify.app/?selftest=1` in the browser (Claude in Chrome MCP, or instruct the user to open it manually if no Chrome automation available).

2. Wait ~10 seconds for jobs to load and the self-test banner to appear.

3. Read the result from `localStorage.bdc_selftest_last` via `mcp__Claude_in_Chrome__javascript_tool`:
   ```js
   JSON.parse(localStorage.getItem('bdc_selftest_last') || 'null')
   ```

4. Report `passed`, `failed`, and any failures in a tight summary. For failures, include the test label and message.

5. If failures look like data issues (negative budgets, missing $, etc.), suggest investigating in the actual data. If failures look like code regressions (missing helpers, throws), they're more urgent and likely a recent deploy.
