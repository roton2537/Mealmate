create or replace function private.unlock_mealmate_household(p_access_code text, p_member_name text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := auth.uid();
  target_household uuid;
  target_member uuid;
  stored_hash text;
begin
  if current_user_id is null or coalesce((auth.jwt()->>'is_anonymous')::boolean, false) is not true then
    raise exception 'A private anonymous session is required';
  end if;
  select h.id into target_household from public.households h where h.slug = 'mealmate-shared';
  select c.code_hash into stored_hash from private.mealmate_access_codes c where c.household_id = target_household;
  if stored_hash is null or encode(sha256(convert_to(trim(coalesce(p_access_code, '')), 'UTF8')), 'hex') <> stored_hash then
    raise exception 'The household access code is incorrect';
  end if;
  select m.id into target_member from public.members m where m.household_id = target_household and m.name = trim(coalesce(p_member_name, ''));
  if target_member is null then raise exception 'Select one of the approved household members'; end if;
  insert into private.mealmate_sessions (user_id, household_id, member_id)
  values (current_user_id, target_household, target_member)
  on conflict (user_id) do update set household_id = excluded.household_id, member_id = excluded.member_id;
  return true;
end;
$$;
revoke all on function private.unlock_mealmate_household(text, text) from public;
grant execute on function private.unlock_mealmate_household(text, text) to authenticated;
create or replace function public.unlock_mealmate_household(p_access_code text, p_member_name text)
returns boolean language sql security invoker set search_path = '' as $$
  select private.unlock_mealmate_household(p_access_code, p_member_name);
$$;
revoke all on function public.unlock_mealmate_household(text, text) from public, anon;
grant execute on function public.unlock_mealmate_household(text, text) to authenticated;
