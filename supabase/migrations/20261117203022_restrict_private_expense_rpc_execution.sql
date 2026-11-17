-- Only authenticated device sessions may execute private expense mutation functions.
revoke all on function private.update_team_expense(uuid,text,text,bigint,text,date,jsonb) from public, anon;
revoke all on function private.void_team_expense(uuid) from public, anon;
grant execute on function private.update_team_expense(uuid,text,text,bigint,text,date,jsonb) to authenticated, service_role;
grant execute on function private.void_team_expense(uuid) to authenticated, service_role;
