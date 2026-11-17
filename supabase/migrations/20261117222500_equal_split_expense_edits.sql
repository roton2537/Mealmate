create or replace function private.update_team_expense_simple(
  p_expense_id uuid,p_description text,p_total_minor bigint,p_occurred_on date
) returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_exp public.mm_expenses%rowtype;
  v_member_id uuid;
  v_count bigint;
  v_before jsonb;
begin
  if auth.uid() is null then raise exception 'A device session is required'; end if;
  select * into v_exp from public.mm_expenses where id=p_expense_id for update;
  if not found then raise exception 'Expense not found'; end if;
  if v_exp.voided_at is not null then raise exception 'Deleted expenses cannot be edited'; end if;
  if v_exp.created_by<>auth.uid() then raise exception 'Only the expense creator can edit it'; end if;
  select id into v_member_id from public.mm_team_members
  where team_id=v_exp.team_id and user_id=auth.uid() and left_at is null;
  if v_member_id is null or v_member_id<>v_exp.payer_member_id then
    raise exception 'Active expense creator membership required';
  end if;
  if p_occurred_on is null or p_occurred_on>current_date then raise exception 'Invalid expense date'; end if;
  if not exists(select 1 from public.mm_team_members where id=v_member_id and joined_at::date<=p_occurred_on) then
    raise exception 'Expense date cannot be before your membership start date';
  end if;
  if char_length(trim(coalesce(p_description,''))) not between 1 and 160 then raise exception 'Description must be 1 to 160 characters'; end if;
  if p_total_minor is null or p_total_minor<=0 then raise exception 'Expense amount must be positive'; end if;
  select count(*) into v_count from public.mm_team_members
  where team_id=v_exp.team_id and joined_at::date<=p_occurred_on
    and (left_at is null or left_at::date>=p_occurred_on);
  if v_count=0 then raise exception 'No eligible members existed on the expense date'; end if;
  v_before:=jsonb_build_object(
    'description',v_exp.description,'total_minor',v_exp.total_minor,'occurred_on',v_exp.occurred_on,
    'shares',(select coalesce(jsonb_agg(jsonb_build_object('member_id',member_id,'share_minor',share_minor) order by member_id),'[]'::jsonb) from public.mm_expense_shares where expense_id=v_exp.id)
  );
  update public.mm_expenses set description=trim(p_description),category='other',total_minor=p_total_minor,
    split_method='equal',occurred_on=p_occurred_on,updated_at=now()
  where id=p_expense_id;
  delete from public.mm_expense_shares where expense_id=p_expense_id;
  insert into public.mm_expense_shares(expense_id,team_id,member_id,share_minor)
  select p_expense_id,v_exp.team_id,m.id,
    (p_total_minor / v_count) + case when row_number() over(order by m.joined_at,m.id)<=mod(p_total_minor,v_count) then 1 else 0 end
  from public.mm_team_members m
  where m.team_id=v_exp.team_id and m.joined_at::date<=p_occurred_on
    and (m.left_at is null or m.left_at::date>=p_occurred_on)
  order by m.joined_at,m.id;
  insert into public.mm_team_audit_log(team_id,actor_user_id,entity_type,entity_id,action,details)
  values(v_exp.team_id,auth.uid(),'expense',p_expense_id,'expense_updated',
    jsonb_build_object('before',v_before,'after',jsonb_build_object('description',trim(p_description),'total_minor',p_total_minor,'occurred_on',p_occurred_on,'split_method','equal')));
end;
$function$;

create or replace function public.update_team_expense_simple(p_expense_id uuid,p_description text,p_total_minor bigint,p_occurred_on date)
returns void language sql security definer set search_path to ''
as $function$ select private.update_team_expense_simple(p_expense_id,p_description,p_total_minor,p_occurred_on); $function$;

revoke all on function public.update_team_expense(uuid,text,text,bigint,text,date,jsonb) from public,anon,authenticated;
revoke all on function private.update_team_expense(uuid,text,text,bigint,text,date,jsonb) from public,anon,authenticated;
revoke all on function public.update_team_expense_simple(uuid,text,bigint,date) from public,anon;
grant execute on function public.update_team_expense_simple(uuid,text,bigint,date) to authenticated;
revoke all on function private.update_team_expense_simple(uuid,text,bigint,date) from public,anon,authenticated;