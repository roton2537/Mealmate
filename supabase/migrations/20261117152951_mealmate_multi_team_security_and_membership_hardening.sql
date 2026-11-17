-- Reject anonymous Auth identities, hide security-definer membership helpers from the exposed API,
-- preserve historical membership periods on re-join, and make invite links multi-use.
begin;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.mm_is_active_team_member(p_team_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false
     and exists (
       select 1 from public.mm_team_members m
       where m.team_id = p_team_id and m.user_id = auth.uid() and m.left_at is null
     );
$$;

create or replace function private.mm_has_team_role(p_team_id uuid, p_roles text[])
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select auth.uid() is not null
     and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false
     and exists (
       select 1 from public.mm_team_members m
       where m.team_id = p_team_id and m.user_id = auth.uid()
         and m.left_at is null and m.role = any(p_roles)
     );
$$;

revoke all on function private.mm_is_active_team_member(uuid) from public, anon;
revoke all on function private.mm_has_team_role(uuid,text[]) from public, anon;
grant execute on function private.mm_is_active_team_member(uuid) to authenticated;
grant execute on function private.mm_has_team_role(uuid,text[]) to authenticated;

drop policy if exists teams_select_member on public.mm_teams;
drop policy if exists members_select_team on public.mm_team_members;
drop policy if exists invitations_select_admin on public.mm_team_invitations;
drop policy if exists expenses_select_member on public.mm_expenses;
drop policy if exists shares_select_member on public.mm_expense_shares;
drop policy if exists settlements_select_member on public.mm_settlements;
drop policy if exists audit_select_admin on public.mm_team_audit_log;

create policy teams_select_member on public.mm_teams for select to authenticated
  using (private.mm_is_active_team_member(id));
create policy members_select_team on public.mm_team_members for select to authenticated
  using (private.mm_is_active_team_member(team_id));
create policy invitations_select_admin on public.mm_team_invitations for select to authenticated
  using (private.mm_has_team_role(team_id,array['owner','admin']));
create policy expenses_select_member on public.mm_expenses for select to authenticated
  using (private.mm_is_active_team_member(team_id));
create policy shares_select_member on public.mm_expense_shares for select to authenticated
  using (private.mm_is_active_team_member(team_id));
create policy settlements_select_member on public.mm_settlements for select to authenticated
  using (private.mm_is_active_team_member(team_id));
create policy audit_select_admin on public.mm_team_audit_log for select to authenticated
  using (private.mm_has_team_role(team_id,array['owner','admin']));

-- Membership periods are separate rows. Only one may be active at a time.
alter table public.mm_team_members drop constraint if exists mm_team_members_team_id_user_id_key;
create unique index if not exists team_members_one_active_user
  on public.mm_team_members(team_id,user_id) where left_at is null;
alter table public.mm_team_invitations alter column max_uses set default 100;

create or replace function public.mm_is_active_team_member(p_team_id uuid)
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$ select private.mm_is_active_team_member(p_team_id); $$;
create or replace function public.mm_has_team_role(p_team_id uuid,p_roles text[])
returns boolean language sql stable security definer
set search_path = public, pg_temp
as $$ select private.mm_has_team_role(p_team_id,p_roles); $$;

revoke all on function public.mm_is_active_team_member(uuid) from public, anon, authenticated;
revoke all on function public.mm_has_team_role(uuid,text[]) from public, anon, authenticated;

create or replace function public.create_team(p_name text,p_currency text default 'SAR')
returns uuid language plpgsql security definer
set search_path = public, auth, pg_temp
as $$
declare v_team_id uuid; v_name text:=trim(coalesce(p_name,'')); v_currency text:=upper(trim(coalesce(p_currency,'')));
v_display_name text:=coalesce(nullif(trim(auth.jwt()->'user_metadata'->>'display_name'),''),nullif(trim(auth.jwt()->>'email'),''),'Team owner');
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'A verified email/password account is required'; end if;
 if char_length(v_name) not between 2 and 80 then raise exception 'Team name must be 2 to 80 characters'; end if;
 if v_currency !~ '^[A-Z]{3}$' then raise exception 'Currency must be a 3-letter ISO code'; end if;
 insert into public.mm_teams(name,currency,owner_user_id) values(v_name,v_currency,auth.uid()) returning id into v_team_id;
 insert into public.mm_team_members(team_id,user_id,display_name,role) values(v_team_id,auth.uid(),v_display_name,'owner');
 insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action) values(v_team_id,auth.uid(),'team',v_team_id,'team_created');
 return v_team_id;
end; $$;

create or replace function public.record_team_expense(
 p_team_id uuid,p_description text,p_category text,p_total_minor bigint,p_currency text,
 p_payer_member_id uuid,p_split_method text,p_occurred_on date,p_shares jsonb)
returns uuid language plpgsql security definer
set search_path = public, auth, pg_temp
as $$
declare v_expense_id uuid; v_currency text:=upper(trim(coalesce(p_currency,''))); v_share_count integer;
v_share_sum numeric; v_payer_user uuid;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'A verified email/password account is required'; end if;
 if not private.mm_is_active_team_member(p_team_id) then raise exception 'Active team membership required'; end if;
 if p_total_minor is null or p_total_minor<=0 then raise exception 'Expense amount must be positive'; end if;
 if p_split_method is null or p_split_method not in ('equal','fixed','percentage') then raise exception 'Invalid split method'; end if;
 if p_occurred_on is null or p_occurred_on>current_date then raise exception 'Invalid expense date'; end if;
 if p_shares is null or jsonb_typeof(p_shares) is distinct from 'array' or jsonb_array_length(p_shares)=0 then raise exception 'At least one share is required'; end if;
 if char_length(trim(coalesce(p_description,''))) not between 1 and 160 then raise exception 'Description must be 1 to 160 characters'; end if;
 select currency into strict v_currency from public.mm_teams where id=p_team_id;
 if p_currency is null or upper(trim(p_currency))<>v_currency then raise exception 'Expense currency must match team currency'; end if;
 select user_id into v_payer_user from public.mm_team_members where id=p_payer_member_id and team_id=p_team_id
 and joined_at::date<=p_occurred_on and (left_at is null or left_at::date>=p_occurred_on);
 if v_payer_user is null then raise exception 'Payer was not an active team member on expense date'; end if;
 select count(*),coalesce(sum(s.share_minor),0) into v_share_count,v_share_sum
 from jsonb_to_recordset(p_shares) as s(member_id uuid,share_minor bigint)
 join public.mm_team_members m on m.id=s.member_id
 where m.team_id=p_team_id and m.joined_at::date<=p_occurred_on
 and (m.left_at is null or m.left_at::date>=p_occurred_on) and s.share_minor>=0;
 if v_share_count<>jsonb_array_length(p_shares) then raise exception 'Every participant must be a valid team member on the expense date'; end if;
 if exists(select 1 from jsonb_to_recordset(p_shares) as s(member_id uuid,share_minor bigint) group by s.member_id having count(*)>1) then raise exception 'Duplicate participants are not allowed'; end if;
 if exists(select 1 from jsonb_to_recordset(p_shares) as s(member_id uuid,share_minor bigint) where s.member_id is null or s.share_minor is null or s.share_minor<0) then raise exception 'Invalid share allocation'; end if;
 if v_share_sum<>p_total_minor then raise exception 'Shares must add up exactly to expense total'; end if;
 if not exists(select 1 from jsonb_to_recordset(p_shares) as s(member_id uuid,share_minor bigint) where s.member_id=p_payer_member_id) then raise exception 'Payer must be included in expense participants'; end if;
 insert into public.mm_expenses(team_id,description,category,total_minor,currency,payer_member_id,split_method,occurred_on,created_by)
 values(p_team_id,trim(p_description),coalesce(nullif(trim(p_category),''),'other'),p_total_minor,v_currency,p_payer_member_id,p_split_method,p_occurred_on,auth.uid()) returning id into v_expense_id;
 insert into public.mm_expense_shares(expense_id,team_id,member_id,share_minor)
 select v_expense_id,p_team_id,s.member_id,s.share_minor from jsonb_to_recordset(p_shares) as s(member_id uuid,share_minor bigint);
 insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action,details)
 values(p_team_id,auth.uid(),'expense',v_expense_id,'expense_created',jsonb_build_object('total_minor',p_total_minor,'currency',v_currency,'occurred_on',p_occurred_on));
 return v_expense_id;
end; $$;

create or replace function public.create_team_invitation(p_team_id uuid,p_invited_email text default null,p_role text default 'member',p_expires_in_days integer default 7)
returns text language plpgsql security definer
set search_path = public, auth, extensions, pg_temp
as $$
declare v_token text; v_email text:=nullif(lower(trim(coalesce(p_invited_email,''))), ''); v_role text:=coalesce(p_role,'member');
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'A verified email/password account is required'; end if;
 if not private.mm_has_team_role(p_team_id,array['owner','admin']) then raise exception 'Only team owners and admins can invite members'; end if;
 if v_role='admin' and not private.mm_has_team_role(p_team_id,array['owner']) then raise exception 'Only the team owner can appoint admins'; end if;
 if v_email is not null and v_email !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$' then raise exception 'Invalid invitation email'; end if;
 if v_role not in ('admin','member') then raise exception 'Invalid invitation role'; end if;
 if p_expires_in_days is null or p_expires_in_days not between 1 and 30 then raise exception 'Invitation expiry must be 1 to 30 days'; end if;
 v_token:=encode(extensions.gen_random_bytes(32),'hex');
 insert into public.mm_team_invitations(team_id,created_by,token_hash,invited_email,role,expires_at,max_uses)
 values(p_team_id,auth.uid(),encode(extensions.digest(v_token,'sha256'),'hex'),v_email,v_role,now()+make_interval(days=>p_expires_in_days),100);
 insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,action,details)
 values(p_team_id,auth.uid(),'invitation','invitation_created',jsonb_build_object('invited_email',v_email,'role',v_role,'expires_in_days',p_expires_in_days));
 return v_token;
end; $$;

create or replace function public.redeem_team_invitation(p_token text,p_display_name text)
returns uuid language plpgsql security definer
set search_path = public, auth, extensions, pg_temp
as $$
declare v_invite public.mm_team_invitations%rowtype; v_team_member_id uuid;
v_email text:=lower(coalesce(auth.jwt()->>'email','')); v_name text:=trim(coalesce(p_display_name,''));
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'A verified email/password account is required'; end if;
 if p_token is null or length(trim(p_token))<32 then raise exception 'Invalid invitation code'; end if;
 if char_length(v_name) not between 1 and 80 then raise exception 'Name must be 1 to 80 characters'; end if;
 select * into v_invite from public.mm_team_invitations where token_hash=encode(extensions.digest(trim(p_token),'sha256'),'hex') for update;
 if not found or v_invite.revoked_at is not null or v_invite.expires_at<=now() or v_invite.uses>=v_invite.max_uses then raise exception 'Invitation is invalid, expired, or already used'; end if;
 if v_invite.invited_email is not null and v_invite.invited_email<>v_email then raise exception 'This invitation belongs to a different email address'; end if;
 if exists(select 1 from public.mm_team_members where team_id=v_invite.team_id and user_id=auth.uid() and left_at is null) then raise exception 'You are already an active member of this team'; end if;
 insert into public.mm_team_members(team_id,user_id,display_name,role) values(v_invite.team_id,auth.uid(),v_name,v_invite.role) returning id into v_team_member_id;
 update public.mm_team_invitations set uses=uses+1 where id=v_invite.id;
 insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action) values(v_invite.team_id,auth.uid(),'member',v_team_member_id,'member_joined_via_invitation');
 return v_team_member_id;
end; $$;

create or replace function public.confirm_team_settlement(p_settlement_id uuid)
returns text language plpgsql security definer
set search_path = public, auth, pg_temp
as $$
declare v_row public.mm_settlements%rowtype; v_member_id uuid; v_payer_confirmed timestamptz; v_recipient_confirmed timestamptz; v_new_status text;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'A verified email/password account is required'; end if;
 select * into strict v_row from public.mm_settlements where id=p_settlement_id for update;
 if v_row.status<>'pending' then raise exception 'Only pending settlements can be confirmed'; end if;
 select id into v_member_id from public.mm_team_members where team_id=v_row.team_id and user_id=auth.uid() and left_at is null;
 if v_member_id is null then raise exception 'Active team membership required'; end if;
 v_payer_confirmed:=v_row.payer_confirmed_at; v_recipient_confirmed:=v_row.recipient_confirmed_at;
 if v_member_id=v_row.payer_member_id then v_payer_confirmed:=coalesce(v_payer_confirmed,now());
 elsif v_member_id=v_row.recipient_member_id then v_recipient_confirmed:=coalesce(v_recipient_confirmed,now());
 else raise exception 'Only settlement parties can confirm'; end if;
 v_new_status:=case when v_payer_confirmed is not null and v_recipient_confirmed is not null then 'completed' else 'pending' end;
 update public.mm_settlements set payer_confirmed_at=v_payer_confirmed,recipient_confirmed_at=v_recipient_confirmed,status=v_new_status,
 completed_at=case when v_new_status='completed' then coalesce(completed_at,now()) else null end where id=p_settlement_id;
 insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
 values(v_row.team_id,auth.uid(),'settlement',p_settlement_id,case when v_new_status='completed' then 'settlement_completed' else 'settlement_confirmed_by_one_party' end);
 return v_new_status;
end; $$;

create or replace function public.manage_team_member(p_member_id uuid,p_action text,p_role text default null)
returns void language plpgsql security definer
set search_path = public, auth, pg_temp
as $$
declare v_member public.mm_team_members%rowtype; v_actor_role text;
begin
 if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'A verified email/password account is required'; end if;
 select * into strict v_member from public.mm_team_members where id=p_member_id for update;
 select role into v_actor_role from public.mm_team_members where team_id=v_member.team_id and user_id=auth.uid() and left_at is null;
 if v_actor_role is null then raise exception 'Active team membership required'; end if;
 if v_member.role='owner' then raise exception 'The team owner cannot be changed or deactivated here'; end if;
 if v_member.left_at is not null then raise exception 'This member is already inactive'; end if;
 if p_action='set_role' then
   if v_actor_role<>'owner' then raise exception 'Only the team owner can appoint admins'; end if;
   if p_role is null or p_role not in ('admin','member') then raise exception 'Role must be admin or member'; end if;
   update public.mm_team_members set role=p_role where id=p_member_id and left_at is null;
   insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action,details) values(v_member.team_id,auth.uid(),'member',p_member_id,'member_role_changed',jsonb_build_object('role',p_role));
 elsif p_action='deactivate' then
   if v_actor_role not in ('owner','admin') then raise exception 'Only owners and admins can deactivate members'; end if;
   if v_actor_role='admin' and v_member.role<>'member' then raise exception 'Admins can only deactivate regular members'; end if;
   if v_member.user_id=auth.uid() then raise exception 'You cannot deactivate your own membership'; end if;
   update public.mm_team_members set left_at=now() where id=p_member_id and left_at is null;
   insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action) values(v_member.team_id,auth.uid(),'member',p_member_id,'member_deactivated');
 else raise exception 'Unsupported member action'; end if;
end; $$;

revoke all on function public.create_team(text,text) from public,anon;
revoke all on function public.record_team_expense(uuid,text,text,bigint,text,uuid,text,date,jsonb) from public,anon;
revoke all on function public.create_team_settlement(uuid,uuid,uuid,bigint) from public,anon;
revoke all on function public.confirm_team_settlement(uuid) from public,anon;
revoke all on function public.create_team_invitation(uuid,text,text,integer) from public,anon;
revoke all on function public.redeem_team_invitation(text,text) from public,anon;
revoke all on function public.manage_team_member(uuid,text,text) from public,anon;
grant execute on function public.create_team(text,text) to authenticated;
grant execute on function public.record_team_expense(uuid,text,text,bigint,text,uuid,text,date,jsonb) to authenticated;
grant execute on function public.create_team_settlement(uuid,uuid,uuid,bigint) to authenticated;
grant execute on function public.confirm_team_settlement(uuid) to authenticated;
grant execute on function public.create_team_invitation(uuid,text,text,integer) to authenticated;
grant execute on function public.redeem_team_invitation(text,text) to authenticated;
grant execute on function public.manage_team_member(uuid,text,text) to authenticated;

commit;