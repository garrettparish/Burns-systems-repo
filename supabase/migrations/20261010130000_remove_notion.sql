-- Notion is retired company-wide (Nic, 2026-10-10). Nothing may pull from it, so the System Health board must not
-- list a Notion source (the Netlify notion-l10-sync function was deleted; the earlier seed in
-- 20261008150000_monitor_waste_people.sql is history). Also retires the no-op payroll-sheet cron: the box job
-- waste-payroll owns payroll. Idempotent; already applied by hand the same day.
delete from public.monitor_source where key = 'waste:notion-l10-sync';
update public.monitor_source
   set enabled = false,
       description = description || ' [DISABLED 2026-10-10: no-op cron; the box job waste-payroll owns payroll.]'
 where key = 'waste:payroll-sync' and enabled;
