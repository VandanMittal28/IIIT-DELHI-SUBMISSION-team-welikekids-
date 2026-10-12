create function public.end_route_closure(p_closure_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target record; attendee record; ended timestamptz; notified integer:=0;
begin
 select closure.id,closure.edge_id,closure.starts_at,closure.ends_at,version.campus_id,campus.college_id
 into target
 from public.route_closures closure
 join public.route_edges edge on edge.id=closure.edge_id
 join public.route_versions version on version.id=edge.route_version_id
 join public.campuses campus on campus.id=version.campus_id
 where closure.id=p_closure_id
 for update of closure;
 if actor is null or target.id is null or not private.is_college_admin(target.college_id,actor) then
   raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}';
 end if;
 if target.ends_at is not null and target.ends_at<=clock_timestamp() then
   return jsonb_build_object('closure_id',target.id,'persisted',true,'route_refresh_required',true,'idempotent_replay',true);
 end if;
 if target.starts_at>clock_timestamp() then
   raise sqlstate 'PGRST' using message='{"code":"CLOSURE_NOT_ACTIVE","message":"A scheduled closure cannot be reopened before it starts."}',detail='{"status":409}';
 end if;

 ended:=greatest(now(),target.starts_at+interval '1 microsecond');
 update public.route_closures set ends_at=ended where id=target.id;
 update public.campuses set route_change_sequence=route_change_sequence+1 where id=target.campus_id;
 for attendee in
   select distinct registration.user_id,edition.id edition_id
   from public.registrations registration
   join public.event_editions edition on edition.id=registration.edition_id
   join public.event_sessions session on session.edition_id=edition.id
   join public.venues venue on venue.id=session.venue_id
   where registration.status in ('registered','waitlisted')
     and venue.campus_id=target.campus_id
     and session.ends_at>ended
 loop
   perform private.enqueue_notification(attendee.user_id,attendee.edition_id,'venue_change','Campus route reopened','A previously closed campus route is available again.',jsonb_build_object('closure_id',target.id,'campus_id',target.campus_id));
   notified:=notified+1;
 end loop;
 insert into public.audit_records(actor_id,action,entity_type,entity_id,detail)
 values(actor,'route.reopen','route_closure',target.id,jsonb_build_object('edge_id',target.edge_id,'notified_attendees',notified,'ended_at',ended));
 return jsonb_build_object('closure_id',target.id,'persisted',true,'route_refresh_required',true,'idempotent_replay',false,'notified_attendees',notified,'ended_at',ended);
end $$;

revoke all on function public.end_route_closure(uuid) from public,anon;
grant execute on function public.end_route_closure(uuid) to authenticated;
