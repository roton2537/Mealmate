-- Enforce self-paid expense ownership, add creator-only edit/soft-delete,
-- and expose complete audit history to active team owners/admins.
create or replace function private.record_team_expense(
 p_team_id uuid,p_description text,p_category text,p_total_minor bigint,p_currency text,
 p_payer_member_id uuid,p_split_method text,p_occurred_on date,p_shares jsonb
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_expense_id uuid; v_currency text; v_share_count integer; v_share_sum numeric; v_payer_user uuid;
begin
 if auth.uid() is null then raise exception 'A device session is required'; end if;
 if not private.mm_is_active_team_member(p_team_id) then raise exception 'Active team membership required'; end if;
 if p_total_minor is null or p_total_minor<=0 then raise exception 'Expense amount must be positive'; end if;
 if p_split_method is null or p_split_method not in ('equal','fixed','percentage') then raise exception 'Invalid split method'; end if;
 if p_occurred_on is null or p_occurred_on>current_date then raise exception 'Invalid expense date'; end if;
 if p_shares is null or jsonb_typeof(p_shares) is distinct from 'array' or jsonb_array_length(p_shares)=0 then raise exception 'At least one share is required'; end if;
 if char_length(trim(coalesce(p_description,''))) not between 1 and 160 then raise exception 'Description must be 1 to 160 characters'; end if;
 select currency into strict v_currency from public.mm_teams where id=p_team_id;
 if p_currency is null or upper(trim(p_currency))<>v_currency then raise exception 'Expense currency must match team currency'; end if;
 select user_id into v_payer_user from public.mm_team_members
 where id=p_payer_member_id and team_id=p_team_id and left_at is null and joined_at::date<=p_occurred_on;
 if v_payer_user is null or v_payer_user<>auth.uid() then raise exception 'You can record expenses only for yourself'; end if;
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

create or replace function private.update_team_expense(
 p_expense_id uuid,p_description text,p_category text,p_total_minor bigint,p_split_method text,p_occurred_on date,p_shares jsonb
) returns void language plpgsql security definer set search_path = '' as $$
declare v_exp public.mm_expenses%rowtype; v_member_id uuid; v_share_sum numeric; v_count integer; v_before jsonb; v_after jsonb;
begin
 if auth.uid() is null then raise exception 'A device session is required'; end if;
 select * into v_exp from public.mm_expenses where id=p_expense_id for update;
 if not found then raise exception 'Expense not found'; end if;
 if v_exp.voided_at is not null then raise exception 'Deleted expenses cannot be edited'; end if;
 if v_exp.created_by<>auth.uid() then raise exception 'Only the expense creator can edit it'; end if;
 select id into v_member_id from public.mm_team_members where team_id=v_exp.team_id and user_id=auth.uid() and left_at is null;
 if v_member_id is null or v_member_id<>v_exp.payer_member_id then raise exception 'Active expense creator membership required'; end if;
 if p_occurred_on is null or p_occurred_on>current_date then raise exception 'Invalid expense date'; end if;
 if not exists(select 1 from public.mm_team_members where id=v_member_id and joined_at::date<=p_occurred_on) then raise exception 'Expense date cannot be before your membership start date'; end if;
 if char_length(trim(coalesce(p_description,''))) not between 1 and 160 then raise exception 'Description must be 1 to 160 characters'; end if;
 if p_total_minor is null or p_total_minor<=0 then raise exception 'Expense amount must be positive'; end if;
 if p_split_method not in ('equal','fixed','percentage') then raise exception 'Invalid split method'; end if;
 if p_shares is null or jsonb_typeof(p_shares) is distinct from 'array' or jsonb_array_length(p_shares)=0 then raise exception 'At least one share is required'; end if;
 select count(*),coalesce(sum(s.share_minor),0) into v_count,v_share_sum
 from jsonb_to_recordset(p_shares) as s(member_id uuid,share_minor bigint)
 join public.mm_team_members m on m.id=s.member_id where m.team_id=v_exp.team_id
 and m.joined_at::date<=p_occurred_on and (m.left_at is null or m.left_at::date>=p_occurred_on) and s.share_minor>=0;
 if v_count<>jsonb_array_length(p_shares) then raise exception 'Every participant must be a valid team member on the expense date'; end if;
 if exists(select 1 from jsonb_to_recordset(p_shares) as s(member_id uuid,share_minor bigint) group by s.member_id having count(*)>1) then raise exception 'Duplicate participants are not allowed'; end if;
 if v_share_sum<>p_total_minor then raise exception 'Shares must add up exactly to expense total'; end if;
 if not exists(select 1 from jsonb_to_recordset(p_shares) as s(member_id uuid,share_minor bigint) where s.member_id=v_member_id) then raise exception 'Creator must remain included in participants'; end if;
 select jsonb_build_object('description',v_exp.description,'category',v_exp.category,'total_minor',v_exp.total_minor,'split_method',v_exp.split_method,'occurred_on',v_exp.occurred_on,
 'shares',(select coalesce(jsonb_agg(jsonb_build_object('member_id',member_id,'share_minor',share_minor) order by member_id),'[]'::jsonb) from public.mm_expense_shares where expense_id=v_exp.id)) into v_before;
 update public.mm_expenses set description=trim(p_description),category=coalesce(nullif(trim(p_category),''),'other'),total_minor=p_total_minor,split_method=p_split_method,occurred_on=p_occurred_on,updated_at=now() where id=p_expense_id;
 delete from public.mm_expense_shares where expense_id=p_expense_id;
 insert into public.mm_expense_shares(expense_id,team_id,member_id,share_minor)
 select p_expense_id,v_exp.team_id,s.member_id,s.share_minor from jsonb_to_recordset(p_shares) as s(member_id uuid,share_minor bigint);
 select jsonb_build_object('description',trim(p_description),'category',coalesce(nullif(trim(p_category),''),'other'),'total_minor',p_total_minor,'split_method',p_split_method,'occurred_on',p_occurred_on,
 'shares',(select coalesce(jsonb_agg(jsonb_build_object('member_id',member_id,'share_minor',share_minor) order by member_id),'[]'::jsonb) from public.mm_expense_shares where expense_id=p_expense_id)) into v_after;
 insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action,details) values(v_exp.team_id,auth.uid(),'expense',p_expense_id,'expense_updated',jsonb_build_object('before',v_before,'after',v_after));
end; $$;

create or replace function private.void_team_expense(p_expense_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_exp public.mm_expenses%rowtype;
begin
 if auth.uid() is null then raise exception 'A device session is required'; end if;
 select * into v_exp from public.mm_expenses where id=p_expense_id for update;
 if not found then raise exception 'Expense not found'; end if;
 if v_exp.voided_at is not null then raise exception 'Expense is already deleted'; end if;
 if v_exp.created_by<>auth.uid() then raise exception 'Only the expense creator can delete it'; end if;
 if not exists(select 1 from public.mm_team_members where team_id=v_exp.team_id and user_id=auth.uid() and id=v_exp.payer_member_id and left_at is null) then raise exception 'Active expense creator membership required'; end if;
 update public.mm_expenses set voided_at=now(),updated_at=now() where id=p_expense_id;
 insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action,details)
 values(v_exp.team_id,auth.uid(),'expense',p_expense_id,'expense_deleted',jsonb_build_object('description',v_exp.description,'total_minor',v_exp.total_minor,'currency',v_exp.currency,'occurred_on',v_exp.occurred_on));
end; $$;

create or replace function public.update_team_expense(p_expense_id uuid,p_description text,p_category text,p_total_minor bigint,p_split_method text,p_occurred_on date,p_shares jsonb)
returns void language sql security invoker set search_path = '' as $$ select private.update_team_expense(p_expense_id,p_description,p_category,p_total_minor,p_split_method,p_occurred_on,p_shares); $$;
create or replace function public.void_team_expense(p_expense_id uuid)
returns void language sql security invoker set search_path = '' as $$ select private.void_team_expense(p_expense_id); $$;
revoke all on function public.update_team_expense(uuid,text,text,bigint,text,date,jsonb) from public, anon;
revoke all on function public.void_team_expense(uuid) from public, anon;
grant execute on function public.update_team_expense(uuid,text,text,bigint,text,date,jsonb) to authenticated;
grant execute on function public.void_team_expense(uuid) to authenticated;
drop policy if exists "Team owners and admins can view audit history" on public.mm_team_audit_log;
create policy "Team owners and admins can view audit history" on public.mm_team_audit_log for select to authenticated using (
 exists(select 1 from public.mm_team_members m where m.team_id=mm_team_audit_log.team_id and m.user_id=auth.uid() and m.left_at is null and m.role in ('owner','admin'))
);
