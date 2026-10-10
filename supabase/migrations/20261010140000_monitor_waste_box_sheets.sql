-- ============================================================================
-- 20261010140000_monitor_waste_box_sheets.sql
-- The burnsbox now owns three more Waste pulls that the Netlify functions stopped doing on 2026-10-08:
--   waste-sheets-sync (06:00 CT)  -> replaces waste:sheets-sync and waste:fel-inventory-sync
--   waste-qbo-detail  (03:25 CT)  -> replaces waste:qbo-detail-sync
-- The Netlify functions are deleted, so their sources would read silent/late forever. Freshness of the tables they
-- fill is judged by the box job waste-feeds-watch (data_through per table), and every box job's last run is on the
-- burnsbox status page.
-- ============================================================================
update public.monitor_source
   set enabled = false,
       description = description || ' [DISABLED 2026-10-10: replaced by a burnsbox job (waste-sheets-sync / waste-qbo-detail); the Netlify function is deleted.]'
 where key in ('waste:sheets-sync', 'waste:fel-inventory-sync', 'waste:qbo-detail-sync') and enabled;
