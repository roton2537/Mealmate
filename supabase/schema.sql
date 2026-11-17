-- MealMate initial schema blueprint. Review before applying to a Supabase project.
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
