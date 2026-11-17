-- MealMate multi-team schema draft.
-- IMPORTANT: staged on the GitHub development branch only; NOT applied to Supabase.
begin;

create extension if not exists pgcrypto;

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 80),
  currency char(3) not null default 'SAR',
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  archived_at timestamptz
);

create table if not exists public.team_members (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  role text not null default 'member' check (role in ('owner','admin','member')),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  created_at timestamptz not null default now(),
  unique (team_id, user_id),
  check (left_at is null or left_at >= joined_at)
);

create unique index if not exists team_members_one_active_user
  on public.team_members(team_id, user_id) where left_at is null;
create index if not exists team_members_user_active
  on public.team_members(user_id, team_id) where left_at is null;

create table if not exists public.team_invitations (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  token_hash text not null unique,
  invited_email text,
  role text not null default 'member' check (role in ('admin','member')),
  expires_at timestamptz not null,
  max_uses integer not null default 1 check (max_uses between 1 and 100),
  uses integer not null default 0 check (uses >= 0 and uses <= max_uses),
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.expenses (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete restrict,
  description text not null check (char_length(trim(description)) between 1 and 160),
  category text not null default 'other',
  total_minor bigint not null check (total_minor > 0),
  currency char(3) not null,
  payer_member_id uuid not null references public.team_members(id) on delete restrict,
  split_method text not null check (split_method in ('equal','fixed','percentage')),
  occurred_on date not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  voided_at timestamptz,
  unique (id, team_id)
);
create index if not exists expenses_team_date on public.expenses(team_id, occurred_on desc);

create table if not exists public.expense_shares (
  id uuid primary key default gen_random_uuid(),
  expense_id uuid not null,
  team_id uuid not null,
  member_id uuid not null references public.team_members(id) on delete restrict,
  share_minor bigint not null check (share_minor >= 0),
  created_at timestamptz not null default now(),
  foreign key (expense_id, team_id) references public.expenses(id, team_id) on delete restrict,
  unique (expense_id, member_id)
);
create index if not exists expense_shares_team_member on public.expense_shares(team_id, member_id);

create table if not exists public.settlements (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete restrict,
  payer_member_id uuid not null references public.team_members(id) on delete restrict,
  recipient_member_id uuid not null references public.team_members(id) on delete restrict,
  amount_minor bigint not null check (amount_minor > 0),
  currency char(3) not null,
  status text not null default 'pending' check (status in ('pending','completed','disputed','cancelled')),
  payer_confirmed_at timestamptz,
  recipient_confirmed_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check (payer_member_id <> recipient_member_id),
  check ((status <> 'completed') or
    (payer_confirmed_at is not null and recipient_confirmed_at is not null and completed_at is not null))
);
create index if not exists settlements_team_status on public.settlements(team_id, status, created_at desc);

create table if not exists public.team_audit_log (
  id bigint generated always as identity primary key,
  team_id uuid not null references public.teams(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  entity_type text not null,
  entity_id uuid,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists team_audit_team_created on public.team_audit_log(team_id, created_at desc);

create or replace function public.is_active_team_member(p_team_id uuid)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.team_members m
    where m.team_id = p_team_id and m.user_id = auth.uid() and m.left_at is null
  );
$$;

create or replace function public.has_team_role(p_team_id uuid, p_roles text[])
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.team_members m
    where m.team_id = p_team_id and m.user_id = auth.uid()
      and m.left_at is null and m.role = any(p_roles)
  );
$$;

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.team_invitations enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_shares enable row level security;
alter table public.settlements enable row level security;
alter table public.team_audit_log enable row level security;

-- Teams can only be read by active members. Team creation and owner membership
-- must be performed together by a trusted RPC in the next migration.
create policy teams_select_member on public.teams
  for select to authenticated using (public.is_active_team_member(id));

create policy members_select_team on public.team_members
  for select to authenticated using (public.is_active_team_member(team_id));

create policy invitations_select_admin on public.team_invitations
  for select to authenticated using (public.has_team_role(team_id, array['owner','admin']));

create policy expenses_select_member on public.expenses
  for select to authenticated using (public.is_active_team_member(team_id));
create policy shares_select_member on public.expense_shares
  for select to authenticated using (public.is_active_team_member(team_id));
create policy settlements_select_member on public.settlements
  for select to authenticated using (public.is_active_team_member(team_id));
create policy audit_select_admin on public.team_audit_log
  for select to authenticated using (public.has_team_role(team_id, array['owner','admin']));

-- No direct client INSERT/UPDATE/DELETE policies are intentionally granted yet.
-- All writes must be added as validated, transactional RPCs that:
-- 1. verify team membership and role,
-- 2. validate effective membership dates and selected participants,
-- 3. write immutable share snapshots whose sum equals total_minor,
-- 4. append an audit event,
-- 5. atomically complete settlements only after both confirmations.

grant execute on function public.is_active_team_member(uuid) to authenticated;
grant execute on function public.has_team_role(uuid, text[]) to authenticated;

commit;
