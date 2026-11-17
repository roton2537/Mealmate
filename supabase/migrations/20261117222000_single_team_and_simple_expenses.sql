create or replace function private.enforce_single_active_team_membership()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.left_at is null and exists (
    select 1 from public.mm_team_members m
    where m.user_id = new.user_id
      and m.left_at is null
      and m.id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    raise exception 'One person can belong to only one active MealMate team. Contact the Admin if you need to recover your existing membership.';
  end if;
  return new;
end;
$function$;

drop trigger if exists mm_single_active_team_membership on public.mm_team_members;
create trigger mm_single_active_team_membership
before insert or update of user_id, team_id, left_at on public.mm_team_members
for each row execute function private.enforce_single_active_team_membership();

create or replace function private.redeem_team_invitation(p_token text,p_display_name text)
returns uuid
language plpgsql
security definer
set search_path to 'public','auth','extensions','pg_temp'
as $function$
declare
  v_invite public.mm_team_invitations%rowtype;
  v_request_id uuid;
  v_email text:=lower(coalesce(auth.jwt()->>'email',''));
  v_name text:=trim(coalesce(p_display_name,''));
begin
  if auth.uid() is null then raise exception 'A device session is required'; end if;
  if coalesce((auth.jwt()->>'is_anonymous')::boolean,false) is not true then
    raise exception 'Member invitations must be opened in a member device session';
  end if;
  if p_token is null or length(trim(p_token))<32 then raise exception 'Invalid invitation code'; end if;
  if char_length(v_name) not between 1 and 80 then raise exception 'Name must be 1 to 80 characters'; end if;
  if exists(select 1 from public.mm_team_members where user_id=auth.uid() and left_at is null) then
    raise exception 'This device already belongs to a team. Use your Admin-issued recovery link to restore an existing membership.';
  end if;
  if exists(select 1 from public.mm_team_join_requests where user_id=auth.uid() and status='pending') then
    raise exception 'This device already has a pending team approval request.';
  end if;
  select * into v_invite from public.mm_team_invitations
  where token_hash=encode(extensions.digest(trim(p_token),'sha256'),'hex') for update;
  if not found or v_invite.revoked_at is not null or v_invite.expires_at<=now() or v_invite.uses>=v_invite.max_uses then
    raise exception 'Invitation is invalid, expired, or already used';
  end if;
  if v_invite.invited_email is not null and v_invite.invited_email<>v_email then
    raise exception 'This invitation belongs to a different email address';
  end if;
  insert into public.mm_team_join_requests(team_id,invitation_id,user_id,display_name,requested_role,status)
  values(v_invite.team_id,v_invite.id,auth.uid(),v_name,'member','pending') returning id into v_request_id;
  update public.mm_team_invitations set uses=uses+1 where id=v_invite.id;
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
  values(v_invite.team_id,auth.uid(),'join_request',v_request_id,'member_join_requested');
  return v_request_id;
end;
$function$;

create or replace function private.record_team_expense_simple(
  p_team_id uuid,p_description text,p_total_minor bigint,p_currency text,
  p_payer_member_id uuid,p_occurred_on date
) returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_expense_id uuid;
  v_currency text;
  v_payer_user uuid;
  v_count bigint;
begin
  if auth.uid() is null then raise exception 'A device session is required'; end if;
  if not private.mm_is_active_team_member(p_team_id) then raise exception 'Active team membership required'; end if;
  if p_total_minor is null or p_total_minor<=0 then raise exception 'Expense amount must be positive'; end if;
  if p_occurred_on is null or p_occurred_on>current_date then raise exception 'Invalid expense date'; end if;
  if char_length(trim(coalesce(p_description,''))) not between 1 and 160 then raise exception 'Description must be 1 to 160 characters'; end if;
  select currency into strict v_currency from public.mm_teams where id=p_team_id;
  if p_currency is null or upper(trim(p_currency))<>v_currency then raise exception 'Expense currency must match team currency'; end if;
  select user_id into v_payer_user from public.mm_team_members
  where id=p_payer_member_id and team_id=p_team_id and left_at is null and joined_at::date<=p_occurred_on;
  if v_payer_user is null or v_payer_user<>auth.uid() then raise exception 'You can record expenses only for yourself'; end if;
  select count(*) into v_count from public.mm_team_members
  where team_id=p_team_id and joined_at::date<=p_occurred_on
    and (left_at is null or left_at::date>=p_occurred_on);
  if v_count=0 then raise exception 'No eligible members existed on the expense date'; end if;
  insert into public.mm_expenses(team_id,description,category,total_minor,currency,payer_member_id,split_method,occurred_on,created_by)
  values(p_team_id,trim(p_description),'other',p_total_minor,v_currency,p_payer_member_id,'equal',p_occurred_on,auth.uid())
  returning id into v_expense_id;
  insert into public.mm_expense_shares(expense_id,team_id,member_id,share_minor)
  select v_expense_id,p_team_id,m.id,
    (p_total_minor / v_count) + case when row_number() over(order by m.joined_at,m.id)<=mod(p_total_minor,v_count) then 1 else 0 end
  from public.mm_team_members m
  where m.team_id=p_team_id and m.joined_at::date<=p_occurred_on
    and (m.left_at is null or m.left_at::date>=p_occurred_on)
  order by m.joined_at,m.id;
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action,details)
  values(p_team_id,auth.uid(),'expense',v_expense_id,'expense_created',
    jsonb_build_object('total_minor',p_total_minor,'currency',v_currency,'occurred_on',p_occurred_on,'split_method','equal'));
  return v_expense_id;
end;
$function$;

create or replace function public.record_team_expense_simple(
  p_team_id uuid,p_description text,p_total_minor bigint,p_currency text,
  p_payer_member_id uuid,p_occurred_on date
) returns uuid
language sql
security definer
set search_path to ''
as $function$
  select private.record_team_expense_simple(p_team_id,p_description,p_total_minor,p_currency,p_payer_member_id,p_occurred_on);
$function$;

revoke all on function public.record_team_expense(uuid,text,text,bigint,text,uuid,text,date,jsonb) from public,anon,authenticated;
revoke all on function private.record_team_expense(uuid,text,text,bigint,text,uuid,text,date,jsonb) from public,anon,authenticated;
revoke all on function public.record_team_expense_simple(uuid,text,bigint,text,uuid,date) from public,anon;
grant execute on function public.record_team_expense_simple(uuid,text,bigint,text,uuid,date) to authenticated;
revoke all on function private.record_team_expense_simple(uuid,text,bigint,text,uuid,date) from public,anon,authenticated;
