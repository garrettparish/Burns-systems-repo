-- The burnsbox now runs these former Netlify jobs (dead since 2026-10-08); their Netlify functions are deleted.
--   waste-leads-planhouse / waste-leads-dirt-inbox -> waste:scrape-planhouse-public, waste:sync-dirt-inbox
--   waste-capacity (Mon 09:00 CT)                  -> waste:capacity-recommendations-sync
-- Freshness of the tables they fill stays watched by the box job waste-feeds-watch.
update public.monitor_source
   set enabled = false,
       description = description || ' [DISABLED 2026-10-10: replaced by a burnsbox job (waste-leads-planhouse / waste-leads-dirt-inbox / waste-capacity); the Netlify function is deleted.]'
 where key in ('waste:scrape-planhouse-public', 'waste:sync-dirt-inbox', 'waste:capacity-recommendations-sync')
   and enabled;
