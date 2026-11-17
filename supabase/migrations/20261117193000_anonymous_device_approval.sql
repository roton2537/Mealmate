-- Device-based Supabase anonymous sessions with owner-approved team membership.
-- Additive only: existing teams, members, expenses, and settlement records are preserved.

create table public.mm_team_join_requests (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.mm_teams(id) on delete cascade,
  invitation_id uuid not null references public.mm_team_invitations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  requested_role text not null check (requested_role in ('admin','member')),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id)
);

create unique index mm_team_join_requests_one_pending_per_user
  on public.mm_team_join_requests(team_id,user_id) where status='pending';
create index mm_team_join_requests_owner_queue
  on public.mm_team_join_requests(team_id,status,created_at);

alter table public.mm_team_join_requests enable row level security;
revoke all on table public.mm_team_join_requests from anon, authenticated;
grant select on table public.mm_team_join_requests to authenticated;

create policy mm_join_requests_select_owner
  on public.mm_team_join_requests for select to authenticated
  using (private.mm_has_team_role(team_id,array['owner']::text[]));
create policy mm_join_requests_select_requester
  on public.mm_team_join_requests for select to authenticated
  using (user_id=(select auth.uid()));

-- Anonymous Supabase users receive the authenticated Postgres role. Authorization
-- remains based on the persisted team membership row, never on user-editable metadata.
create or replace function private.mm_is_active_team_member(p_team_id uuid)
returns boolean
language sql stable security definer
set search_path to ''
as $function$
  select auth.uid() is not null
     and exists (
       select 1 from public.mm_team_members m
       where m.team_id=p_team_id and m.user_id=auth.uid() and m.left_at is null
     );
$function$;

create or replace function private.mm_has_team_role(p_team_id uuid,p_roles text[])
returns boolean
language sql stable security definer
set search_path to ''
as $function$
  select auth.uid() is not null
     and exists (
       select 1 from public.mm_team_members m
       where m.team_id=p_team_id and m.user_id=auth.uid()
         and m.left_at is null and m.role=any(p_roles)
     );
$function$;

-- New owner creation signature accepts a display name instead of relying on email metadata.
create or replace function private.create_team(p_name text,p_currency text,p_display_name text)
returns uuid
language plpgsql security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare
  v_team_id uuid;
  v_name text:=trim(coalesce(p_name,''));
  v_currency text:=upper(trim(coalesce(p_currency,'')));
  v_display_name text:=trim(coalesce(p_display_name,''));
begin
  if auth.uid() is null then raise exception 'A device session is required'; end if;
  if char_length(v_name) not between 2 and 80 then raise exception 'Team name must be 2 to 80 characters'; end if;
  if v_currency !~ '^[A-Z]{3}$' then raise exception 'Currency must be a 3-letter ISO code'; end if;
  if char_length(v_display_name) not between 1 and 80 then raise exception 'Display name must be 1 to 80 characters'; end if;
  insert into public.mm_teams(name,currency,owner_user_id)
  values(v_name,v_currency,auth.uid()) returning id into v_team_id;
  insert into public.mm_team_members(team_id,user_id,display_name,role)
  values(v_team_id,auth.uid(),v_display_name,'owner');
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
  values(v_team_id,auth.uid(),'team',v_team_id,'team_created');
  return v_team_id;
end;
$function$;

create or replace function public.create_team(p_name text,p_currency text,p_display_name text)
returns uuid
language sql
set search_path to ''
as $function$
  select private.create_team(p_name,p_currency,p_display_name);
$function$;

-- The existing invite RPC remains the entry point. All links are single-use.
do $migration$
declare
  v_oid oid;
  v_definition text;
  v_guard text := $guard$if auth.uid() is null or coalesce((auth.jwt()->>'is_anonymous')::boolean,false) then raise exception 'A verified email/password account is required'; end if;$guard$;
  v_replacement text := $guard$if auth.uid() is null then raise exception 'A device session is required'; end if;$guard$;
begin
  foreach v_oid in array array[
    to_regprocedure('private.create_team_invitation(uuid,text,text,integer)'),
    to_regprocedure('private.redeem_team_invitation(text,text)'),
    to_regprocedure('private.record_team_expense(uuid,text,text,bigint,text,uuid,text,date,jsonb)'),
    to_regprocedure('private.create_team_settlement(uuid,uuid,uuid,bigint)'),
    to_regprocedure('private.confirm_team_settlement(uuid)'),
    to_regprocedure('private.manage_team_member(uuid,text,text)')
  ] loop
    if v_oid is null then raise exception 'Required MealMate authorization function is missing'; end if;
    v_definition:=pg_get_functiondef(v_oid);
    if position(v_guard in v_definition)=0 then
      raise exception 'Unexpected authorization guard in function %',v_oid::regprocedure;
    end if;
    v_definition:=replace(v_definition,v_guard,v_replacement);
    execute v_definition;
  end loop;

  v_oid:=to_regprocedure('private.create_team_invitation(uuid,text,text,integer)');
  v_definition:=pg_get_functiondef(v_oid);
  if position('make_interval(days=>p_expires_in_days),100);' in v_definition)=0 then
    raise exception 'Unexpected invitation-use limit implementation';
  end if;
  v_definition:=replace(v_definition,'make_interval(days=>p_expires_in_days),100);','make_interval(days=>p_expires_in_days),1);');
  execute v_definition;

  v_oid:=to_regprocedure('private.redeem_team_invitation(text,text)');
  v_definition:=pg_get_functiondef(v_oid);
  if position('insert into public.mm_team_members(team_id,user_id,display_name,role)' in v_definition)=0 then
    raise exception 'Unexpected invitation redemption implementation';
  end if;
  v_definition:=replace(
    v_definition,
    $old$insert into public.mm_team_members(team_id,user_id,display_name,role) values(v_invite.team_id,auth.uid(),v_name,v_invite.role) returning id into v_team_member_id;
 update public.mm_team_invitations set uses=uses+1 where id=v_invite.id;
 insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action) values(v_invite.team_id,auth.uid(),'member',v_team_member_id,'member_joined_via_invitation');
 return v_team_member_id;$old$,
    $new$insert into public.mm_team_join_requests(team_id,invitation_id,user_id,display_name,requested_role,status)
 values(v_invite.team_id,v_invite.id,auth.uid(),v_name,v_invite.role,'pending') returning id into v_team_member_id;
 update public.mm_team_invitations set uses=uses+1 where id=v_invite.id;
 insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
 values(v_invite.team_id,auth.uid(),'join_request',v_team_member_id,'member_join_requested');
 return v_team_member_id;$new$
  );
  if position('insert into public.mm_team_members(team_id,user_id,display_name,role)' in v_definition)>0 then
    raise exception 'Invitation redemption was not converted to an approval request';
  end if;
  execute v_definition;
end;
$migration$;

create or replace function private.approve_team_join_request(p_request_id uuid)
returns uuid
language plpgsql security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare
  v_request public.mm_team_join_requests%rowtype;
  v_member_id uuid;
begin
  if auth.uid() is null then raise exception 'A device session is required'; end if;
  select * into strict v_request from public.mm_team_join_requests where id=p_request_id for update;
  if not private.mm_has_team_role(v_request.team_id,array['owner']::text[]) then
    raise exception 'Only the team owner can approve devices';
  end if;
  if v_request.status<>'pending' then raise exception 'This request is no longer pending'; end if;
  if exists(select 1 from public.mm_team_members where team_id=v_request.team_id and user_id=v_request.user_id and left_at is null) then
    raise exception 'This device is already an active member';
  end if;
  insert into public.mm_team_members(team_id,user_id,display_name,role)
  values(v_request.team_id,v_request.user_id,v_request.display_name,v_request.requested_role)
  returning id into v_member_id;
  update public.mm_team_join_requests
    set status='approved',reviewed_at=now(),reviewed_by=auth.uid()
    where id=p_request_id;
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
  values(v_request.team_id,auth.uid(),'join_request',p_request_id,'member_join_request_approved');
  return v_member_id;
end;
$function$;

create or replace function public.approve_team_join_request(p_request_id uuid)
returns uuid
language sql
set search_path to ''
as $function$
  select private.approve_team_join_request(p_request_id);
$function$;

create or replace function private.reject_team_join_request(p_request_id uuid)
returns void
language plpgsql security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare
  v_request public.mm_team_join_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'A device session is required'; end if;
  select * into strict v_request from public.mm_team_join_requests where id=p_request_id for update;
  if not private.mm_has_team_role(v_request.team_id,array['owner']::text[]) then
    raise exception 'Only the team owner can reject devices';
  end if;
  if v_request.status<>'pending' then raise exception 'This request is no longer pending'; end if;
  update public.mm_team_join_requests
    set status='rejected',reviewed_at=now(),reviewed_by=auth.uid()
    where id=p_request_id;
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
  values(v_request.team_id,auth.uid(),'join_request',p_request_id,'member_join_request_rejected');
end;
$function$;

create or replace function public.reject_team_join_request(p_request_id uuid)
returns void
language sql
set search_path to ''
as $function$
  select private.reject_team_join_request(p_request_id);
$function$;

revoke all on function private.create_team(text,text,text) from public,anon;
revoke all on function public.create_team(text,text,text) from public,anon;
revoke all on function private.approve_team_join_request(uuid) from public,anon;
revoke all on function public.approve_team_join_request(uuid) from public,anon;
revoke all on function private.reject_team_join_request(uuid) from public,anon;
revoke all on function public.reject_team_join_request(uuid) from public,anon;
grant execute on function private.create_team(text,text,text) to authenticated;
grant execute on function public.create_team(text,text,text) to authenticated;
grant execute on function private.approve_team_join_request(uuid) to authenticated;
grant execute on function public.approve_team_join_request(uuid) to authenticated;
grant execute on function private.reject_team_join_request(uuid) to authenticated;
grant execute on function public.reject_team_join_request(uuid) to authenticated;

do $realtime$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='mm_team_join_requests') then
    alter publication supabase_realtime add table public.mm_team_join_requests;
  end if;
end;
$realtime$;
