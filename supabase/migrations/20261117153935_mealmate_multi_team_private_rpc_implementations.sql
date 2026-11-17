begin;

alter function public.create_team(text,text) set schema private;
alter function public.record_team_expense(uuid,text,text,bigint,text,uuid,text,date,jsonb) set schema private;
alter function public.create_team_settlement(uuid,uuid,uuid,bigint) set schema private;
alter function public.confirm_team_settlement(uuid) set schema private;
alter function public.create_team_invitation(uuid,text,text,integer) set schema private;
alter function public.redeem_team_invitation(text,text) set schema private;
alter function public.manage_team_member(uuid,text,text) set schema private;

drop function if exists public.mm_is_active_team_member(uuid);
drop function if exists public.mm_has_team_role(uuid,text[]);

create or replace function public.create_team(p_name text,p_currency text default 'SAR')
returns uuid language sql security invoker set search_path=''
as $$ select private.create_team(p_name,p_currency); $$;

create or replace function public.record_team_expense(
 p_team_id uuid,p_description text,p_category text,p_total_minor bigint,p_currency text,
 p_payer_member_id uuid,p_split_method text,p_occurred_on date,p_shares jsonb)
returns uuid language sql security invoker set search_path=''
as $$ select private.record_team_expense(p_team_id,p_description,p_category,p_total_minor,p_currency,p_payer_member_id,p_split_method,p_occurred_on,p_shares); $$;

create or replace function public.create_team_settlement(
 p_team_id uuid,p_payer_member_id uuid,p_recipient_member_id uuid,p_amount_minor bigint)
returns uuid language sql security invoker set search_path=''
as $$ select private.create_team_settlement(p_team_id,p_payer_member_id,p_recipient_member_id,p_amount_minor); $$;

create or replace function public.confirm_team_settlement(p_settlement_id uuid)
returns text language sql security invoker set search_path=''
as $$ select private.confirm_team_settlement(p_settlement_id); $$;

create or replace function public.create_team_invitation(
 p_team_id uuid,p_invited_email text default null,p_role text default 'member',p_expires_in_days integer default 7)
returns text language sql security invoker set search_path=''
as $$ select private.create_team_invitation(p_team_id,p_invited_email,p_role,p_expires_in_days); $$;

create or replace function public.redeem_team_invitation(p_token text,p_display_name text)
returns uuid language sql security invoker set search_path=''
as $$ select private.redeem_team_invitation(p_token,p_display_name); $$;

create or replace function public.manage_team_member(p_member_id uuid,p_action text,p_role text default null)
returns void language sql security invoker set search_path=''
as $$ select private.manage_team_member(p_member_id,p_action,p_role); $$;

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