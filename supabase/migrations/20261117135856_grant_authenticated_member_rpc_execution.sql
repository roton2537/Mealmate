grant execute on function private.add_mealmate_member(text,text) to authenticated;
grant execute on function private.deactivate_mealmate_member(uuid) to authenticated;
grant execute on function private.create_mealmate_invitation(uuid,text) to authenticated;
grant execute on function private.claim_mealmate_invitation(text) to authenticated;