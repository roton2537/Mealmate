create index if not exists expenses_created_by_idx on public.expenses (created_by);
create index if not exists expenses_household_payer_idx on public.expenses (household_id, paid_by_member_id);