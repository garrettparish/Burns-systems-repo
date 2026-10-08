-- ============================================================================
-- 20261008150000_monitor_waste_people.sql
-- Registers the Waste (waste-dashboard) and People OS Netlify scheduled jobs.
-- Evidence: heartbeats from the withMonitor() wrapper
-- (netlify/functions/lib/monitor.js in each repo) via monitor-report.
--
-- Note: curbwaste-sync and cw-inventory-sync are TRIGGER functions that start a
-- -background function; the heartbeat comes from the background function (the one
-- that does the work and logs cw_sync_runs / cw_inventory_sync_runs), not the trigger.
-- ============================================================================
insert into public.monitor_source
  (key, tool, type, name, description, expected_interval_min, grace_min, window_start_hour, window_end_hour, severity, weekdays_only)
values
  ('waste:curbwaste-sync','Waste','sync','CurbWaste dispatch pull','07:30 UTC daily, OTP login via Gmail then API pull (background fn). Gmail quota 403s seen 4x in the week before registration.',1440,240,null,null,'high',false),
  ('waste:cw-inventory-sync','Waste','sync','CurbWaste inventory pull','07:40 UTC daily (background fn), shares the Gmail OTP quota with the dispatch pull',1440,240,null,null,'normal',false),
  ('waste:sheets-sync','Waste','sync','Google Sheets sync','11:00 UTC daily',1440,240,null,null,'normal',false),
  ('waste:fel-inventory-sync','Waste','sync','FEL inventory sync','11:15 UTC daily',1440,240,null,null,'normal',false),
  ('waste:samsara-waste-sync','Waste','api','Samsara (waste fleet) sync','11:00 UTC daily; its safety-event fetch can fail while the endpoint still answers ok',1440,240,null,null,'normal',false),
  ('waste:qbo-sync','Waste','api','QuickBooks weekly P&L snapshot','Mondays 13:00 UTC; shares one QBO refresh token with Finance',10080,1440,null,null,'high',false),
  ('waste:qbo-detail-sync','Waste','sync','QuickBooks detail copy','13:00 UTC daily, copies burns_waste.* into Waste tables',1440,240,null,null,'normal',false),
  ('waste:payroll-sync','Waste','sync','Payroll sheet sync','12:30 UTC daily; code notes it is a no-op cron',1440,240,null,null,'low',false),
  ('waste:notion-l10-sync','Waste','api','Notion L10 sync','23:00 UTC daily; still depends on Notion (Fellow recaps)',1440,240,null,null,'low',false),
  ('waste:sync-dirt-inbox','Waste','sync','Dirt inbox sync','11:00 UTC daily',1440,240,null,null,'normal',false),
  ('waste:scrape-planhouse-public','Waste','api','Planhouse public scraper','10:00 UTC daily',1440,240,null,null,'low',false),
  ('waste:scrape-planholders','Waste','api','Planholders scraper','10:30 UTC daily',1440,240,null,null,'low',false),
  ('waste:scrape-central-bidding','Waste','api','Central Bidding scraper','11:30 UTC daily',1440,240,null,null,'low',false),
  ('waste:trigger-leads-digest','Waste','sync','Leads digest email','Mon + Thu 13:00 UTC',5760,1440,null,null,'low',false),
  ('waste:capacity-recommendations-sync','Waste','sync','Capacity recommendations','Mondays 14:00 UTC',10080,1440,null,null,'low',false),
  ('people:bamboohr-sync','People OS','api','BambooHR employee sync','Hourly 11:00-23:00 UTC plus 07:00; writes the employees table',60,90,11,23,'high',false),
  ('people:bamboohr-supervisor-sync','People OS','api','BambooHR supervisor sync','11:15 UTC daily, one API call per active employee',1440,240,null,null,'normal',false),
  ('people:bamboohr-dates-sync','People OS','api','BambooHR dates sync','11:30 UTC daily, one API call per active employee',1440,240,null,null,'normal',false)
on conflict (key) do nothing;
