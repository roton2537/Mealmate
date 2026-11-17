-- MealMate initial schema. Applied to Supabase migration initial_mealmate_schema plus index_expense_foreign_keys.
-- Shared household; all four authenticated members can see and manage the shared expense ledger.
-- No meal/consumption records are created.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table if not exists public.households (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name text not null,
  name_bn text not null,
  auth_user_id uuid unique references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint members_household_id_id_unique unique (household_id, id),
  constraint members_household_name_unique unique (household_id, name)
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  description text not null check (char_length(trim(description)) between 1 and 160),
  amount numeric(12,2) not null check (amount > 0),
  paid_by_member_id uuid not null,
  expense_date date not null default current_date,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint expenses_payer_in_same_household
    foreign key (household_id, paid_by_member_id)
    references public.members (household_id, id)
);

create index if not exists expenses_household_date_idx
  on public.expenses (household_id, expense_date desc, created_at desc);
create index if not exists members_auth_user_idx
  on public.members (auth_user_id) where auth_user_id is not null;
create index if not exists expenses_created_by_idx on public.expenses (created_by);
create index if not exists expenses_household_payer_idx on public.expenses (household_id, paid_by_member_id);

-- SECURITY DEFINER is limited to this non-exposed schema and this membership lookup.
-- It avoids recursive RLS when a member policy needs to verify group membership.
create or replace function private.is_mealmate_member(target_household uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.members m
    where m.household_id = target_household
      and m.auth_user_id = (select auth.uid())
  );
$$;
revoke all on function private.is_mealmate_member(uuid) from public;
grant execute on function private.is_mealmate_member(uuid) to authenticated;

create or replace function private.guard_expense_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.household_id is distinct from old.household_id
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Expense ownership and audit fields cannot be changed';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function private.guard_expense_update() from public;

drop trigger if exists guard_expense_update on public.expenses;
create trigger guard_expense_update
before update on public.expenses
for each row execute function private.guard_expense_update();

alter table public.households enable row level security;
alter table public.members enable row level security;
alter table public.expenses enable row level security;

drop policy if exists "Members can view their household" on public.households;
create policy "Members can view their household"
on public.households for select to authenticated
using (private.is_mealmate_member(id));

drop policy if exists "Members can view group members" on public.members;
create policy "Members can view group members"
on public.members for select to authenticated
using (private.is_mealmate_member(household_id));

drop policy if exists "Members can view shared expenses" on public.expenses;
create policy "Members can view shared expenses"
on public.expenses for select to authenticated
using (private.is_mealmate_member(household_id));

drop policy if exists "Members can add shared expenses" on public.expenses;
create policy "Members can add shared expenses"
on public.expenses for insert to authenticated
with check (
  private.is_mealmate_member(household_id)
  and created_by = (select auth.uid())
);

drop policy if exists "Members can update shared expenses" on public.expenses;
create policy "Members can update shared expenses"
on public.expenses for update to authenticated
using (private.is_mealmate_member(household_id))
with check (private.is_mealmate_member(household_id));

drop policy if exists "Members can delete shared expenses" on public.expenses;
create policy "Members can delete shared expenses"
on public.expenses for delete to authenticated
using (private.is_mealmate_member(household_id));

grant select on public.households, public.members to authenticated;
grant select, insert, update, delete on public.expenses to authenticated;

-- Seed the agreed group. auth_user_id stays NULL until each person's account is
-- verified and explicitly linked by an administrator; no account is auto-created.
with household as (
  insert into public.households (slug, name)
  values ('mealmate-shared', 'MealMate Shared Household')
  on conflict (slug) do update set name = excluded.name
  returning id
)
insert into public.members (household_id, name, name_bn)
select household.id, seed.name, seed.name_bn
from household
cross join (values
  ('MD ROTON MIAH', 'এমডি রোটন মিয়া'),
  ('AJIBUR RAHMAN', 'আজিবুর রহমান'),
  ('ROBIUL ISLAM', 'রবিউল ইসলাম'),
  ('HINDI', 'হিন্দি')
) as seed(name, name_bn)
on conflict (household_id, name) do update
set name_bn = excluded.name_bn;


-- Passwordless household access. See migration passwordless_household_access.
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
  constraint mealmate_sessions_member_fk foreign key (household_id, member_id)
    references public.members (household_id, id) on delete cascade
);
revoke all on private.mealmate_sessions from public, anon, authenticated;
create index if not exists mealmate_sessions_household_idx on private.mealmate_sessions (household_id);
create index if not exists mealmate_sessions_household_member_idx on private.mealmate_sessions (household_id, member_id);

insert into private.mealmate_access_codes (household_id, code_hash)
select id, encode(sha256(convert_to('MM-7KQ4-N9PX-3W8D-6R2V', 'UTF8')), 'hex')
from public.households where slug = 'mealmate-shared'
on conflict (household_id) do update set code_hash = excluded.code_hash;

create or replace function private.is_mealmate_member(target_household uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from private.mealmate_sessions s where s.household_id = target_household and s.user_id = (select auth.uid()))
    or exists (select 1 from public.members m where m.household_id = target_household and m.auth_user_id = (select auth.uid()));
$$;
revoke all on function private.is_mealmate_member(uuid) from public;
grant execute on function private.is_mealmate_member(uuid) to authenticated;

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

-- Resolve the household/member linked to the current authenticated device session.
-- The private SECURITY DEFINER lookup exposes only the caller's own session mapping.
create or replace function private.get_mealmate_session_context()
returns table(member_id uuid, household_id uuid)
language sql stable security definer set search_path = '' as $$
  select s.member_id, s.household_id
  from private.mealmate_sessions s
  where s.user_id = (select auth.uid())
  union all
  select m.id, m.household_id
  from public.members m
  where m.auth_user_id = (select auth.uid())
    and not exists (select 1 from private.mealmate_sessions s where s.user_id = (select auth.uid()));
$$;
revoke all on function private.get_mealmate_session_context() from public, anon;
grant execute on function private.get_mealmate_session_context() to authenticated;

create or replace function public.get_mealmate_session_context()
returns table(member_id uuid, household_id uuid)
language sql stable security invoker set search_path = '' as $$
  select * from private.get_mealmate_session_context();
$$;
revoke all on function public.get_mealmate_session_context() from public, anon;
grant execute on function public.get_mealmate_session_context() to authenticated;
