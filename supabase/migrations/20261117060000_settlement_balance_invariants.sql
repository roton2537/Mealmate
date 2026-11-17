-- Keep settlement validation aligned with existing pending/completed transfers.
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
  v_payer_paid numeric;
  v_payer_share numeric;
  v_recipient_paid numeric;
  v_recipient_share numeric;
  v_payer_sent numeric;
  v_payer_received numeric;
  v_recipient_sent numeric;
  v_recipient_received numeric;
  v_payer_net numeric;
  v_recipient_net numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_amount_minor is null or p_amount_minor <= 0 then raise exception 'Settlement amount must be positive'; end if;
  select currency into strict v_currency from public.mm_teams where id=p_team_id;
  select user_id into v_payer_user from public.mm_team_members where id=p_payer_member_id and team_id=p_team_id and left_at is null;
  select user_id into v_recipient_user from public.mm_team_members where id=p_recipient_member_id and team_id=p_team_id and left_at is null;
  if v_payer_user is null or v_recipient_user is null then raise exception 'Both parties must be active team members'; end if;
  if p_payer_member_id=p_recipient_member_id or v_payer_user=v_recipient_user then raise exception 'Settlement parties must be different users'; end if;
  if auth.uid()<>v_payer_user then raise exception 'Only the paying party can create this settlement'; end if;

  select coalesce(sum(total_minor),0) into v_payer_paid from public.mm_expenses where team_id=p_team_id and payer_member_id=p_payer_member_id and voided_at is null;
  select coalesce(sum(share_minor),0) into v_payer_share from public.mm_expense_shares where team_id=p_team_id and member_id=p_payer_member_id;
  select coalesce(sum(total_minor),0) into v_recipient_paid from public.mm_expenses where team_id=p_team_id and payer_member_id=p_recipient_member_id and voided_at is null;
  select coalesce(sum(share_minor),0) into v_recipient_share from public.mm_expense_shares where team_id=p_team_id and member_id=p_recipient_member_id;

  select coalesce(sum(amount_minor) filter(where payer_member_id=p_payer_member_id),0),
         coalesce(sum(amount_minor) filter(where recipient_member_id=p_payer_member_id),0)
    into v_payer_sent,v_payer_received
    from public.mm_settlements where team_id=p_team_id and status in ('pending','completed');
  select coalesce(sum(amount_minor) filter(where payer_member_id=p_recipient_member_id),0),
         coalesce(sum(amount_minor) filter(where recipient_member_id=p_recipient_member_id),0)
    into v_recipient_sent,v_recipient_received
    from public.mm_settlements where team_id=p_team_id and status in ('pending','completed');

  v_payer_net:=v_payer_paid-v_payer_share+v_payer_sent-v_payer_received;
  v_recipient_net:=v_recipient_paid-v_recipient_share+v_recipient_sent-v_recipient_received;
  if v_payer_net>=0 or v_recipient_net<=0 then raise exception 'Settlement parties do not have an outstanding balance in this direction'; end if;
  if p_amount_minor>least(abs(v_payer_net),v_recipient_net) then raise exception 'Settlement exceeds the outstanding balance'; end if;

  insert into public.mm_settlements(team_id,payer_member_id,recipient_member_id,amount_minor,currency,created_by)
  values(p_team_id,p_payer_member_id,p_recipient_member_id,p_amount_minor,v_currency,auth.uid()) returning id into v_id;
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
  values(p_team_id,auth.uid(),'settlement',v_id,'settlement_created');
  return v_id;
end;
$$;

revoke all on function public.create_team_settlement(uuid,uuid,uuid,bigint) from public,anon;
grant execute on function public.create_team_settlement(uuid,uuid,uuid,bigint) to authenticated;
