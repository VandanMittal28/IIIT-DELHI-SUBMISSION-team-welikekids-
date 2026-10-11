alter table public.attendance_transitions alter column recorded_at set default clock_timestamp();

create or replace function public.record_attendance(p_pass_token uuid,p_action public.attendance_action,p_client_request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target record; last_action public.attendance_action; transition_id uuid; inside integer;
begin
  if actor is null then raise sqlstate 'PGRST' using message='{"code":"AUTH_REQUIRED","message":"Sign in is required."}',detail='{"status":401}'; end if;
  select at.id into transition_id from public.attendance_transitions at where at.scanned_by=actor and at.client_request_id=p_client_request_id;
  if transition_id is not null then
    select estimated_inside into inside from public.edition_occupancy where edition_id=(select edition_id from public.attendance_transitions where id=transition_id);
    return jsonb_build_object('transition_id',transition_id,'idempotent_replay',true,'estimated_inside',inside);
  end if;
  select p.id pass_id,p.status pass_status,r.id registration_id,r.status registration_status,r.edition_id,ee.reentry_allowed
  into target from public.passes p join public.registrations r on r.id=p.registration_id join public.event_editions ee on ee.id=r.edition_id
  where p.token=p_pass_token for update of p,r,ee;
  if target.pass_id is null or target.pass_status<>'active' or target.registration_status<>'registered' then
    raise sqlstate 'PGRST' using message='{"code":"INVALID_PASS","message":"This pass is invalid or inactive."}',detail='{"status":409}';
  end if;
  if not private.can_manage_edition(target.edition_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Assigned event staff access is required."}',detail='{"status":403}'; end if;
  select action into last_action from public.attendance_transitions where registration_id=target.registration_id order by recorded_at desc,id desc limit 1;
  if p_action='enter' and last_action is not null then raise sqlstate 'PGRST' using message='{"code":"DUPLICATE_ENTRY","message":"This attendee is already inside or has previously entered."}',detail='{"status":409}'; end if;
  if p_action='exit' and last_action not in ('enter','reenter') then raise sqlstate 'PGRST' using message='{"code":"NOT_INSIDE","message":"An exit requires an attendee who is inside."}',detail='{"status":409}'; end if;
  if p_action='reenter' and (last_action<>'exit' or not target.reentry_allowed) then raise sqlstate 'PGRST' using message='{"code":"REENTRY_NOT_ALLOWED","message":"Re-entry is not permitted for this pass."}',detail='{"status":409}'; end if;
  insert into public.attendance_transitions(edition_id,registration_id,pass_id,action,scanned_by,client_request_id,recorded_at)
  values(target.edition_id,target.registration_id,target.pass_id,p_action,actor,p_client_request_id,clock_timestamp()) returning id into transition_id;
  select estimated_inside into inside from public.edition_occupancy where edition_id=target.edition_id;
  return jsonb_build_object('transition_id',transition_id,'action',p_action,'estimated_inside',inside,'idempotent_replay',false);
end;
$$;
revoke all on function public.record_attendance(uuid,public.attendance_action,uuid) from public,anon;
grant execute on function public.record_attendance(uuid,public.attendance_action,uuid) to authenticated;
