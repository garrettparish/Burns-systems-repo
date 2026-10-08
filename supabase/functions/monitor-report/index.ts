// monitor-report — heartbeat ingest for the System Health tab.
//
// Anything that can't be judged from sync_log / pg_cron (external APIs, MCP
// servers, burnsbox jobs, Netlify scheduled functions in other repos) POSTs one
// event per run:
//
//   POST /functions/v1/monitor-report
//   Authorization: Bearer <MONITOR_TOKEN>
//   { "source_key": "samsara:api", "status": "ok" | "warn" | "error",
//     "duration_ms": 1234, "message": "optional", "detail": { ... } }
//
// Batch form (used by the spine feed): { "events": [ {source_key, status, at?, external_id?, ...}, ... ] }
// — up to 500; external_id makes re-sent events idempotent; unknown sources are skipped and listed in the reply.
//
// The source must already exist in public.monitor_source (curated registry —
// a single-event call with an unknown key is rejected so a typo can't create a source that never alerts).
//
// Deploy (ask first — see CLAUDE.md 10.1):
//   supabase secrets set MONITOR_TOKEN=<random-value>
//   supabase functions deploy monitor-report --no-verify-jwt
//
// verify_jwt is off for the same reason as hcss-sync-actuals: a gateway JWT
// check would pass the public anon key, so the shared token is the real gate.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

// Constant-time compare on fixed-size buffers (mirrors hcss-sync-actuals).
function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const aBytes = enc.encode(a);
  const bBytes = enc.encode(b);
  const maxLen = Math.max(aBytes.length, bBytes.length, 32);
  let diff = aBytes.length ^ bBytes.length;
  for (let i = 0; i < maxLen; i++) diff |= (aBytes[i] ?? 0) ^ (bBytes[i] ?? 0);
  return diff === 0;
}

function authorized(req: Request): boolean {
  const expected = Deno.env.get('MONITOR_TOKEN');
  if (!expected) return false; // fail closed
  const m = (req.headers.get('authorization') || '').match(/^Bearer\s+(.+)$/i);
  return !!m && timingSafeEqual(m[1], expected);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'POST only' }, 405);
  if (!authorized(req)) return json({ error: 'unauthorized' }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'invalid JSON' }, 400);
  }

  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Batch: { events: [ {source_key, status, at?, external_id?, ...}, ... ] }
  // Single: { source_key, status, ... }  (treated as a batch of one)
  const rawEvents: Record<string, unknown>[] = Array.isArray(body.events)
    ? (body.events as Record<string, unknown>[]).slice(0, 500)
    : [body];
  if (rawEvents.length === 0) return json({ ok: true, inserted: 0 });

  const { data: known, error: srcErr } = await sb.from('monitor_source').select('key');
  if (srcErr) return json({ error: srcErr.message }, 500);
  const knownKeys = new Set((known ?? []).map((r: { key: string }) => r.key));

  const now = Date.now();
  const rows: Record<string, unknown>[] = [];
  const unknown = new Set<string>();
  const invalid: string[] = [];
  for (const e of rawEvents) {
    const source_key = typeof e.source_key === 'string' ? e.source_key : '';
    const status = e.status;
    if (!source_key || (status !== 'ok' && status !== 'warn' && status !== 'error')) {
      invalid.push(source_key || '(missing source_key)');
      continue;
    }
    if (!knownKeys.has(source_key)) { unknown.add(source_key); continue; }
    // Pushed events may carry their own timestamp, but never from the future
    // and never older than 3 days (stops a bad feed rewriting history).
    let at: string | undefined;
    if (typeof e.at === 'string') {
      const t = Date.parse(e.at);
      if (Number.isFinite(t) && t <= now + 60_000 && t >= now - 3 * 86_400_000) at = new Date(t).toISOString();
    }
    rows.push({
      source_key,
      status,
      ...(at ? { at } : {}),
      duration_ms: Number.isFinite(e.duration_ms) ? Math.round(e.duration_ms as number) : null,
      message: typeof e.message === 'string' ? e.message.slice(0, 1000) : null,
      detail: e.detail && typeof e.detail === 'object' ? e.detail : null,
      external_id: typeof e.external_id === 'string' ? e.external_id.slice(0, 200) : null,
    });
  }

  // Single-event callers keep the strict contract: bad input is an error.
  if (!Array.isArray(body.events)) {
    if (invalid.length) return json({ error: "source_key required and status must be 'ok' | 'warn' | 'error'" }, 400);
    if (unknown.size) return json({ error: `unknown source_key '${[...unknown][0]}' — register it in monitor_source first` }, 404);
  }

  if (rows.length) {
    // Rows with an external_id are idempotent (re-sent buckets are ignored).
    const withId = rows.filter((r) => r.external_id);
    const withoutId = rows.filter((r) => !r.external_id);
    if (withId.length) {
      const { error } = await sb.from('monitor_event')
        .upsert(withId, { onConflict: 'source_key,external_id', ignoreDuplicates: true });
      if (error) return json({ error: error.message }, 500);
    }
    if (withoutId.length) {
      const { error } = await sb.from('monitor_event').insert(withoutId);
      if (error) return json({ error: error.message }, 500);
    }
  }
  return json({ ok: true, received: rawEvents.length, accepted: rows.length, unknown_sources: [...unknown], invalid: invalid.length });
});
