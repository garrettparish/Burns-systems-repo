// monitor-pull-remote — pulls run results the monitor can't receive by push.
//
// For projects where we can read a log but can't change the deployed code (People OS: its
// BambooHR syncs write public.sync_log in the People OS database, and burnsos-people-os is
// deployed from a repo we don't control). Each probe calls a read-only RPC in the remote
// project with that project's PUBLIC anon key (the one its own front end ships), maps log
// sources to monitor_source keys, and writes events idempotently (external_id), exactly like
// the push feeds.
//
// Triggered every 10 minutes by Project Controls pg_cron (job 'monitor-pull-remote', Bearer
// MONITOR_TOKEN from vault). Same auth as monitor-report.
//   supabase functions deploy monitor-pull-remote --no-verify-jwt
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const PROBES = [
  {
    name: 'people-os',
    rpc: 'https://sthianwnfwmhkturtyem.supabase.co/rest/v1/rpc/monitor_sync_log',
    // Public anon key (role=anon), shipped in People OS's own front end. Not a secret.
    anonKey:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN0aGlhbnduZndtaGt0dXJ0eWVtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5MDcyMzgsImV4cCI6MjA5MDQ4MzIzOH0.jn58XviHGa2o-dHBUmPUsnPbs2c7PfAOjW4tSc8ocbY',
    idPrefix: 'plog',
    sources: {
      bamboohr: 'people:bamboohr-sync',
      bamboohr_supervisor: 'people:bamboohr-supervisor-sync',
      bamboohr_timeoff: 'people:bamboohr-timeoff-sync',
    } as Record<string, string>,
  },
];

const CORS = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type' };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...CORS, 'Content-Type': 'application/json' } });

function timingSafeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder(); const x = enc.encode(a), y = enc.encode(b);
  const n = Math.max(x.length, y.length, 32); let d = x.length ^ y.length;
  for (let i = 0; i < n; i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0;
}
function authorized(req: Request): boolean {
  const expected = Deno.env.get('MONITOR_TOKEN');
  if (!expected) return false;
  const m = (req.headers.get('authorization') || '').match(/^Bearer\s+(.+)$/i);
  return !!m && timingSafeEqual(m[1], expected);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
  if (!authorized(req)) return json({ error: 'unauthorized' }, 401);

  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data: known, error: kErr } = await sb.from('monitor_source').select('key');
  if (kErr) return json({ error: kErr.message }, 500);
  const knownKeys = new Set((known ?? []).map((r: { key: string }) => r.key));

  const report: Record<string, unknown> = {};
  for (const p of PROBES) {
    try {
      const res = await fetch(p.rpc, {
        method: 'POST',
        headers: { apikey: p.anonKey, Authorization: `Bearer ${p.anonKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ since_hours: 72 }),
        signal: AbortSignal.timeout(15000),
      });
      if (!res.ok) { report[p.name] = { error: `HTTP ${res.status}` }; continue; }
      const rows = (await res.json()) as Array<{
        id: string; source: string; status: string; synced_at: string;
        records_synced: number | null; error_message: string | null; errors: number | null;
      }>;
      const events = rows
        .filter((r) => p.sources[r.source] && knownKeys.has(p.sources[r.source]))
        .map((r) => ({
          source_key: p.sources[r.source],
          at: r.synced_at,
          status: r.status === 'success' ? ((r.errors ?? 0) > 0 ? 'warn' : 'ok') : r.status === 'partial' ? 'warn' : 'error',
          message: (r.error_message ?? `${r.records_synced ?? 0} records${(r.errors ?? 0) > 0 ? `, ${r.errors} error(s)` : ''}`).slice(0, 500),
          external_id: `${p.idPrefix}:${r.id}`,
        }));
      if (events.length) {
        const { error } = await sb.from('monitor_event').upsert(events, { onConflict: 'source_key,external_id', ignoreDuplicates: true });
        if (error) { report[p.name] = { error: error.message }; continue; }
      }
      report[p.name] = { rows: rows.length, events: events.length };
    } catch (e) {
      report[p.name] = { error: String((e as Error)?.message ?? e) };
    }
  }
  return json({ ok: true, report });
});
