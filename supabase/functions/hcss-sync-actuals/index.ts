// ============================================================
// HCSS Sync — Phase 1 (HeavyJob daily actuals)
// Burns Project Controls
// ============================================================
// Supabase Edge Function (Deno runtime).
//
// Responsibilities:
//   1. Mint an OAuth2 client-credentials token from HCSS.
//   2. Discover the Burns business unit (or use HCSS_BUSINESS_UNIT_CODE).
//   3. List active jobs in that BU.
//   4. For each job, pull time cards + quantities for the last N days
//      (default 14, env: HCSS_LOOKBACK_DAYS).
//   5. Merge time cards + quantities by (job, date, costCode, foreman).
//   6. Upsert into public.actuals_detail_sync.
//   7. Write an audit row to public.sync_log.
//
// Triggers:
//   - pg_cron daily at 10:00 UTC (see migration)
//   - Manual: POST {"trigger":"manual"} from the front-end
//   - Discovery: POST {"discover":true} returns BU + job list WITHOUT
//     writing anything (use this to find your businessUnitCode).
//
// ============================================================
// ENV (set via `supabase secrets set`):
//   HCSS_CLIENT_ID           (required)
//   HCSS_CLIENT_SECRET       (required)
//   HCSS_BUSINESS_UNIT_CODE  (optional — if missing, we list BUs and abort)
//   HCSS_LOOKBACK_DAYS       (optional, default 14)
//   HCSS_API_BASE            (optional, default https://api.hcssapps.com)
//   HCSS_TOKEN_URL           (optional, default <base>/identity/connect/token)
//   HCSS_SCOPES              (optional, default 'heavyjob:read setups:read')
//   SUPABASE_URL             (injected automatically by Supabase)
//   SUPABASE_SERVICE_ROLE_KEY (injected automatically)
// ============================================================
//
// IMPORTANT — ENDPOINT PATHS:
// HCSS publishes its exact endpoint paths on developer.hcssapps.com
// behind auth-gated docs we can't fetch from here. The paths below
// are based on the public product overview + redoc schema naming and
// are STRONGLY SUSPECTED to be correct, but the first run in discovery
// mode will prove them. If a path 404s, change the constant and redeploy.
// Every path is defined once at the top so there's a single source of truth.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// -------------------- CONFIG --------------------
const HCSS_API_BASE    = Deno.env.get('HCSS_API_BASE')    || 'https://api.hcssapps.com';
const HCSS_TOKEN_URL   = Deno.env.get('HCSS_TOKEN_URL')   || `${HCSS_API_BASE}/identity/connect/token`;
const HCSS_SCOPES      = Deno.env.get('HCSS_SCOPES')      || 'heavyjob:read e360:read e360:timecards:read setups:read setups:write timecards:read';
const LOOKBACK_DAYS    = parseInt(Deno.env.get('HCSS_LOOKBACK_DAYS') || '14', 10);

// Endpoint paths — ALL under heavyjob product (confirmed via endpoint scan 2026-04-14).
// businessUnits returned 200 from heavyjob; setups returned 403, e360 returned 404.
// FIXED 2026-04-16: HCSS developer docs confirm the correct endpoint is /timeCardInfo
// (not /timeCards). All ID params (jobId, foremanId, etc.) must be HCSS UUIDs.
// Pagination is cursor-based (cursor + limit), NOT skip-based.
const EP = {
  businessUnits: `${HCSS_API_BASE}/heavyjob/api/v1/businessUnits`,
  jobs:          (buId: string) => `${HCSS_API_BASE}/heavyjob/api/v1/jobs?businessUnitId=${encodeURIComponent(buId)}`,
  timeCards:     (_buId: string, jobId: string) => `${HCSS_API_BASE}/heavyjob/api/v1/timeCardInfo?jobId=${encodeURIComponent(jobId)}`,
  // Quantities endpoint: costCodeTransactionInfo returned 404 in scan.
  // Trying costTypeQuantity as fallback. If both fail, sync runs timecard-only.
  quantities:    (_buId: string, jobId: string) => `${HCSS_API_BASE}/heavyjob/api/v1/costTypeQuantity?jobId=${encodeURIComponent(jobId)}`,
};

// -------------------- SHARED HELPERS --------------------
// Numeric coercion with NaN → 0 fallback. Used throughout merge + extraction.
const num = (v: any) => {
  const n = Number(v);
  return isFinite(n) ? n : 0;
};

// -------------------- TYPES --------------------
interface TokenResponse { access_token: string; token_type: string; expires_in: number; scope?: string }

// Module-level cache of the last minted token's granted scope string,
// so discovery mode can surface it to the caller for debugging.
let _lastGrantedScope: string | null = null;
interface SyncRequest { trigger?: 'cron'|'manual'|'api'; discover?: boolean; syncMetadata?: boolean; scanEndpoints?: boolean; lookbackDays?: number; jobNumber?: string; fullHistory?: boolean }
interface EquipObservation {
  code: string;
  description: string;
  lastSeenDate: string;  // YYYY-MM-DD
  lastSeenJob: string;   // job code (not UUID)
  timesSeen: number;
  raw?: any;             // a sample raw timecard equipment entry for forward-compat
}
// Per-day equipment assignment row for hcss_equipment_history.
// Keyed by (hcss_code, date, job_code) — mirrors Store.crewHistory.
interface EquipHistoryRow {
  hcss_code: string;
  date: string;        // YYYY-MM-DD
  job_code: string;
  hours: number;       // total hours on that machine for that day on that job
}
interface DetailRow {
  job_number: string; date: string; cost_code: string; foreman: string;
  cost_code_desc: string; unit: string;
  actual_qty: number;
  actual_labor_hours: number; actual_equip_hours: number;
  actual_labor_cost: number; actual_equip_cost: number;
  actual_mat_cost: number; actual_sub_cost: number;
  expected_labor_hours: number; expected_labor_cost: number;
  expected_equip_cost: number; expected_mat_cost: number; expected_sub_cost: number;
  source: string;
}

// -------------------- CORS --------------------
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, x-client-info, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// -------------------- MAIN HANDLER --------------------
Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  const startedAt = Date.now();
  let body: SyncRequest = {};
  try { body = await req.json(); } catch { /* empty body = cron */ }
  const trigger = body.trigger || 'cron';
  // Full-history mode: omit startDate so HCSS returns everything for each job.
  // Use this once on initial deployment to backfill; the daily cron stays at LOOKBACK_DAYS.
  const fullHistory = body.fullHistory === true;
  const lookback = fullHistory ? null : (body.lookbackDays || LOOKBACK_DAYS);
  const supa = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const logRun = async (status: string, extras: Record<string, unknown> = {}) =>
    await supa.from('sync_log').insert({
      kind: body.discover ? 'discover' : 'actuals',
      status,
      trigger,
      duration_ms: Date.now() - startedAt,
      ...extras,
    });

  try {
    const clientId     = Deno.env.get('HCSS_CLIENT_ID');
    const clientSecret = Deno.env.get('HCSS_CLIENT_SECRET');
    if (!clientId || !clientSecret) throw new Error('HCSS_CLIENT_ID / HCSS_CLIENT_SECRET are not set in Supabase secrets');

    // 1. Token mint
    const token = await mintToken(clientId, clientSecret);

    // 2. Business unit — env override or discover.
    const buEnv = Deno.env.get('HCSS_BUSINESS_UNIT_CODE');
    const bus = await listBusinessUnits(token);

    if (body.discover || !buEnv) {
      // Discovery mode: return the list without writing actuals.
      await logRun('success', {
        details: { mode: 'discover', businessUnits: bus, lookbackDays: lookback },
      });
      return json({
        ok: true,
        mode: 'discover',
        businessUnits: bus,
        message: buEnv
          ? `Discovery requested. Env has HCSS_BUSINESS_UNIT_CODE=${buEnv}`
          : 'HCSS_BUSINESS_UNIT_CODE is not set. Pick a code from businessUnits[] and set it via: supabase secrets set HCSS_BUSINESS_UNIT_CODE=<code>',
      });
    }

    // Endpoint scan mode — try multiple paths for timecard/quantity endpoints
    if (body.scanEndpoints) {
      const matchedBU = bus.find(b => b.code === buEnv || b.id === buEnv);
      const buId = matchedBU?.id || buEnv;
      // Get jobs and pick a real one (skip job code "0" or empty)
      const testJobs = await listJobs(token, buId);
      const realJob = testJobs.find(j => j.jobCode && j.jobCode !== '0') || testJobs[0];
      const testJobId = realJob?.id || '';
      const testJobCode = realJob?.jobCode || '';

      // Also get first 10 job samples for debugging
      const jobSamples = testJobs.slice(0, 10).map(j => ({ code: j.jobCode, id: (j.id || '').substring(0, 8), name: j.name, status: j.status }));

      const TC_CANDIDATES = [
        // ── Confirmed correct paths from HCSS developer docs (2026-04-16) ──
        // IMPORTANT: jobId must be HCSS UUID, not job code
        { label: 'hj/v1/timeCardInfo (CORRECT)',  url: `${HCSS_API_BASE}/heavyjob/api/v1/timeCardInfo?jobId=${testJobId}&limit=1` },
        { label: 'hj/v1/timeCardApprovalInfo',    url: `${HCSS_API_BASE}/heavyjob/api/v1/timeCardApprovalInfo?jobId=${testJobId}&limit=1` },
        { label: 'hj/v1/costCodeTransactionInfo',  url: `${HCSS_API_BASE}/heavyjob/api/v1/costCodeTransactionInfo?jobId=${testJobId}&limit=1` },
        { label: 'hj/v1/costCodeProgress',         url: `${HCSS_API_BASE}/heavyjob/api/v1/costCodeProgress?jobId=${testJobId}&limit=1` },
        { label: 'hj/v1/costTypeQuantity',         url: `${HCSS_API_BASE}/heavyjob/api/v1/costTypeQuantity?jobId=${testJobId}&limit=1` },
        { label: 'hj/v1/costTransaction',          url: `${HCSS_API_BASE}/heavyjob/api/v1/costTransaction?jobId=${testJobId}&limit=1` },
        { label: 'hj/v1/costInfo',                 url: `${HCSS_API_BASE}/heavyjob/api/v1/costInfo?jobId=${testJobId}&limit=1` },
        { label: 'hj/v1/quantityAdjustment',       url: `${HCSS_API_BASE}/heavyjob/api/v1/quantityAdjustment?jobId=${testJobId}&limit=1` },
        { label: 'hj/v1/payItemTransaction',       url: `${HCSS_API_BASE}/heavyjob/api/v1/payItemTransaction?jobId=${testJobId}&limit=1` },
        // ── Old guesses (all returned 404 — leaving for reference) ──
        { label: 'hj/v1/timeCards (WRONG)',   url: `${HCSS_API_BASE}/heavyjob/api/v1/timeCards?jobId=${testJobId}&limit=1` },
        { label: 'hj/v1/quantities (WRONG)',  url: `${HCSS_API_BASE}/heavyjob/api/v1/quantities?jobId=${testJobId}&limit=1` },
        // ── Other data endpoints ──
        { label: 'hj/v1/costCodes',           url: `${HCSS_API_BASE}/heavyjob/api/v1/costCodes?jobId=${testJobId}` },
        { label: 'hj/v1/employees',           url: `${HCSS_API_BASE}/heavyjob/api/v1/employees?limit=1` },
        { label: 'hj/v1/equipment',           url: `${HCSS_API_BASE}/heavyjob/api/v1/equipment?limit=1` },
        { label: 'hj/v1/foremen',             url: `${HCSS_API_BASE}/heavyjob/api/v1/foremen?jobId=${testJobId}` },
        { label: 'hj/v1/costTypes',           url: `${HCSS_API_BASE}/heavyjob/api/v1/costTypes` },
      ];

      const results: { label: string; status: number; body: string }[] = [];
      for (const c of TC_CANDIDATES) {
        try {
          const resp = await fetch(c.url, {
            headers: { 'Authorization': `Bearer ${token}`, 'Accept': 'application/json' },
          });
          const txt = await resp.text();
          results.push({ label: c.label, status: resp.status, body: txt.substring(0, 2000) });
        } catch (e) {
          results.push({ label: c.label, status: 0, body: String(e) });
        }
      }

      // Phase 2: Try multiple detail URL patterns to find the one with cost code entries
      const tcDetailResults: { url: string; status: number; body: string }[] = [];
      const tcListResult = results.find(r => r.label.includes('timeCardInfo (CORRECT)') && r.status === 200);
      if (tcListResult) {
        try {
          const parsed = JSON.parse(tcListResult.body);
          const firstTc = parsed?.results?.[0];
          if (firstTc?.id) {
            const detailCandidates = [
              `${HCSS_API_BASE}/heavyjob/api/v1/timeCardInfo/${firstTc.id}`,
              `${HCSS_API_BASE}/heavyjob/api/v1/timeCard/${firstTc.id}`,
              `${HCSS_API_BASE}/heavyjob/api/v1/timeCards/${firstTc.id}`,
              `${HCSS_API_BASE}/heavyjob/api/v1/timecards/${firstTc.id}`,
              `${HCSS_API_BASE}/heavyjob/api/v1/timeCard?id=${firstTc.id}`,
            ];
            for (const url of detailCandidates) {
              try {
                const resp = await fetch(url, {
                  headers: { 'Authorization': `Bearer ${token}`, 'Accept': 'application/json' },
                });
                const txt = await resp.text();
                tcDetailResults.push({ url, status: resp.status, body: txt.substring(0, 3000) });
              } catch (e) {
                tcDetailResults.push({ url, status: 0, body: String(e) });
              }
            }
            // Also try POST /timeCardInfo with the TC id in the body
            try {
              const postResp = await fetch(`${HCSS_API_BASE}/heavyjob/api/v1/timeCardInfo`, {
                method: 'POST',
                headers: { 'Authorization': `Bearer ${token}`, 'Accept': 'application/json', 'Content-Type': 'application/json' },
                body: JSON.stringify({ ids: [firstTc.id], jobId: firstTc.jobId }),
              });
              const postTxt = await postResp.text();
              tcDetailResults.push({ url: 'POST /timeCardInfo', status: postResp.status, body: postTxt.substring(0, 3000) });
            } catch (e) {
              tcDetailResults.push({ url: 'POST /timeCardInfo', status: 0, body: String(e) });
            }
          }
        } catch (e) {
          tcDetailResults.push({ url: 'parse-error', status: 0, body: String(e) });
        }
      }

      return json({
        ok: true,
        mode: 'endpoint-scan',
        testJob: { id: testJobId, code: testJobCode },
        totalJobs: testJobs.length,
        jobSamples,
        results,
        tcDetailResults,
      });
    }

    // ── Metadata sync mode: pull jobs + cost codes into reference tables ──
    if (body.syncMetadata) {
      const matchedBU = bus.find(b => b.code === buEnv || b.id === buEnv);
      if (!matchedBU) throw new Error(`BU '${buEnv}' not found`);
      const buId = matchedBU.id || matchedBU.code;

      // 1. Pull all jobs
      const allJobs = await listJobs(token, buId);

      // 2. Upsert jobs into hcss_jobs
      const jobRows = allJobs.map(j => ({
        hcss_id: j.id,
        job_code: j.jobCode,
        job_name: j.name,
        status: j.status,
        start_date: j.startDate || null,
        end_date: j.endDate || null,
        business_unit_id: matchedBU.id,
        business_unit_code: matchedBU.code,
        raw: j._raw || null,
        synced_at: new Date().toISOString(),
      }));

      let jobsUpserted = 0;
      // Batch upsert in chunks of 50
      for (let i = 0; i < jobRows.length; i += 50) {
        const chunk = jobRows.slice(i, i + 50);
        const { error, count } = await supa
          .from('hcss_jobs')
          .upsert(chunk, { onConflict: 'hcss_id', count: 'exact' });
        if (error) throw new Error(`hcss_jobs upsert failed: ${error.message}`);
        jobsUpserted += count || chunk.length;
      }

      // 3. Pull cost codes for active jobs only (to avoid API rate limits)
      const activeJobs = allJobs.filter(j => isJobActive(j));
      let totalCostCodes = 0;
      const ccErrors: { job: string; error: string }[] = [];

      for (const job of activeJobs) {
        try {
          const ccUrl = `${HCSS_API_BASE}/heavyjob/api/v1/costCodes?jobId=${encodeURIComponent(job.id)}`;
          const ccData = await hcssGetPaginated(ccUrl, token);

          if (ccData.length > 0) {
            const ccRows = ccData.map((cc: any) => ({
              hcss_job_id: job.id,
              job_code: job.jobCode,
              cost_code: String(cc.code || '').trim(),
              description: String(cc.description || ''),
              unit: String(cc.unit || cc.unitOfMeasure || ''),
              is_hidden: cc.isHiddenFromMobile || false,
              quantity_driven: cc.quantityDriving || cc.isQuantityDriving || false,
              raw: cc,
              synced_at: new Date().toISOString(),
            })).filter(r => r.cost_code);

            for (let i = 0; i < ccRows.length; i += 50) {
              const chunk = ccRows.slice(i, i + 50);
              const { error } = await supa
                .from('hcss_cost_codes')
                .upsert(chunk, { onConflict: 'hcss_job_id,cost_code' });
              if (error) throw new Error(`hcss_cost_codes upsert: ${error.message}`);
            }
            totalCostCodes += ccRows.length;
          }
        } catch (e) {
          ccErrors.push({ job: job.jobCode, error: String(e.message || e) });
        }
      }

      await logRun('success', {
        details: {
          mode: 'metadata',
          jobsUpserted,
          totalJobs: allJobs.length,
          activeJobs: activeJobs.length,
          costCodesUpserted: totalCostCodes,
          costCodeErrors: ccErrors,
        },
      });

      return json({
        ok: true,
        mode: 'metadata',
        jobsUpserted,
        totalJobs: allJobs.length,
        activeJobs: activeJobs.length,
        costCodesUpserted: totalCostCodes,
        costCodeErrors: ccErrors.length,
        durationMs: Date.now() - startedAt,
      });
    }

    const buCode = buEnv;
    // Match by code OR by id (env can store either)
    const matchedBU = bus.find(b => b.code === buCode || b.id === buCode);
    if (!matchedBU) {
      throw new Error(`HCSS_BUSINESS_UNIT_CODE='${buCode}' not found in this account's BU list. Available: ${bus.map(b=>`${b.code} (id=${b.id})`).join(', ')}`);
    }
    // heavyjob endpoints use UUID businessUnitId
    const buIdentifier = matchedBU.id || matchedBU.code;

    // 3. List jobs
    let jobs = await listJobs(token, buIdentifier);
    if (body.jobNumber) jobs = jobs.filter(j => j.jobCode === body.jobNumber);
    // Active jobs only — skip closed/archived.
    const activeJobs = jobs.filter(j => isJobActive(j));

    // 4. Pull data per job
    // If fullHistory, `since` is null → listTimeCards/listQuantities will omit startDate.
    const since = lookback == null ? null : isoDaysAgo(lookback);
    const rows: DetailRow[] = [];
    const errors: { job: string; error: string }[] = [];
    // Equipment accumulator — keyed by HCSS equipment code. Tracks latest
    // observation across ALL jobs in this run so we can set last_seen correctly.
    const equipAcc = new Map<string, EquipObservation>();
    // Per-day history accumulator — keyed by "code|date|job". Feeds
    // hcss_equipment_history so the Equipment Planner can auto-populate
    // past cells with the job each machine was actually on.
    const equipHistAcc = new Map<string, EquipHistoryRow>();

    for (const job of activeJobs) {
      try {
        // CRITICAL: HCSS API requires UUID jobId, NOT the job code string.
        // job.id is the HCSS UUID from the jobs list response.
        if (!job.id) {
          errors.push({ job: job.jobCode, error: 'Missing HCSS UUID (job.id) — cannot query timecards' });
          continue;
        }
        const [tcs, qs] = await Promise.all([
          listTimeCards(token, buIdentifier, job.id, since),
          listQuantities(token, buIdentifier, job.id, since),
        ]);
        rows.push(...mergeJobRows(job.jobCode, tcs, qs));
        // Equipment extraction piggybacks on the same timecard details we
        // already parsed — essentially free. Populates both roster + history.
        extractEquipmentObservations(job.jobCode, tcs, equipAcc, equipHistAcc);
      } catch (e) {
        errors.push({ job: job.jobCode, error: String(e.message || e) });
      }
    }

    // 5. Upsert actuals
    let inserted = 0, updated = 0;
    if (rows.length) {
      const { error, count } = await supa
        .from('actuals_detail_sync')
        .upsert(rows, { onConflict: 'job_number,date,cost_code,foreman', count: 'exact' });
      if (error) throw new Error(`Upsert failed: ${error.message}`);
      // Supabase returns total affected, not split insert/update. Report in "rows_updated".
      updated = count || rows.length;
    }

    // 6. Upsert equipment observations (HCSS-owned fields only).
    // We omit first_seen_at so the column default (now()) applies on INSERT
    // and ON CONFLICT DO UPDATE leaves it untouched — preserving true first-seen.
    // User-assigned fields (category, notes) live in front-end localStorage
    // and are never touched by this table.
    let equipUpserted = 0;
    if (equipAcc.size > 0) {
      const equipRows = Array.from(equipAcc.values()).map(e => ({
        hcss_code: e.code,
        description: e.description,
        last_seen_job_code: e.lastSeenJob,
        last_seen_date: e.lastSeenDate,
        times_seen: e.timesSeen,
        raw: e.raw || null,
        synced_at: new Date().toISOString(),
      }));
      for (let i = 0; i < equipRows.length; i += 50) {
        const chunk = equipRows.slice(i, i + 50);
        const { error, count } = await supa
          .from('hcss_equipment')
          .upsert(chunk, { onConflict: 'hcss_code', count: 'exact' });
        if (error) {
          // Non-fatal — actuals already saved. Record error and keep going.
          errors.push({ job: '(equipment)', error: `hcss_equipment upsert: ${error.message}` });
          break;
        }
        equipUpserted += count || chunk.length;
      }
    }

    // 7. Upsert equipment day-by-day history.
    // Same approach as (6) but the conflict key is the full (code, date, job)
    // composite. Powers auto-populated past cells in the Equipment Planner.
    let equipHistUpserted = 0;
    if (equipHistAcc.size > 0) {
      const histRows = Array.from(equipHistAcc.values()).map(h => ({
        hcss_code: h.hcss_code,
        date: h.date,
        job_code: h.job_code,
        hours: h.hours,
        synced_at: new Date().toISOString(),
      }));
      for (let i = 0; i < histRows.length; i += 200) {
        const chunk = histRows.slice(i, i + 200);
        const { error, count } = await supa
          .from('hcss_equipment_history')
          .upsert(chunk, { onConflict: 'hcss_code,date,job_code', count: 'exact' });
        if (error) {
          errors.push({ job: '(equipment-history)', error: `hcss_equipment_history upsert: ${error.message}` });
          break;
        }
        equipHistUpserted += count || chunk.length;
      }
    }

    const status = errors.length ? 'partial' : 'success';
    await logRun(status, {
      jobs_synced: activeJobs.length,
      rows_updated: updated,
      rows_inserted: inserted,
      details: {
        mode: fullHistory ? 'backfill' : 'sync',
        businessUnit: buCode,
        lookbackDays: lookback,
        activeJobs: activeJobs.length,
        totalJobs: jobs.length,
        errors,
        topJobsByRows: topCountsByJob(rows),
        equipmentDiscovered: equipAcc.size,
        equipmentUpserted: equipUpserted,
        equipmentHistoryRows: equipHistAcc.size,
        equipmentHistoryUpserted: equipHistUpserted,
      },
    });

    return json({
      ok: true,
      status,
      jobsSynced: activeJobs.length,
      totalJobsFound: jobs.length,
      rowsUpserted: updated,
      equipmentHistoryUpserted: equipHistUpserted,
      equipmentDiscovered: equipAcc.size,
      equipmentUpserted: equipUpserted,
      errors,
      durationMs: Date.now() - startedAt,
      debug: {
        businessUnit: { code: buCode, id: buIdentifier },
        jobsEndpoint: EP.jobs(buIdentifier),
        sampleJobs: jobs.slice(0, 5),
      },
    });
  } catch (err) {
    console.error('HCSS sync failed:', err);
    await logRun('error', { error_message: String(err.message || err), details: { requestedScopes: HCSS_SCOPES, grantedScope: _lastGrantedScope } });
    return json({ ok: false, error: String(err.message || err), requestedScopes: HCSS_SCOPES, grantedScope: _lastGrantedScope }, 500);
  }
});

// -------------------- HCSS CLIENT --------------------
async function mintToken(clientId: string, clientSecret: string): Promise<string> {
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: clientId,
    client_secret: clientSecret,
    scope: HCSS_SCOPES,
  });
  const res = await fetch(HCSS_TOKEN_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'BurnsProjectControls/1.0 (+https://bdcprojectcontrols.netlify.app)',
    },
    body,
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`Token mint failed (${res.status}): ${txt}`);
  }
  const j: TokenResponse = await res.json();
  _lastGrantedScope = j.scope || null;
  return j.access_token;
}

async function hcssGet(url: string, token: string): Promise<any> {
  const res = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Accept': 'application/json',
      'User-Agent': 'BurnsProjectControls/1.0 (+https://bdcprojectcontrols.netlify.app)',
    },
  });
  if (!res.ok) {
    const txt = await res.text();
    const hdrs: string[] = [];
    res.headers.forEach((v, k) => { if (/^(www-authenticate|x-|content-type)/i.test(k)) hdrs.push(`${k}=${v}`); });
    throw new Error(`GET ${url} → ${res.status}: body="${txt.slice(0, 500)}" headers=[${hdrs.join(', ')}]`);
  }
  return await res.json();
}

async function hcssGetPaginated(url: string, token: string): Promise<any[]> {
  // HCSS uses cursor-based pagination (confirmed via developer.hcssapps.com).
  // Response shape: { results/items/data: [...], metadata: { nextCursor: "..." } }
  // Pass cursor as query param to get next page. limit defaults to 1000.
  const out: any[] = [];
  const pageSize = 1000;
  let cursor: string | null = null;
  let pages = 0;
  for (;;) {
    const sep = url.includes('?') ? '&' : '?';
    const pageUrl = cursor
      ? `${url}${sep}limit=${pageSize}&cursor=${encodeURIComponent(cursor)}`
      : `${url}${sep}limit=${pageSize}`;
    const data = await hcssGet(pageUrl, token);
    const items: any[] = Array.isArray(data) ? data
                       : Array.isArray(data?.results) ? data.results
                       : Array.isArray(data?.items) ? data.items
                       : Array.isArray(data?.data)  ? data.data
                       : [];
    out.push(...items);
    // Check for nextCursor in metadata (HCSS cursor pagination)
    const nextCursor = data?.metadata?.nextCursor || data?.nextCursor || null;
    if (!nextCursor || items.length === 0) break;
    cursor = nextCursor;
    pages++;
    if (pages > 100) break; // safety: max ~100k rows
  }
  return out;
}

async function listBusinessUnits(token: string) {
  // BusinessUnit list is small (< dozens), no pagination needed.
  // Calling it raw also sidesteps any 403-on-unknown-query-param behavior.
  const raw = await hcssGet(EP.businessUnits, token);
  const data: any[] = Array.isArray(raw) ? raw
                    : Array.isArray(raw?.items) ? raw.items
                    : Array.isArray(raw?.data)  ? raw.data
                    : Array.isArray(raw?.results) ? raw.results
                    : [];
  return data.map((b: any) => ({
    code: String(b.code || b.businessUnitCode || b.id || '').trim(),
    name: String(b.name || b.description || ''),
    id:   String(b.id || ''),
  })).filter(b => b.code);
}

async function listJobs(token: string, buId: string) {
  const data = await hcssGetPaginated(EP.jobs(buId), token);
  return data.map((j: any) => ({
    id:      String(j.id || ''),
    jobCode: String(j.jobCode || j.code || j.number || '').trim(),
    name:    String(j.name || j.description || ''),
    status:  String(j.status || j.jobStatus || ''),
    startDate: j.startDate || null,
    endDate: j.endDate || null,
    _raw: j, // preserve full API response for metadata sync
  })).filter(j => j.jobCode);
}

function isJobActive(j: any): boolean {
  const s = (j.status || '').toLowerCase();
  if (s.includes('closed') || s.includes('archived') || s.includes('complete') || s.includes('inactive')) return false;
  return true;
}

async function listTimeCards(token: string, buCode: string, jobId: string, sinceISO: string | null) {
  // Step 1: List timecard summaries via /timeCardInfo (returns ids, dates, foreman)
  const base = EP.timeCards(buCode, jobId);
  const url = sinceISO ? `${base}&startDate=${sinceISO}` : base;
  const summaries = await hcssGetPaginated(url, token);

  // Step 2: Fetch full detail for each timecard via /timeCards/{id}
  // This gives us costCodes[], employees[] with hours, equipment[]
  const details: any[] = [];
  for (const tc of summaries) {
    if (!tc.id) continue;
    try {
      const detail = await hcssGet(
        `${HCSS_API_BASE}/heavyjob/api/v1/timeCards/${tc.id}`,
        token
      );
      details.push(detail);
    } catch (e) {
      // Individual timecard fetch failed — skip it, don't block the whole sync
      console.warn(`Failed to fetch timecard detail ${tc.id}: ${e.message || e}`);
    }
  }
  return details;
}

async function listQuantities(token: string, buCode: string, jobId: string, sinceISO: string | null) {
  // EP.quantities already includes ?jobId=, so append with &
  // Gracefully degrade: if quantities endpoint 404s, return empty array
  // so sync still works with timecard data alone.
  try {
    const base = EP.quantities(buCode, jobId);
    const url = sinceISO ? `${base}&startDate=${sinceISO}` : base;
    return await hcssGetPaginated(url, token);
  } catch (e) {
    // 404 or other error — quantities endpoint may not be provisioned
    // Continue without quantities; timecards alone still provide labor/equip costs
    console.warn(`Quantities fetch failed (non-fatal): ${e.message || e}`);
    return [];
  }
}

// -------------------- MERGE / NORMALIZE --------------------
// HCSS timecard detail structure (from GET /timeCards/{id}):
//   - costCodes[]: { timeCardCostCodeId, costCodeCode, quantity, unitOfMeasure, isTm }
//   - employees[]: { employeeCode, employeeDescription, payClassCode,
//                    regularHours[{timeCardCostCodeId, hours}],
//                    overtimeHours[{timeCardCostCodeId, hours}],
//                    costAdjustments[{timeCardCostCodeId, amount}] }
//   - equipment[]: { equipmentCode, equipmentDescription,
//                    totalHours[{timeCardCostCodeId, hours}],
//                    operatingHours[{timeCardCostCodeId, hours}] }
//
// We produce one DetailRow per (date, costCode, foreman) by:
//   1. Building a costCodeId → costCode lookup from costCodes[]
//   2. Summing employee regular + OT hours per costCode
//   3. Summing equipment hours per costCode
//   4. Grabbing quantity from costCodes[].quantity
function mergeJobRows(jobCode: string, timeCards: any[], _quantities: any[]): DetailRow[] {
  const map = new Map<string, DetailRow>();
  const rowKey = (date: string, code: string, foreman: string) => `${date}|${code}|${foreman}`;
  const fmtDate = (v: any) => {
    if (!v) return '';
    const d = new Date(v);
    return isNaN(d.getTime()) ? '' : d.toISOString().slice(0, 10);
  };

  for (const tc of timeCards) {
    const d = fmtDate(tc.date);
    if (!d) continue;
    const foreman = String(tc.foremanDescription || tc.foremanCode || '').trim();

    // Build costCodeId → {code, unit, qty} lookup
    const ccMap = new Map<string, { code: string; unit: string; qty: number }>();
    const costCodes: any[] = tc.costCodes || [];
    for (const cc of costCodes) {
      const code = String(cc.costCodeCode || cc.code || '').trim();
      if (!code) continue;
      ccMap.set(cc.timeCardCostCodeId, {
        code,
        unit: String(cc.unitOfMeasure || ''),
        qty: num(cc.quantity),
      });
    }

    // If no cost codes on this timecard, skip it
    if (ccMap.size === 0) continue;

    // Initialize rows for each cost code
    for (const [_ccId, cc] of ccMap) {
      const k = rowKey(d, cc.code, foreman);
      if (!map.has(k)) {
        const row = blankRow(jobCode, d, cc.code, foreman);
        row.unit = cc.unit;
        row.actual_qty = cc.qty;
        map.set(k, row);
      } else {
        // Accumulate quantity if same key from different timecard
        map.get(k)!.actual_qty += cc.qty;
      }
    }

    // Sum employee hours per cost code
    const employees: any[] = tc.employees || [];
    for (const emp of employees) {
      const regHours: any[] = emp.regularHours || [];
      const otHours: any[] = emp.overtimeHours || [];
      const dotHours: any[] = emp.doubleOvertimeHours || [];
      const adjustments: any[] = emp.costAdjustments || [];

      for (const h of [...regHours, ...otHours, ...dotHours]) {
        const cc = ccMap.get(h.timeCardCostCodeId);
        if (!cc) continue;
        const k = rowKey(d, cc.code, foreman);
        const row = map.get(k);
        if (row) row.actual_labor_hours += num(h.hours);
      }

      // Cost adjustments (labor cost overrides/additions)
      for (const adj of adjustments) {
        const cc = ccMap.get(adj.timeCardCostCodeId);
        if (!cc) continue;
        const k = rowKey(d, cc.code, foreman);
        const row = map.get(k);
        if (row) row.actual_labor_cost += num(adj.amount);
      }
    }

    // Sum equipment hours per cost code
    const equipment: any[] = tc.equipment || [];
    for (const eq of equipment) {
      const allHours: any[] = [
        ...(eq.totalHours || []),
        ...(eq.operatingHours || []),
      ];
      for (const h of allHours) {
        const cc = ccMap.get(h.timeCardCostCodeId);
        if (!cc) continue;
        const k = rowKey(d, cc.code, foreman);
        const row = map.get(k);
        if (row) row.actual_equip_hours += num(h.hours);
      }
    }
  }

  return Array.from(map.values());
}

// -------------------- EQUIPMENT EXTRACTION --------------------
// Walk the timecard detail structure and accumulate:
//   (a) one observation per unique equipment code (latest job/date) → feeds hcss_equipment
//   (b) one row per (code, date, job) with total hours → feeds hcss_equipment_history
// Both pieces are collected in the same pass since timecards are expensive to fetch.
function extractEquipmentObservations(
  jobCode: string,
  timeCards: any[],
  acc: Map<string, EquipObservation>,
  histAcc: Map<string, EquipHistoryRow>,
) {
  const fmtDate = (v: any) => {
    if (!v) return '';
    const d = new Date(v);
    return isNaN(d.getTime()) ? '' : d.toISOString().slice(0, 10);
  };
  for (const tc of timeCards) {
    const d = fmtDate(tc.date);
    if (!d) continue;
    const equipment: any[] = tc.equipment || [];
    for (const eq of equipment) {
      const code = String(eq.equipmentCode || eq.code || '').trim();
      if (!code) continue;
      const desc = String(eq.equipmentDescription || eq.description || '').trim();

      // Sum hours for this machine on this timecard (all cost codes)
      const allHours: any[] = [
        ...(eq.totalHours || []),
        ...(eq.operatingHours || []),
      ];
      let tcHours = 0;
      for (const h of allHours) tcHours += num(h.hours);

      // --- (a) latest-observation accumulator ---
      const existing = acc.get(code);
      if (!existing) {
        acc.set(code, {
          code,
          description: desc,
          lastSeenDate: d,
          lastSeenJob: jobCode,
          timesSeen: 1,
          raw: { equipmentCode: code, equipmentDescription: desc },
        });
      } else {
        existing.timesSeen += 1;
        if (!existing.description && desc) existing.description = desc;
        if (d > existing.lastSeenDate) {
          existing.lastSeenDate = d;
          existing.lastSeenJob = jobCode;
        }
      }

      // --- (b) per-day history accumulator ---
      const histKey = `${code}|${d}|${jobCode}`;
      const histRow = histAcc.get(histKey);
      if (histRow) {
        histRow.hours += tcHours;
      } else {
        histAcc.set(histKey, {
          hcss_code: code,
          date: d,
          job_code: jobCode,
          hours: tcHours,
        });
      }
    }
  }
}

function blankRow(jobCode: string, date: string, costCode: string, foreman: string): DetailRow {
  return {
    job_number: jobCode, date, cost_code: costCode, foreman,
    cost_code_desc: '', unit: '',
    actual_qty: 0,
    actual_labor_hours: 0, actual_equip_hours: 0,
    actual_labor_cost: 0, actual_equip_cost: 0,
    actual_mat_cost: 0, actual_sub_cost: 0,
    expected_labor_hours: 0, expected_labor_cost: 0,
    expected_equip_cost: 0, expected_mat_cost: 0, expected_sub_cost: 0,
    source: 'hcss-api',
  };
}

// -------------------- UTILITIES --------------------
function isoDaysAgo(days: number): string {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
}

function topCountsByJob(rows: DetailRow[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const r of rows) out[r.job_number] = (out[r.job_number] || 0) + 1;
  return out;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      ...CORS_HEADERS,
      'Content-Type': 'application/json',
    },
  });
}
