-- Read-only client access, realtime publication and safe team administration.
-- Uses mm_ prefixed tables to coexist with the legacy household schema.
begin;

grant select on public.mm_teams, public.mm_team_members, public.mm_team_invitations,
  public.mm_expenses, public.mm_expense_shares, public.mm_settlements,
  public.mm_team_audit_log to authenticated;

create or replace function public.manage_team_member(
  p_member_id uuid,
  p_action text,
  p_role text default null
)
returns void
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_member public.mm_team_members%rowtype;
  v_actor_role text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into strict v_member from public.mm_team_members where id=p_member_id for update;
  select role into v_actor_role from public.mm_team_members
    where team_id=v_member.team_id and user_id=auth.uid() and left_at is null;
  if v_actor_role is null then raise exception 'Active team membership required'; end if;
  if v_member.role='owner' then raise exception 'The team owner cannot be changed or deactivated here'; end if;
  if v_member.left_at is not null then raise exception 'This member is already inactive'; end if;

  if p_action='set_role' then
    if v_actor_role <> 'owner' then raise exception 'Only the team owner can appoint admins'; end if;
    if p_role is null or p_role not in ('admin','member') then raise exception 'Role must be admin or member'; end if;
    update public.mm_team_members set role=p_role where id=p_member_id and left_at is null;
    insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action,details)
    values(v_member.team_id,auth.uid(),'member',p_member_id,'member_role_changed',jsonb_build_object('role',p_role));
  elsif p_action='deactivate' then
    if v_actor_role not in ('owner','admin') then raise exception 'Only owners and admins can deactivate members'; end if;
    if v_actor_role='admin' and v_member.role<>'member' then raise exception 'Admins can only deactivate regular members'; end if;
    if v_member.user_id=auth.uid() then raise exception 'You cannot deactivate your own membership'; end if;
    update public.mm_team_members set left_at=now() where id=p_member_id and left_at is null;
    insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action)
    values(v_member.team_id,auth.uid(),'member',p_member_id,'member_deactivated');
  else
    raise exception 'Unsupported member action';
  end if;
end;
$$;

revoke all on function public.manage_team_member(uuid,text,text) from public, anon;
grant execute on function public.manage_team_member(uuid,text,text) to authenticated;

-- Enable live change notifications for the app's team-scoped records.
do $$
declare t text;
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    foreach t in array array['mm_expenses','mm_expense_shares','mm_settlements','mm_team_members'] loop
      if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
        execute format('alter publication supabase_realtime add table public.%I',t);
      end if;
    end loop;
  end if;
end $$;

commit;
