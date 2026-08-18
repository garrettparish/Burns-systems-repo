-- Surface HCSS's per-cost-code BUDGET dollars as first-class columns.
--
-- hcss-sync-actuals' metadata sync (syncMetadata mode) already fetches the
-- full costCodes API response per job and stores it verbatim in
-- hcss_cost_codes.raw (see index.ts's syncMetadata block, `raw: cc`) -- that
-- response already includes laborDollars/equipmentDollars/materialDollars/
-- subcontractDollars/supplyDollars/laborHours/equipmentHours per cost code.
-- None of that was ever pulled out into queryable columns; it's been sitting
-- in the JSONB blob, fully populated, the whole time.
--
-- Verified live 2026-08-18: all 2,614 existing hcss_cost_codes rows have
-- raw.laborDollars populated. Company-wide totals from the new columns:
-- $9.58M labor budget, $24.4M material budget, $38.2M subcontract budget.
--
-- Using GENERATED ALWAYS ... STORED (not a one-time backfill column) so
-- these stay correct automatically on every future metadata sync re-upsert
-- of raw, with zero Edge Function code change or redeploy needed.

alter table public.hcss_cost_codes
  add column if not exists budget_labor_dollars      numeric generated always as ((raw->>'laborDollars')::numeric)      stored,
  add column if not exists budget_equipment_dollars   numeric generated always as ((raw->>'equipmentDollars')::numeric) stored,
  add column if not exists budget_material_dollars    numeric generated always as ((raw->>'materialDollars')::numeric) stored,
  add column if not exists budget_subcontract_dollars numeric generated always as ((raw->>'subcontractDollars')::numeric) stored,
  add column if not exists budget_supply_dollars      numeric generated always as ((raw->>'supplyDollars')::numeric)    stored,
  add column if not exists budget_labor_hours         numeric generated always as ((raw->>'laborHours')::numeric)      stored,
  add column if not exists budget_equipment_hours     numeric generated always as ((raw->>'equipmentHours')::numeric)  stored;

comment on column public.hcss_cost_codes.budget_labor_dollars is
  'Budgeted labor $ for this cost code, from HCSS costCodes API (raw.laborDollars). Generated column -- always in sync with raw, no separate backfill needed.';
