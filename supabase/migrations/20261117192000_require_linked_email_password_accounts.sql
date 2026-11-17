-- Final authentication cutover: household data is accessible only to linked,
-- non-anonymous Supabase Auth users. Existing household records are untouched.
create unique index if not exists members_auth_user_id_unique
  on public.members(auth_user_id) where auth_user_id is not null;

create or replace function private.get_mealmate_session_context()
returns table(member_id uuid, household_id uuid)
language sql stable security definer set search_path = ''
as $$
  select m.id, m.household_id
  from public.members m
  where m.auth_user_id = (select auth.uid())
    and m.deactivated_at is null
    and coalesce((select auth.jwt()->>'is_anonymous')::boolean,false) = false;
$$;

create or replace function private.is_mealmate_member(target_household uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce((select auth.jwt()->>'is_anonymous')::boolean,false) = false
    and exists (
      select 1 from public.members m
      where m.household_id = target_household
        and m.auth_user_id = (select auth.uid())
        and m.deactivated_at is null
    );
$$;

create or replace function private.is_mealmate_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce((select auth.jwt()->>'is_anonymous')::boolean,false) = false
    and exists (
      select 1 from public.members m
      where m.auth_user_id = (select auth.uid())
        and m.name = 'MD ROTON MIAH'
        and m.deactivated_at is null
    );
$$;

delete from private.mealmate_sessions;

revoke all on function public.unlock_mealmate_household(text,text) from public,anon,authenticated;
revoke all on function public.list_mealmate_members(text) from public,anon,authenticated;
revoke all on function private.unlock_mealmate_household(text,text) from public,anon,authenticated;
revoke all on function private.list_mealmate_members(text) from public,anon,authenticated;
