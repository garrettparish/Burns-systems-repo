-- ============================================================================
-- 20261010150000_monitor_qbo_report_snapshot.sql
-- The Netlify qbo-sync (Waste's weekly QuickBooks report snapshot) died on 2026-10-08 and is replaced:
--   burns-finance sync-qbo-background now captures the official reports nightly (sync_log source 'qbo_reports'),
--   the burnsbox job waste-qbo-snapshot copies the Monday rows into Waste OS (watched by waste-feeds-watch: qbo-snapshot).
-- ============================================================================
insert into public.monitor_source
  (key, tool, type, name, description, expected_interval_min, grace_min, severity, weekdays_only)
values
  ('finance:qbo_reports','Finance','sync','QuickBooks official reports snapshot','burns-finance sync-qbo-background step: AgedReceivables/AgedPayables/BalanceSheet/ProfitAndLoss into burns_waste.qbo_report_snapshot, weekdays 02:00 CT. Feeds Waste OS qbo_weekly_snapshot (scorecard DSO, AR/AP headlines) through the box job waste-qbo-snapshot.',1440,180,'high',true)
on conflict (key) do nothing;

update public.monitor_source
   set enabled = false,
       description = description || ' [DISABLED 2026-10-10: replaced by burns-finance report capture (finance:qbo_reports) + burnsbox waste-qbo-snapshot; the Netlify function is deleted.]'
 where key = 'waste:qbo-sync' and enabled;
