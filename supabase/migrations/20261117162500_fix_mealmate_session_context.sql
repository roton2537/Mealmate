
create or replace function private.get_mealmate_session_context()
returns table(member_id uuid, household_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select s.member_id, s.household_id
  from private.mealmate_sessions s
  where s.user_id = (select auth.uid())
  union all
  select m.id, m.household_id
  from public.members m
  where m.auth_user_id = (select auth.uid())
    and not exists (
      select 1 from private.mealmate_sessions s
      where s.user_id = (select auth.uid())
    );
$$;
revoke all on function private.get_mealmate_session_context() from public, anon;
grant execute on function private.get_mealmate_session_context() to authenticated;

create or replace function public.get_mealmate_session_context()
returns table(member_id uuid, household_id uuid)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from private.get_mealmate_session_context();
$$;
revoke all on function public.get_mealmate_session_context() from public, anon;
grant execute on function public.get_mealmate_session_context() to authenticated;
