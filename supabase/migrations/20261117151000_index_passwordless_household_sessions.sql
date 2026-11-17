create index if not exists mealmate_sessions_household_idx on private.mealmate_sessions (household_id);
create index if not exists mealmate_sessions_household_member_idx on private.mealmate_sessions (household_id, member_id);
