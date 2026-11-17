alter table public.mm_team_members drop constraint if exists mm_team_members_role_check;
alter table public.mm_team_members add constraint mm_team_members_role_check check (role in ('admin','member'));

alter table public.mm_team_invitations drop constraint if exists mm_team_invitations_role_check;
alter table public.mm_team_invitations add constraint mm_team_invitations_role_check check (role='member');

alter table public.mm_team_join_requests drop constraint if exists mm_team_join_requests_requested_role_check;
alter table public.mm_team_join_requests add constraint mm_team_join_requests_requested_role_check check (requested_role='member');

create or replace function public.admin_issue_member_recovery_token(p_member_id uuid)
returns text
language sql
security definer
set search_path to ''
as $function$ select private.admin_issue_member_recovery_token(p_member_id); $function$;

create or replace function public.redeem_member_recovery_token(p_token text)
returns uuid
language sql
security definer
set search_path to ''
as $function$ select private.redeem_member_recovery_token(p_token); $function$;

revoke all on function public.admin_issue_member_recovery_token(uuid) from public,anon;
revoke all on function public.redeem_member_recovery_token(text) from public,anon;
grant execute on function public.admin_issue_member_recovery_token(uuid) to authenticated;
grant execute on function public.redeem_member_recovery_token(text) to authenticated;