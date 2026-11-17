-- Keep the existing canonical owner/admin audit SELECT policy only.
drop policy if exists "Team owners and admins can view audit history" on public.mm_team_audit_log;
