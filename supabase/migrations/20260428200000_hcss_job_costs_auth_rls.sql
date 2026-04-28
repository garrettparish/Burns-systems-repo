-- 2026-04-28b — Fix RLS on hcss_job_costs.
-- The 20260420 migration switched all HCSS read-only tables from anon to
-- authenticated-only. The 20260428 migration created hcss_job_costs with the
-- old anon-read pattern, so logged-in users couldn't see the rows even though
-- the Edge Function (service_role) was writing them successfully.

drop policy if exists "anon read hcss_job_costs" on public.hcss_job_costs;
drop policy if exists "auth users select hcss job costs" on public.hcss_job_costs;

create policy "auth users select hcss job costs"
  on public.hcss_job_costs
  for select
  to authenticated
  using (true);
