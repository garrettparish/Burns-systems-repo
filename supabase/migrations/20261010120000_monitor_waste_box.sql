-- ============================================================================
-- 20261010120000_monitor_waste_box.sql
-- The burnsbox job waste-cw-pull took over the CurbWaste pulls from the Netlify functions (which stopped 2026-10-08).
-- Evidence: the Waste OS run logs, pulled every 10 min by monitor-pull-remote via the read-only RPC
-- public.monitor_cw_runs (supabase/monitor-feeds/waste_monitor_rpc.sql, applied to the Waste OS project).
-- ============================================================================
insert into public.monitor_source
  (key, tool, type, name, description, expected_interval_min, grace_min, severity, weekdays_only)
values
  ('waste:cw-dispatch','Waste','sync','CurbWaste dispatch pull (burnsbox)','burnsbox waste-cw-pull, 03:05 CT daily: replaces the trailing 14-day cw_dispatch window. Judged by cw_sync_runs via monitor_cw_runs.',1440,240,'high',false),
  ('waste:cw-ar','Waste','sync','CurbWaste AR snapshot (burnsbox)','Same job. cw_ar_snapshot is the ONLY AR history that will ever exist (CurbWaste serves current state only): a missed night is gone for good.',1440,240,'high',false),
  ('waste:cw-inventory','Waste','sync','CurbWaste container inventory (burnsbox)','Same job. Live mirror + daily per-size history (cw_container_inventory_day), also unrecoverable if a night is missed.',1440,240,'high',false)
on conflict (key) do nothing;

update public.monitor_source
   set enabled = false,
       description = description || ' [DISABLED 2026-10-10: replaced by the burnsbox job waste-cw-pull (waste:cw-dispatch / waste:cw-ar / waste:cw-inventory); the Netlify job stopped 2026-10-08.]'
 where key in ('waste:curbwaste-sync', 'waste:cw-inventory-sync') and enabled;

-- finance:actuals (Dirt OS sync-finance-actuals, 10:30 UTC) runs weekdays only; without this every Saturday
-- check read it as a day late.
update public.monitor_source set weekdays_only = true where key = 'finance:actuals' and not weekdays_only;
