-- Final removal of the retired single-household implementation.
-- Historical migrations remain in git for auditability; this migration ensures
-- fresh installs finish with only the multi-team MealMate schema.
drop table if exists public.expenses cascade;
drop table if exists public.members cascade;
drop table if exists public.households cascade;
drop table if exists private.mealmate_access_codes cascade;
drop table if exists private.mealmate_invitations cascade;
drop table if exists private.mealmate_sessions cascade;

drop function if exists public.add_mealmate_member(text,text) cascade;
drop function if exists public.claim_mealmate_invitation(text) cascade;
drop function if exists public.create_mealmate_invitation(uuid,text) cascade;
drop function if exists public.deactivate_mealmate_member(uuid) cascade;
drop function if exists public.get_mealmate_session_context() cascade;
drop function if exists public.list_mealmate_members(text) cascade;
drop function if exists public.unlock_mealmate_household(text,text) cascade;

drop function if exists private.add_mealmate_member(text,text) cascade;
drop function if exists private.claim_mealmate_invitation(text) cascade;
drop function if exists private.create_mealmate_invitation(uuid,text) cascade;
drop function if exists private.deactivate_mealmate_member(uuid) cascade;
drop function if exists private.get_mealmate_session_context() cascade;
drop function if exists private.guard_expense_update() cascade;
drop function if exists private.is_mealmate_admin() cascade;
drop function if exists private.is_mealmate_member(uuid) cascade;
drop function if exists private.list_mealmate_members(text) cascade;
drop function if exists private.unlock_mealmate_household(text,text) cascade;
