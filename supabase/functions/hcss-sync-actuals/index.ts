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
const HCSS_SCOPES      = Deno.env.get('HCSS_SCOPES')      || 'heavyjob:read setups:read setups:write timecards:read';
const LOOKBACK_DAYS    = parseInt(Deno.env.get('HCSS_LOOKBACK_DAYS') || '14', 10);

// Endpoint paths — confirmed against HCSS developer portal on 2026-04-10.
// BusinessUnit and Job live under the `setups` product (NOT heavyjob) and use
// PascalCase singular resource names. Jobs takes businessUnitCode as a
// query param rather than a path segment.
// TimeCard / Quantity endpoints under /heavyjob/api/v1/... are still best-guess
// and will be confirmed once discovery succeeds.
const EP = {
  businessUnits: `${HCSS_API_BASE}/setups/api/v1/BusinessUnit`,
  jobs:          (buCode: string) => `${HCSS_API_BASE}/setups/api/v1/Job?businessUnitCode=${encodeURIComponent(buCode)}`,
  timeCards:     (_buCode: string, jobCode: string) => `${HCSS_API_BASE}/heavyjob/api/v1/TimeCard?jobCode=${encodeURIComponent(jobCode)}`,
  quantities:    (_buCode: string, jobCode: string) => `${HCSS_API_BASE}/heavyjob/api/v1/Quantity?jobCode=${encodeURIComponent(jobCode)}`,
};

// -------------------- TYPES --------------------
interface TokenResponse { access_token: string; token_type: string; expires_in: number; scope?: string }

// Module-level cache of the last minted token's granted scope string,
// so discovery mode can surface it to the caller for debugging.
let _lastGrantedScope: string | null = null;
interface SyncRequest { trigger?: 'cron'|'manual'|'api'; discover?: boolean; lookbackDays?: number; jobNumber?: string; fullHistory?: boolean }
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

// -------------------- MAIN HANDLER --------------------
Deno.serve(async (req) => {
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

    const buCode = buEnv;
    if (!bus.some(b => b.code === buCode)) {
      throw new Error(`HCSS_BUSINESS_UNIT_CODE='${buCode}' not found in this account's BU list. Available: ${bus.map(b=>b.code).join(', ')}`);
    }

    // 3. List jobs
    let jobs = await listJobs(token, buCode);
    if (body.jobNumber) jobs = jobs.filter(j => j.jobCode === body.jobNumber);
    // Active jobs only — skip closed/archived.
    const activeJobs = jobs.filter(j => isJobActive(j));

    // 4. Pull data per job
    // If fullHistory, `since` is null → listTimeCards/listQuantities will omit startDate.
    const since = lookback == null ? null : isoDaysAgo(lookback);
    const rows: DetailRow[] = [];
    const errors: { job: string; error: string }[] = [];

    for (const job of activeJobs) {
      try {
        const [tcs, qs] = await Promise.all([
          listTimeCards(token, buCode, job.jobCode, since),
          listQuantities(token, buCode, job.jobCode, since),
        ]);
        rows.push(...mergeJobRows(job.jobCode, tcs, qs));
      } catch (e) {
        errors.push({ job: job.jobCode, error: String(e.message || e) });
      }
    }

    // 5. Upsert
    let inserted = 0, updated = 0;
    if (rows.length) {
      const { error, count } = await supa
        .from('actuals_detail_sync')
        .upsert(rows, { onConflict: 'job_number,date,cost_code,foreman', count: 'exact' });
      if (error) throw new Error(`Upsert failed: ${error.message}`);
      // Supabase returns total affected, not split insert/update. Report in "rows_updated".
      updated = count || rows.length;
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
      },
    });

    return json({
      ok: true,
      status,
      jobsSynced: activeJobs.length,
      rowsUpserted: updated,
      errors,
      durationMs: Date.now() - startedAt,
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
  // HCSS paginates with skip/limit on most collection endpoints.
  // If the list is returned at top level, we handle that too.
  const out: any[] = [];
  const pageSize = 500;
  let skip = 0;
  for (;;) {
    const sep = url.includes('?') ? '&' : '?';
    const pageUrl = `${url}${sep}skip=${skip}&limit=${pageSize}`;
    const data = await hcssGet(pageUrl, token);
    const items: any[] = Array.isArray(data) ? data
                       : Array.isArray(data?.items) ? data.items
                       : Array.isArray(data?.data)  ? data.data
                       : Array.isArray(data?.results) ? data.results
                       : [];
    out.push(...items);
    if (items.length < pageSize) break;
    skip += pageSize;
    if (skip > 50000) break; // safety
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

async function listJobs(token: string, buCode: string) {
  const data = await hcssGetPaginated(EP.jobs(buCode), token);
  return data.map((j: any) => ({
    jobCode: String(j.jobCode || j.code || j.number || '').trim(),
    name:    String(j.name || j.description || ''),
    status:  String(j.status || j.jobStatus || ''),
    startDate: j.startDate, endDate: j.endDate,
  })).filter(j => j.jobCode);
}

function isJobActive(j: any): boolean {
  const s = (j.status || '').toLowerCase();
  if (s.includes('closed') || s.includes('archived') || s.includes('complete') || s.includes('inactive')) return false;
  return true;
}

async function listTimeCards(token: string, buCode: string, jobCode: string, sinceISO: string | null) {
  const url = sinceISO ? `${EP.timeCards(buCode, jobCode)}?startDate=${sinceISO}` : EP.timeCards(buCode, jobCode);
  return await hcssGetPaginated(url, token);
}

async function listQuantities(token: string, buCode: string, jobCode: string, sinceISO: string | null) {
  const url = sinceISO ? `${EP.quantities(buCode, jobCode)}?startDate=${sinceISO}` : EP.quantities(buCode, jobCode);
  return await hcssGetPaginated(url, token);
}

// -------------------- MERGE / NORMALIZE --------------------
// HCSS time cards contain labor + equipment costs keyed by date/costCode/foreman.
// HCSS quantities contain installed quantity by date/costCode.
// We accumulate both into the same composite-key map so the final DetailRow
// mirrors exactly what parseActualsDetailRaw() produces from the XLSX file.
function mergeJobRows(jobCode: string, timeCards: any[], quantities: any[]): DetailRow[] {
  const map = new Map<string, DetailRow>();
  const key = (date: string, code: string, foreman: string) => `${date}|${code}|${foreman}`;
  const pick = (o: any, keys: string[]): any => {
    for (const k of keys) if (o[k] != null) return o[k];
    return undefined;
  };
  const num = (v: any) => { const n = Number(v); return isFinite(n) ? n : 0; };
  const date = (v: any) => {
    if (!v) return '';
    const d = new Date(v);
    return isNaN(d.getTime()) ? '' : d.toISOString().slice(0, 10);
  };

  // Time cards — one row per (date, cost code, foreman) with cost breakdown.
  for (const tc of timeCards) {
    // Some HCSS TC shapes nest entries under `entries` or `costCodeEntries`.
    const entries: any[] = Array.isArray(tc.entries) ? tc.entries
                        : Array.isArray(tc.costCodeEntries) ? tc.costCodeEntries
                        : [tc];
    for (const e of entries) {
      const d = date(pick(e, ['date', 'workDate', 'timeCardDate']) || pick(tc, ['date', 'workDate', 'timeCardDate']));
      const costCode = String(pick(e, ['costCode', 'costCodeCode', 'code']) || '').trim();
      if (!d || !costCode) continue;
      const foreman = String(pick(e, ['foreman', 'foremanName']) || pick(tc, ['foreman', 'foremanName']) || '').trim();
      const k = key(d, costCode, foreman);
      let row = map.get(k);
      if (!row) {
        row = blankRow(jobCode, d, costCode, foreman);
        row.cost_code_desc = String(pick(e, ['costCodeDescription', 'description']) || '');
        row.unit = String(pick(e, ['unit', 'units', 'unitOfMeasure']) || '');
        map.set(k, row);
      }
      row.actual_labor_hours  += num(pick(e, ['laborHours', 'actualLaborHours', 'hours']));
      row.actual_equip_hours  += num(pick(e, ['equipmentHours', 'actualEquipmentHours', 'equipHours']));
      row.actual_labor_cost   += num(pick(e, ['laborCost', 'actualLaborCost']));
      row.actual_equip_cost   += num(pick(e, ['equipmentCost', 'actualEquipmentCost']));
      row.actual_mat_cost     += num(pick(e, ['materialCost', 'actualMaterialCost']));
      row.actual_sub_cost     += num(pick(e, ['subcontractCost', 'actualSubcontractCost']));
      row.expected_labor_hours+= num(pick(e, ['expectedLaborHours', 'budgetLaborHours']));
      row.expected_labor_cost += num(pick(e, ['expectedLaborCost',  'budgetLaborCost']));
      row.expected_equip_cost += num(pick(e, ['expectedEquipmentCost', 'budgetEquipmentCost']));
      row.expected_mat_cost   += num(pick(e, ['expectedMaterialCost',  'budgetMaterialCost']));
      row.expected_sub_cost   += num(pick(e, ['expectedSubcontractCost','budgetSubcontractCost']));
    }
  }

  // Quantities — attach installed qty to the matching (date, code, foreman) row.
  // If the quantity row has no foreman, we attach it to the foreman='' row.
  for (const q of quantities) {
    const d = date(pick(q, ['date', 'workDate', 'reportDate']));
    const costCode = String(pick(q, ['costCode', 'code']) || '').trim();
    if (!d || !costCode) continue;
    const foreman = String(pick(q, ['foreman', 'foremanName']) || '').trim();
    const k = key(d, costCode, foreman);
    let row = map.get(k);
    if (!row) {
      row = blankRow(jobCode, d, costCode, foreman);
      row.cost_code_desc = String(pick(q, ['costCodeDescription', 'description']) || '');
      row.unit = String(pick(q, ['unit', 'units']) || '');
      map.set(k, row);
    }
    row.actual_qty += num(pick(q, ['quantity', 'actualQuantity', 'installedQuantity']));
  }

  return Array.from(map.values());
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
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'authorization, content-type',
    },
  });
}
