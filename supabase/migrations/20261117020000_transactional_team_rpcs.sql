-- MealMate transactional write RPCs.
-- Staged only on feature/multi-team-foundation. NOT applied to Supabase.
begin;

create or replace function public.create_team(p_name text, p_currency text default 'SAR')
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_team_id uuid;
  v_name text := trim(coalesce(p_name, ''));
  v_currency text := upper(trim(coalesce(p_currency, '')));
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if char_length(v_name) < 2 or char_length(v_name) > 80 then
    raise exception 'Team name must be 2 to 80 characters';
  end if;
  if v_currency !~ '^[A-Z]{3}$' then raise exception 'Currency must be a 3-letter ISO code'; end if;

  insert into public.teams(name, currency, owner_user_id)
  values (v_name, v_currency, auth.uid())
  returning id into v_team_id;

  insert into public.team_members(team_id, user_id, display_name, role)
  values (v_team_id, auth.uid(), coalesce(nullif(trim(auth.jwt()->>'email'), ''), 'Team owner'), 'owner');

  insert into public.team_audit_log(team_id, actor_user_id, entity_type, entity_id, action)
  values (v_team_id, auth.uid(), 'team', v_team_id, 'team_created');
  return v_team_id;
end;
$$;

create or replace function public.record_team_expense(
  p_team_id uuid,
  p_description text,
  p_category text,
  p_total_minor bigint,
  p_currency text,
  p_payer_member_id uuid,
  p_split_method text,
  p_occurred_on date,
  p_shares jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_expense_id uuid;
  v_currency text := upper(trim(coalesce(p_currency, '')));
  v_share_count integer;
  v_share_sum numeric;
  v_payer_user uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.is_active_team_member(p_team_id) then raise exception 'Active team membership required'; end if;
  if p_total_minor is null or p_total_minor <= 0 then raise exception 'Expense amount must be positive'; end if;
  if p_split_method not in ('equal','fixed','percentage') then raise exception 'Invalid split method'; end if;
  if p_occurred_on is null or p_occurred_on > current_date then raise exception 'Invalid expense date'; end if;
  if jsonb_typeof(p_shares) <> 'array' or jsonb_array_length(p_shares) = 0 then
    raise exception 'At least one share is required';
  end if;
  if char_length(trim(coalesce(p_description,''))) not between 1 and 160 then
    raise exception 'Description must be 1 to 160 characters';
  end if;

  select currency into strict v_currency from public.teams where id = p_team_id;
  if upper(trim(p_currency)) <> v_currency then raise exception 'Expense currency must match team currency'; end if;

  select user_id into v_payer_user
  from public.team_members
  where id = p_payer_member_id and team_id = p_team_id
    and joined_at::date <= p_occurred_on
    and (left_at is null or left_at::date >= p_occurred_on);
  if v_payer_user is null then raise exception 'Payer was not an active team member on expense date'; end if;

  -- Only a currently active member may submit. The payer may submit on behalf of the team.
  select count(*), coalesce(sum(s.share_minor),0)
    into v_share_count, v_share_sum
  from jsonb_to_recordset(p_shares) as s(member_id uuid, share_minor bigint)
  join public.team_members m on m.id = s.member_id
  where m.team_id = p_team_id
    and m.joined_at::date <= p_occurred_on
    and (m.left_at is null or m.left_at::date >= p_occurred_on)
    and s.share_minor >= 0;

  if v_share_count <> jsonb_array_length(p_shares) then
    raise exception 'Every participant must be a valid team member on the expense date';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_shares) as s(member_id uuid, share_minor bigint)
    group by s.member_id having count(*) > 1
  ) then raise exception 'Duplicate participants are not allowed'; end if;
  if exists (
    select 1 from jsonb_to_recordset(p_shares) as s(member_id uuid, share_minor bigint)
    where s.member_id is null or s.share_minor is null or s.share_minor < 0
  ) then raise exception 'Invalid share allocation'; end if;
  if v_share_sum <> p_total_minor then raise exception 'Shares must add up exactly to expense total'; end if;
  if not exists (
    select 1 from jsonb_to_recordset(p_shares) as s(member_id uuid, share_minor bigint)
    where s.member_id = p_payer_member_id
  ) then raise exception 'Payer must be included in expense participants'; end if;

  insert into public.expenses(team_id, description, category, total_minor, currency,
    payer_member_id, split_method, occurred_on, created_by)
  values (p_team_id, trim(p_description), coalesce(nullif(trim(p_category),''),'other'),
    p_total_minor, v_currency, p_payer_member_id, p_split_method, p_occurred_on, auth.uid())
  returning id into v_expense_id;

  insert into public.expense_shares(expense_id, team_id, member_id, share_minor)
  select v_expense_id, p_team_id, s.member_id, s.share_minor
  from jsonb_to_recordset(p_shares) as s(member_id uuid, share_minor bigint);

  insert into public.team_audit_log(team_id, actor_user_id, entity_type, entity_id, action, details)
  values (p_team_id, auth.uid(), 'expense', v_expense_id, 'expense_created',
    jsonb_build_object('total_minor', p_total_minor, 'currency', v_currency, 'occurred_on', p_occurred_on));
  return v_expense_id;
end;
$$;

create or replace function public.create_team_settlement(
  p_team_id uuid,
  p_payer_member_id uuid,
  p_recipient_member_id uuid,
  p_amount_minor bigint
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_id uuid;
  v_currency text;
  v_payer_user uuid;
  v_recipient_user uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_amount_minor is null or p_amount_minor <= 0 then raise exception 'Settlement amount must be positive'; end if;
  select currency into strict v_currency from public.teams where id = p_team_id;
  select user_id into v_payer_user from public.team_members
    where id = p_payer_member_id and team_id = p_team_id and left_at is null;
  select user_id into v_recipient_user from public.team_members
    where id = p_recipient_member_id and team_id = p_team_id and left_at is null;
  if v_payer_user is null or v_recipient_user is null then raise exception 'Both parties must be active team members'; end if;
  if p_payer_member_id = p_recipient_member_id or v_payer_user = v_recipient_user then
    raise exception 'Settlement parties must be different users';
  end if;
  if auth.uid() <> v_payer_user then raise exception 'Only the paying party can create this settlement'; end if;

  insert into public.settlements(team_id, payer_member_id, recipient_member_id, amount_minor,
    currency, created_by)
  values (p_team_id, p_payer_member_id, p_recipient_member_id, p_amount_minor, v_currency, auth.uid())
  returning id into v_id;

  insert into public.team_audit_log(team_id, actor_user_id, entity_type, entity_id, action)
  values (p_team_id, auth.uid(), 'settlement', v_id, 'settlement_created');
  return v_id;
end;
$$;

create or replace function public.confirm_team_settlement(p_settlement_id uuid)
returns text
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_row public.settlements%rowtype;
  v_member_id uuid;
  v_new_status text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into strict v_row from public.settlements where id = p_settlement_id for update;
  if v_row.status <> 'pending' then raise exception 'Only pending settlements can be confirmed'; end if;

  select id into v_member_id from public.team_members
    where team_id = v_row.team_id and user_id = auth.uid() and left_at is null;
  if v_member_id is null then raise exception 'Active team membership required'; end if;

  if v_member_id = v_row.payer_member_id then
    update public.settlements set payer_confirmed_at = coalesce(payer_confirmed_at, now())
    where id = p_settlement_id;
  elsif v_member_id = v_row.recipient_member_id then
    update public.settlements set recipient_confirmed_at = coalesce(recipient_confirmed_at, now())
    where id = p_settlement_id;
  else
    raise exception 'Only settlement parties can confirm';
  end if;

  update public.settlements
    set status = case
      when payer_confirmed_at is not null and recipient_confirmed_at is not null then 'completed'
      else 'pending'
    end,
    completed_at = case
      when payer_confirmed_at is not null and recipient_confirmed_at is not null then coalesce(completed_at, now())
      else null
    end
  where id = p_settlement_id
  returning status into v_new_status;

  insert into public.team_audit_log(team_id, actor_user_id, entity_type, entity_id, action)
  values (v_row.team_id, auth.uid(), 'settlement', p_settlement_id,
    case when v_new_status = 'completed' then 'settlement_completed' else 'settlement_confirmed_by_one_party' end);
  return v_new_status;
end;
$$;

revoke all on function public.create_team(text,text) from public, anon;
revoke all on function public.record_team_expense(uuid,text,text,bigint,text,uuid,text,date,jsonb) from public, anon;
revoke all on function public.create_team_settlement(uuid,uuid,uuid,bigint) from public, anon;
revoke all on function public.confirm_team_settlement(uuid) from public, anon;
grant execute on function public.create_team(text,text) to authenticated;
grant execute on function public.record_team_expense(uuid,text,text,bigint,text,uuid,text,date,jsonb) to authenticated;
grant execute on function public.create_team_settlement(uuid,uuid,uuid,bigint) to authenticated;
grant execute on function public.confirm_team_settlement(uuid) to authenticated;

commit;
