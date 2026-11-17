-- Keep SECURITY DEFINER implementations in the private schema.
-- Public RPCs are SECURITY INVOKER wrappers with narrowly granted EXECUTE.
create or replace function private.add_mealmate_member(p_name text,p_name_bn text default '')
returns public.members language plpgsql security definer set search_path=''
as $$
declare household uuid; created public.members; clean_name text:=upper(trim(coalesce(p_name,'')));
begin
 if not private.is_mealmate_admin() then raise exception 'Only Roton can manage household members'; end if;
 select s.household_id into household from private.mealmate_sessions s where s.user_id=(select auth.uid());
 if household is null then raise exception 'Household session unavailable'; end if;
 if char_length(clean_name) not between 2 and 80 then raise exception 'Enter a member name between 2 and 80 characters'; end if;
 if (select count(*) from public.members m where m.household_id=household and m.deactivated_at is null)>=6 then raise exception 'A household can have at most six active members'; end if;
 if exists(select 1 from public.members m where m.household_id=household and upper(m.name)=clean_name) then raise exception 'A member with this name already exists'; end if;
 insert into public.members(household_id,name,name_bn,joined_at) values(household,clean_name,coalesce(nullif(trim(p_name_bn),''),clean_name),current_date) returning * into created;
 return created;
end; $$;
create or replace function private.deactivate_mealmate_member(p_member_id uuid)
returns public.members language plpgsql security definer set search_path=''
as $$
declare household uuid; target public.members; active_count integer;
begin
 if not private.is_mealmate_admin() then raise exception 'Only Roton can manage household members'; end if;
 select s.household_id into household from private.mealmate_sessions s where s.user_id=(select auth.uid());
 select * into target from public.members m where m.id=p_member_id and m.household_id=household for update;
 if target.id is null then raise exception 'Member not found'; end if;
 if target.name='MD ROTON MIAH' then raise exception 'The household administrator cannot be deactivated'; end if;
 if target.deactivated_at is not null then return target; end if;
 select count(*) into active_count from public.members m where m.household_id=household and m.deactivated_at is null;
 if active_count<=3 then raise exception 'At least three active members are required'; end if;
 update public.members set deactivated_at=current_date where id=p_member_id returning * into target;
 return target;
end; $$;
create or replace function private.list_mealmate_members(p_access_code text)
returns table(id uuid,name text,name_bn text) language plpgsql security definer set search_path=''
as $$
declare target_household uuid; stored_hash text;
begin
 select h.id into target_household from public.households h where h.slug='mealmate-shared';
 select c.code_hash into stored_hash from private.mealmate_access_codes c where c.household_id=target_household;
 if stored_hash is null or encode(sha256(convert_to(trim(coalesce(p_access_code,'')),'UTF8')),'hex')<>stored_hash then raise exception 'The household access code is incorrect'; end if;
 return query select m.id,m.name,m.name_bn from public.members m where m.household_id=target_household and m.deactivated_at is null order by m.name;
end; $$;
revoke all on function private.add_mealmate_member(text,text),private.deactivate_mealmate_member(uuid),private.list_mealmate_members(text) from public,anon,authenticated;
grant execute on function private.add_mealmate_member(text,text),private.deactivate_mealmate_member(uuid),private.list_mealmate_members(text) to authenticated;
create or replace function public.add_mealmate_member(p_name text,p_name_bn text default '')
returns public.members language sql security invoker set search_path='' as $$ select private.add_mealmate_member(p_name,p_name_bn); $$;
create or replace function public.deactivate_mealmate_member(p_member_id uuid)
returns public.members language sql security invoker set search_path='' as $$ select private.deactivate_mealmate_member(p_member_id); $$;
create or replace function public.list_mealmate_members(p_access_code text)
returns table(id uuid,name text,name_bn text) language sql security invoker set search_path='' as $$ select * from private.list_mealmate_members(p_access_code); $$;
revoke all on function public.add_mealmate_member(text,text),public.deactivate_mealmate_member(uuid),public.list_mealmate_members(text) from public,anon;
grant execute on function public.add_mealmate_member(text,text),public.deactivate_mealmate_member(uuid),public.list_mealmate_members(text) to authenticated;
