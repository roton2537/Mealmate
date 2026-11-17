-- Final authorization and settlement invariants for the multi-team model.
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
  v_display_name text := coalesce(
    nullif(trim(auth.jwt()->'user_metadata'->>'display_name'), ''),
    nullif(trim(auth.jwt()->>'email'), ''),
    'Team owner'
  );
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if char_length(v_name) < 2 or char_length(v_name) > 80 then
    raise exception 'Team name must be 2 to 80 characters';
  end if;
  if v_currency !~ '^[A-Z]{3}$' then raise exception 'Currency must be a 3-letter ISO code'; end if;
  insert into public.mm_teams(name,currency,owner_user_id) values(v_name,v_currency,auth.uid()) returning id into v_team_id;
  insert into public.mm_team_members(team_id,user_id,display_name,role)
  values(v_team_id,auth.uid(),v_display_name,'owner');
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
  values(v_team_id,auth.uid(),'team',v_team_id,'team_created');
  return v_team_id;
end;
$$;

create or replace function public.create_team_invitation(
  p_team_id uuid,
  p_invited_email text default null,
  p_role text default 'member',
  p_expires_in_days integer default 7
)
returns text
language plpgsql
security definer
set search_path = public, auth, extensions, pg_temp
as $$
declare
  v_token text;
  v_email text := nullif(lower(trim(coalesce(p_invited_email,''))), '');
  v_role text := coalesce(p_role,'member');
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.mm_has_team_role(p_team_id,array['owner','admin']) then
    raise exception 'Only team owners and admins can invite members';
  end if;
  if v_role='admin' and not public.mm_has_team_role(p_team_id,array['owner']) then
    raise exception 'Only the team owner can appoint admins';
  end if;
  if v_email is not null and v_email !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$' then
    raise exception 'Invalid invitation email';
  end if;
  if v_role not in ('admin','member') then raise exception 'Invalid invitation role'; end if;
  if p_expires_in_days is null or p_expires_in_days not between 1 and 30 then raise exception 'Invitation expiry must be 1 to 30 days'; end if;
  v_token := encode(gen_random_bytes(32),'hex');
  insert into public.mm_team_invitations(team_id,created_by,token_hash,invited_email,role,expires_at)
  values(p_team_id,auth.uid(),encode(digest(v_token,'sha256'),'hex'),v_email,v_role,now()+make_interval(days=>p_expires_in_days));
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,action,details)
  values(p_team_id,auth.uid(),'invitation','invitation_created',jsonb_build_object('invited_email',v_email,'role',v_role,'expires_in_days',p_expires_in_days));
  return v_token;
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
  v_payer_paid numeric;
  v_payer_share numeric;
  v_recipient_paid numeric;
  v_recipient_share numeric;
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
  v_payer_net:=v_payer_paid-v_payer_share;
  v_recipient_net:=v_recipient_paid-v_recipient_share;
  if v_payer_net>=0 or v_recipient_net<=0 then raise exception 'Settlement parties do not have an outstanding balance in this direction'; end if;
  if p_amount_minor>least(abs(v_payer_net),v_recipient_net) then raise exception 'Settlement exceeds the outstanding balance'; end if;

  insert into public.mm_settlements(team_id,payer_member_id,recipient_member_id,amount_minor,currency,created_by)
  values(p_team_id,p_payer_member_id,p_recipient_member_id,p_amount_minor,v_currency,auth.uid()) returning id into v_id;
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
  values(p_team_id,auth.uid(),'settlement',v_id,'settlement_created');
  return v_id;
end;
$$;

revoke all on function public.create_team(text,text) from public,anon;
revoke all on function public.create_team_invitation(uuid,text,text,integer) from public,anon;
revoke all on function public.create_team_settlement(uuid,uuid,uuid,bigint) from public,anon;
grant execute on function public.create_team(text,text) to authenticated;
grant execute on function public.create_team_invitation(uuid,text,text,integer) to authenticated;
grant execute on function public.create_team_settlement(uuid,uuid,uuid,bigint) to authenticated;

commit;
