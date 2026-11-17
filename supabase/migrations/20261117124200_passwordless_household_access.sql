-- Passwordless, device-persistent household access.
-- Anonymous Auth sessions are still authenticated by Supabase and remain protected by RLS.
create table if not exists private.mealmate_access_codes (
  household_id uuid primary key references public.households(id) on delete cascade,
  code_hash text not null,
  created_at timestamptz not null default now()
);
revoke all on private.mealmate_access_codes from public, anon, authenticated;

create table if not exists private.mealmate_sessions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  household_id uuid not null references public.households(id) on delete cascade,
  member_id uuid not null,
  created_at timestamptz not null default now(),
  constraint mealmate_sessions_member_fk
    foreign key (household_id, member_id)
    references public.members (household_id, id) on delete cascade
);
revoke all on private.mealmate_sessions from public, anon, authenticated;

insert into private.mealmate_access_codes (household_id, code_hash)
select id, encode(sha256(convert_to('MM-7KQ4-N9PX-3W8D-6R2V', 'UTF8')), 'hex')
from public.households
where slug = 'mealmate-shared'
on conflict (household_id) do update
set code_hash = excluded.code_hash;

create or replace function private.is_mealmate_member(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    exists (
      select 1 from private.mealmate_sessions s
      where s.household_id = target_household
        and s.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.members m
      where m.household_id = target_household
        and m.auth_user_id = (select auth.uid())
    );
$$;
revoke all on function private.is_mealmate_member(uuid) from public;
grant execute on function private.is_mealmate_member(uuid) to authenticated;

create or replace function public.unlock_mealmate_household(p_access_code text, p_member_name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := auth.uid();
  target_household uuid;
  target_member uuid;
  stored_hash text;
begin
  if current_user_id is null
     or coalesce((auth.jwt()->>'is_anonymous')::boolean, false) is not true then
    raise exception 'A private anonymous session is required';
  end if;

  select h.id into target_household
  from public.households h
  where h.slug = 'mealmate-shared';

  select c.code_hash into stored_hash
  from private.mealmate_access_codes c
  where c.household_id = target_household;

  if stored_hash is null
     or encode(sha256(convert_to(trim(coalesce(p_access_code, '')), 'UTF8')), 'hex') <> stored_hash then
    raise exception 'The household access code is incorrect';
  end if;

  select m.id into target_member
  from public.members m
  where m.household_id = target_household
    and m.name = trim(coalesce(p_member_name, ''));

  if target_member is null then
    raise exception 'Select one of the approved household members';
  end if;

  insert into private.mealmate_sessions (user_id, household_id, member_id)
  values (current_user_id, target_household, target_member)
  on conflict (user_id) do update
    set household_id = excluded.household_id,
        member_id = excluded.member_id;

  return true;
end;
$$;
revoke all on function public.unlock_mealmate_household(text, text) from public, anon;
grant execute on function public.unlock_mealmate_household(text, text) to authenticated;
