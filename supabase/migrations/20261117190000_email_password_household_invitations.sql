-- Individual email/password accounts with member-bound, one-time invitations.
create table if not exists private.mealmate_invitations (
  member_id uuid primary key references public.members(id) on delete cascade,
  household_id uuid not null references public.households(id) on delete cascade,
  email text not null,
  token_hash text not null,
  expires_at timestamptz not null,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  constraint mealmate_invitation_email_nonempty check (length(trim(email)) > 3)
);
create index if not exists mealmate_invitations_household_idx on private.mealmate_invitations(household_id);
revoke all on private.mealmate_invitations from public, anon, authenticated;

create or replace function private.is_mealmate_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.members m
    where m.auth_user_id = (select auth.uid())
      and m.name = 'MD ROTON MIAH' and m.deactivated_at is null
  ) or exists (
    select 1 from private.mealmate_sessions s
    join public.members m on m.id=s.member_id and m.household_id=s.household_id
    where s.user_id=(select auth.uid()) and m.name='MD ROTON MIAH'
      and m.deactivated_at is null
  );
$$;

create or replace function private.add_mealmate_member(p_name text, p_name_bn text default '')
returns public.members language plpgsql security definer set search_path = ''
as $$
declare household uuid; created public.members; clean_name text := upper(trim(coalesce(p_name,'')));
begin
  if not private.is_mealmate_admin() then raise exception 'Only Roton can manage household members'; end if;
  select c.household_id into household from private.get_mealmate_session_context() c limit 1;
  if household is null then raise exception 'Household account is not linked'; end if;
  if char_length(clean_name) not between 2 and 80 then raise exception 'Enter a member name between 2 and 80 characters'; end if;
  if (select count(*) from public.members m where m.household_id=household and m.deactivated_at is null) >= 6 then raise exception 'A household can have at most six active members'; end if;
  if exists(select 1 from public.members m where m.household_id=household and upper(m.name)=clean_name) then raise exception 'A member with this name already exists'; end if;
  insert into public.members(household_id,name,name_bn,joined_at) values(household,clean_name,coalesce(nullif(trim(p_name_bn),''),clean_name),current_date) returning * into created;
  return created;
end;
$$;

create or replace function private.deactivate_mealmate_member(p_member_id uuid)
returns public.members language plpgsql security definer set search_path = ''
as $$
declare household uuid; target public.members; active_count integer;
begin
  if not private.is_mealmate_admin() then raise exception 'Only Roton can manage household members'; end if;
  select c.household_id into household from private.get_mealmate_session_context() c limit 1;
  select * into target from public.members m where m.id=p_member_id and m.household_id=household for update;
  if target.id is null then raise exception 'Member not found'; end if;
  if target.name='MD ROTON MIAH' then raise exception 'The household administrator cannot be deactivated'; end if;
  if target.deactivated_at is not null then return target; end if;
  select count(*) into active_count from public.members m where m.household_id=household and m.deactivated_at is null;
  if active_count <= 3 then raise exception 'At least three active members are required'; end if;
  update public.members set deactivated_at=current_date where id=p_member_id returning * into target;
  return target;
end;
$$;

create or replace function private.create_mealmate_invitation(p_member_id uuid, p_email text)
returns text language plpgsql security definer set search_path = ''
as $$
declare household uuid; target public.members; token text; normalized_email text := lower(trim(coalesce(p_email,'')));
begin
  if (select auth.uid()) is null or coalesce((select auth.jwt()->>'is_anonymous')::boolean,false) then
    raise exception 'Sign in with an email and password before creating invitations';
  end if;
  if not private.is_mealmate_admin() then raise exception 'Only Roton can invite household members'; end if;
  select c.household_id into household from private.get_mealmate_session_context() c limit 1;
  select * into target from public.members m where m.id=p_member_id and m.household_id=household for update;
  if target.id is null or target.deactivated_at is not null then raise exception 'Active household member not found'; end if;
  if target.auth_user_id is not null then raise exception 'This member already has a linked account'; end if;
  if normalized_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Enter a valid email address'; end if;
  if exists(select 1 from private.mealmate_invitations i where i.household_id=household and lower(i.email)=normalized_email and i.member_id<>p_member_id) then
    raise exception 'This email is already invited to another member';
  end if;
  token := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  insert into private.mealmate_invitations(member_id,household_id,email,token_hash,expires_at,created_by)
  values(p_member_id,household,normalized_email,encode(sha256(convert_to(token,'UTF8')),'hex'),now()+interval '7 days',(select auth.uid()))
  on conflict(member_id) do update set household_id=excluded.household_id,email=excluded.email,token_hash=excluded.token_hash,expires_at=excluded.expires_at,created_by=excluded.created_by,created_at=now();
  return token;
end;
$$;

create or replace function private.claim_mealmate_invitation(p_token text)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare current_user_id uuid := (select auth.uid()); current_email text := lower(coalesce((select auth.jwt()->>'email'),'')); verified_at timestamptz; target private.mealmate_invitations; linked_member uuid;
begin
  if current_user_id is null or coalesce((select auth.jwt()->>'is_anonymous')::boolean,false) then
    raise exception 'Sign in with your personal email and password first';
  end if;
  select u.email_confirmed_at into verified_at from auth.users u where u.id=current_user_id;
  if verified_at is null then raise exception 'Verify your email address before joining MealMate'; end if;
  select * into target from private.mealmate_invitations i
  where i.token_hash=encode(sha256(convert_to(trim(coalesce(p_token,'')),'UTF8')),'hex')
    and lower(i.email)=current_email and i.expires_at>now()
  for update;
  if target.member_id is null then raise exception 'Invitation is invalid, expired, or belongs to a different email'; end if;
  update public.members m set auth_user_id=current_user_id
  where m.id=target.member_id and m.household_id=target.household_id
    and m.deactivated_at is null and m.auth_user_id is null
  returning m.id into linked_member;
  if linked_member is null then raise exception 'This member already has an account or is no longer active'; end if;
  delete from private.mealmate_invitations where member_id=target.member_id;
  return linked_member;
end;
$$;

create or replace function public.create_mealmate_invitation(p_member_id uuid,p_email text)
returns text language sql set search_path = '' as $$ select private.create_mealmate_invitation(p_member_id,p_email); $$;
create or replace function public.claim_mealmate_invitation(p_token text)
returns uuid language sql set search_path = '' as $$ select private.claim_mealmate_invitation(p_token); $$;

revoke all on function private.create_mealmate_invitation(uuid,text) from public,anon,authenticated;
revoke all on function private.claim_mealmate_invitation(text) from public,anon,authenticated;
revoke all on function private.is_mealmate_admin() from public,anon,authenticated;
revoke all on function private.add_mealmate_member(text,text) from public,anon,authenticated;
revoke all on function private.deactivate_mealmate_member(uuid) from public,anon,authenticated;
grant execute on function public.create_mealmate_invitation(uuid,text) to authenticated;
grant execute on function public.claim_mealmate_invitation(text) to authenticated;
grant execute on function public.add_mealmate_member(text,text) to authenticated;
grant execute on function public.deactivate_mealmate_member(uuid) to authenticated;
