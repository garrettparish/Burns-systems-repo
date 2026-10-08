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
// The source must already exist in public.monitor_source (curated registry —
// unknown keys are rejected so a typo can't create a source that never alerts).
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

  const source_key = typeof body.source_key === 'string' ? body.source_key : '';
  const status = body.status;
  if (!source_key) return json({ error: 'source_key required' }, 400);
  if (status !== 'ok' && status !== 'warn' && status !== 'error') {
    return json({ error: "status must be 'ok' | 'warn' | 'error'" }, 400);
  }
  const duration_ms = Number.isFinite(body.duration_ms) ? Math.round(body.duration_ms as number) : null;
  const message = typeof body.message === 'string' ? body.message.slice(0, 1000) : null;
  const detail = body.detail && typeof body.detail === 'object' ? body.detail : null;

  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: src, error: srcErr } = await sb
    .from('monitor_source').select('key').eq('key', source_key).maybeSingle();
  if (srcErr) return json({ error: srcErr.message }, 500);
  if (!src) return json({ error: `unknown source_key '${source_key}' — register it in monitor_source first` }, 404);

  const { error } = await sb.from('monitor_event').insert({ source_key, status, duration_ms, message, detail });
  if (error) return json({ error: error.message }, 500);
  return json({ ok: true });
});
