create schema if not exists private;

create table if not exists private.mm_member_recovery_tokens (
  member_id uuid primary key references public.mm_team_members(id) on delete cascade,
  team_id uuid not null references public.mm_teams(id) on delete cascade,
  token_hash text not null unique,
  issued_by uuid not null references auth.users(id),
  issued_at timestamptz not null default now(),
  last_used_at timestamptz
);
revoke all on table private.mm_member_recovery_tokens from public, anon, authenticated;

-- The product has exactly two roles. Existing team creators become Admins.
update public.mm_team_members set role='admin' where role='owner';
update public.mm_team_invitations set role='member' where role<>'member';
update public.mm_team_join_requests set requested_role='member' where requested_role<>'member';

create or replace function private.approve_team_join_request(p_request_id uuid)
returns uuid language plpgsql security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare v_request public.mm_team_join_requests%rowtype; v_member_id uuid;
begin
  if auth.uid() is null then raise exception 'An admin session is required'; end if;
  select * into strict v_request from public.mm_team_join_requests where id=p_request_id for update;
  if not private.mm_has_team_role(v_request.team_id,array['admin']::text[]) then
    raise exception 'Only the Admin can approve members';
  end if;
  if v_request.status<>'pending' then raise exception 'This request is no longer pending'; end if;
  if exists(select 1 from public.mm_team_members where team_id=v_request.team_id and user_id=v_request.user_id and left_at is null) then
    raise exception 'This device is already an active member';
  end if;
  insert into public.mm_team_members(team_id,user_id,display_name,role)
  values(v_request.team_id,v_request.user_id,v_request.display_name,'member')
  returning id into v_member_id;
  update public.mm_team_join_requests set status='approved',reviewed_at=now(),reviewed_by=auth.uid() where id=p_request_id;
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
  values(v_request.team_id,auth.uid(),'join_request',p_request_id,'member_join_request_approved');
  return v_member_id;
end;
$function$;

create or replace function private.reject_team_join_request(p_request_id uuid)
returns void language plpgsql security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare v_request public.mm_team_join_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'An admin session is required'; end if;
  select * into strict v_request from public.mm_team_join_requests where id=p_request_id for update;
  if not private.mm_has_team_role(v_request.team_id,array['admin']::text[]) then
    raise exception 'Only the Admin can reject members';
  end if;
  if v_request.status<>'pending' then raise exception 'This request is no longer pending'; end if;
  update public.mm_team_join_requests set status='rejected',reviewed_at=now(),reviewed_by=auth.uid() where id=p_request_id;
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
  values(v_request.team_id,auth.uid(),'join_request',p_request_id,'member_join_request_rejected');
end;
$function$;

create or replace function private.create_team_invitation(
  p_team_id uuid, p_invited_email text default null, p_role text default 'member', p_expires_in_days integer default 7
) returns text language plpgsql security definer
set search_path to 'public','auth','extensions','pg_temp'
as $function$
declare v_token text; v_email text:=nullif(lower(trim(coalesce(p_invited_email,''))), '');
begin
  if auth.uid() is null then raise exception 'An admin session is required'; end if;
  if not private.mm_has_team_role(p_team_id,array['admin']::text[]) then raise exception 'Only the Admin can invite members'; end if;
  if coalesce(p_role,'member')<>'member' then raise exception 'Invitations can only create Member accounts'; end if;
  if v_email is not null and v_email !~* '^[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}$' then raise exception 'Invalid invitation email'; end if;
  if p_expires_in_days is null or p_expires_in_days not between 1 and 30 then raise exception 'Invitation expiry must be 1 to 30 days'; end if;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.mm_team_invitations(team_id,created_by,token_hash,invited_email,role,expires_at,max_uses)
  values(p_team_id,auth.uid(),encode(extensions.digest(v_token,'sha256'),'hex'),v_email,'member',now()+make_interval(days=>p_expires_in_days),1);
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,action,details)
  values(p_team_id,auth.uid(),'invitation','invitation_created',jsonb_build_object('invited_email',v_email,'role','member','expires_in_days',p_expires_in_days));
  return v_token;
end;
$function$;

create or replace function private.manage_team_member(p_member_id uuid,p_action text,p_role text default null)
returns void language plpgsql security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare v_member public.mm_team_members%rowtype;
begin
  if auth.uid() is null then raise exception 'An admin session is required'; end if;
  select * into strict v_member from public.mm_team_members where id=p_member_id for update;
  if not private.mm_has_team_role(v_member.team_id,array['admin']::text[]) then raise exception 'Only the Admin can manage members'; end if;
  if v_member.role='admin' then raise exception 'The Admin account cannot be changed or deactivated here'; end if;
  if v_member.left_at is not null then raise exception 'This member is already inactive'; end if;
  if p_action<>'deactivate' then raise exception 'Only member deactivation is supported'; end if;
  if v_member.user_id=auth.uid() then raise exception 'You cannot deactivate your own membership'; end if;
  update public.mm_team_members set left_at=now() where id=p_member_id and left_at is null;
  update private.mm_member_recovery_tokens set token_hash=encode(extensions.digest(encode(extensions.gen_random_bytes(32),'hex'),'sha256'),'hex')
  where member_id=p_member_id;
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
  values(v_member.team_id,auth.uid(),'member',p_member_id,'member_deactivated');
end;
$function$;

create or replace function private.create_team(p_name text,p_currency text,p_display_name text)
returns uuid language plpgsql security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare v_team_id uuid; v_name text:=trim(coalesce(p_name,'')); v_currency text:=upper(trim(coalesce(p_currency,''))); v_display_name text:=trim(coalesce(p_display_name,''));
begin
  if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,true) then raise exception 'The team creator must sign in with an email and password'; end if;
  if char_length(v_name) not between 2 and 80 then raise exception 'Team name must be 2 to 80 characters'; end if;
  if v_currency !~ '^[A-Z]{3}$' then raise exception 'Currency must be a 3-letter ISO code'; end if;
  if char_length(v_display_name) not between 1 and 80 then raise exception 'Display name must be 1 to 80 characters'; end if;
  if exists(select 1 from public.mm_team_members where user_id=auth.uid() and left_at is null) then raise exception 'You already belong to a team'; end if;
  insert into public.mm_teams(name,currency,owner_user_id) values(v_name,v_currency,auth.uid()) returning id into v_team_id;
  insert into public.mm_team_members(team_id,user_id,display_name,role) values(v_team_id,auth.uid(),v_display_name,'admin');
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action) values(v_team_id,auth.uid(),'team',v_team_id,'team_created');
  return v_team_id;
end;
$function$;

create or replace function private.create_team(p_name text,p_currency text default 'SAR')
returns uuid language plpgsql security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare v_display_name text;
begin
  if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,true) then raise exception 'The team creator must sign in with an email and password'; end if;
  v_display_name:=coalesce(nullif(trim(auth.jwt()->'user_metadata'->>'display_name'),''),nullif(trim(auth.jwt()->>'email'),''),'Admin');
  return private.create_team(p_name,p_currency,v_display_name);
end;
$function$;

create or replace function private.admin_issue_member_recovery_token(p_member_id uuid)
returns text language plpgsql security definer
set search_path to 'public','auth','extensions','pg_temp'
as $function$
declare v_member public.mm_team_members%rowtype; v_token text;
begin
  if auth.uid() is null then raise exception 'An admin session is required'; end if;
  select * into strict v_member from public.mm_team_members where id=p_member_id for update;
  if not private.mm_has_team_role(v_member.team_id,array['admin']::text[]) then raise exception 'Only the Admin can issue recovery links'; end if;
  if v_member.role<>'member' or v_member.left_at is not null then raise exception 'Recovery links can only be issued to active Members'; end if;
  v_token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into private.mm_member_recovery_tokens(member_id,team_id,token_hash,issued_by,issued_at,last_used_at)
  values(p_member_id,v_member.team_id,encode(extensions.digest(v_token,'sha256'),'hex'),auth.uid(),now(),null)
  on conflict(member_id) do update set team_id=excluded.team_id,token_hash=excluded.token_hash,issued_by=excluded.issued_by,issued_at=now(),last_used_at=null;
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
  values(v_member.team_id,auth.uid(),'member',p_member_id,'member_recovery_token_rotated');
  return v_token;
end;
$function$;

create or replace function private.redeem_member_recovery_token(p_token text)
returns uuid language plpgsql security definer
set search_path to 'public','auth','extensions','pg_temp'
as $function$
declare v_member public.mm_team_members%rowtype; v_old_user_id uuid; v_hash text;
begin
  if auth.uid() is null then raise exception 'A temporary device session is required'; end if;
  if coalesce((auth.jwt()->>'is_anonymous')::boolean,false) is not true then raise exception 'Recovery links are for member device sessions only'; end if;
  if p_token is null or length(trim(p_token))<>64 then raise exception 'Invalid recovery token'; end if;
  v_hash:=encode(extensions.digest(trim(p_token),'sha256'),'hex');
  select m.* into v_member
  from private.mm_member_recovery_tokens r
  join public.mm_team_members m on m.id=r.member_id
  where r.token_hash=v_hash and m.left_at is null and m.role='member'
  for update of r,m;
  if not found then raise exception 'Recovery link is invalid or the membership is inactive'; end if;
  if exists(select 1 from public.mm_team_members where user_id=auth.uid() and left_at is null) then raise exception 'This device is already connected to an active team'; end if;
  v_old_user_id:=v_member.user_id;
  update public.mm_team_members set user_id=auth.uid() where id=v_member.id;
  update public.mm_expenses set created_by=auth.uid() where payer_member_id=v_member.id and created_by=v_old_user_id;
  update private.mm_member_recovery_tokens set last_used_at=now() where member_id=v_member.id;
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
  values(v_member.team_id,auth.uid(),'member',v_member.id,'member_recovered_on_new_device');
  return v_member.id;
end;
$function$;

create or replace function public.admin_issue_member_recovery_token(p_member_id uuid)
returns text language sql set search_path to ''
as $function$ select private.admin_issue_member_recovery_token(p_member_id); $function$;

create or replace function public.redeem_member_recovery_token(p_token text)
returns uuid language sql set search_path to ''
as $function$ select private.redeem_member_recovery_token(p_token); $function$;

revoke all on function public.admin_issue_member_recovery_token(uuid) from public,anon;
revoke all on function public.redeem_member_recovery_token(text) from public,anon;
grant execute on function public.admin_issue_member_recovery_token(uuid) to authenticated;
grant execute on function public.redeem_member_recovery_token(text) to authenticated;

revoke all on function private.admin_issue_member_recovery_token(uuid) from public,anon,authenticated;
revoke all on function private.redeem_member_recovery_token(text) from public,anon,authenticated;
