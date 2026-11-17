drop policy if exists mm_join_requests_select_owner on public.mm_team_join_requests;
create policy mm_join_requests_select_admin
on public.mm_team_join_requests
for select
to authenticated
using (private.mm_has_team_role(team_id,array['admin']::text[]));

grant select on public.mm_team_join_requests to authenticated;