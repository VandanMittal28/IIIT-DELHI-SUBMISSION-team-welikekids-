create function public.get_assignable_event_staff(p_edition_id uuid)
returns table(user_id uuid,full_name text,role public.membership_role)
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
  if actor is null or not private.can_manage_edition(p_edition_id,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Event staff access is required."}',detail='{"status":403}';
  end if;
  return query
  select assignment.user_id,coalesce(nullif(trim(profile.full_name),''),'Assigned staff'),assignment.role
  from public.event_staff_assignments assignment
  join public.profiles profile on profile.id=assignment.user_id
  where assignment.edition_id=p_edition_id
  order by coalesce(nullif(trim(profile.full_name),''),'Assigned staff'),assignment.user_id;
end $$;

revoke all on function public.get_assignable_event_staff(uuid) from public,anon;
grant execute on function public.get_assignable_event_staff(uuid) to authenticated;
