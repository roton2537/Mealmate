-- Invitation lifecycle for multi-team membership.
-- Staged on feature branch only. Not applied to the live Supabase project.
begin;

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
  if not public.has_team_role(p_team_id, array['owner','admin']) then
    raise exception 'Only team owners and admins can invite members';
  end if;
  if v_email is not null and v_email !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$' then
    raise exception 'Invalid invitation email';
  end if;
  if v_role not in ('admin','member') then raise exception 'Invalid invitation role'; end if;
  if p_expires_in_days is null or p_expires_in_days not between 1 and 30 then
    raise exception 'Invitation expiry must be 1 to 30 days';
  end if;

  v_token := encode(gen_random_bytes(32), 'hex');
  insert into public.team_invitations(team_id, created_by, token_hash, invited_email, role, expires_at)
  values (p_team_id, auth.uid(), encode(digest(v_token, 'sha256'),'hex'), v_email, v_role,
    now() + make_interval(days => p_expires_in_days));

  insert into public.team_audit_log(team_id, actor_user_id, entity_type, action, details)
  values (p_team_id, auth.uid(), 'invitation', 'invitation_created',
    jsonb_build_object('invited_email', v_email, 'role', v_role, 'expires_in_days', p_expires_in_days));
  return v_token;
end;
$$;

create or replace function public.redeem_team_invitation(p_token text, p_display_name text)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions, pg_temp
as $$
declare
  v_invite public.team_invitations%rowtype;
  v_team_member_id uuid;
  v_email text := lower(coalesce(auth.jwt()->>'email',''));
  v_name text := trim(coalesce(p_display_name,''));
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_token is null or length(trim(p_token)) < 32 then raise exception 'Invalid invitation code'; end if;
  if char_length(v_name) not between 1 and 80 then raise exception 'Name must be 1 to 80 characters'; end if;

  select * into v_invite
  from public.team_invitations
  where token_hash = encode(digest(trim(p_token), 'sha256'),'hex')
  for update;

  if not found or v_invite.revoked_at is not null or v_invite.expires_at <= now()
     or v_invite.uses >= v_invite.max_uses then
    raise exception 'Invitation is invalid, expired, or already used';
  end if;
  if v_invite.invited_email is not null and v_invite.invited_email <> v_email then
    raise exception 'This invitation belongs to a different email address';
  end if;
  if exists (select 1 from public.team_members where team_id = v_invite.team_id and user_id = auth.uid() and left_at is null) then
    raise exception 'You are already an active member of this team';
  end if;

  insert into public.team_members(team_id, user_id, display_name, role)
  values (v_invite.team_id, auth.uid(), v_name, v_invite.role)
  returning id into v_team_member_id;

  update public.team_invitations set uses = uses + 1 where id = v_invite.id;
  insert into public.team_audit_log(team_id, actor_user_id, entity_type, entity_id, action)
  values (v_invite.team_id, auth.uid(), 'member', v_team_member_id, 'member_joined_via_invitation');
  return v_team_member_id;
end;
$$;

revoke all on function public.create_team_invitation(uuid,text,text,integer) from public, anon;
revoke all on function public.redeem_team_invitation(text,text) from public, anon;
grant execute on function public.create_team_invitation(uuid,text,text,integer) to authenticated;
grant execute on function public.redeem_team_invitation(text,text) to authenticated;

commit;
