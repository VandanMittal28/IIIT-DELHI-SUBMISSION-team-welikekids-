alter table public.route_closures add column client_request_id uuid;
create unique index route_closures_creator_request_idx
  on public.route_closures(created_by,client_request_id)
  where client_request_id is not null;

drop function public.add_route_closure(uuid,text,timestamptz,timestamptz);

create function public.add_route_closure(
  p_edge_id uuid,
  p_reason text,
  p_starts_at timestamptz default clock_timestamp(),
  p_ends_at timestamptz default null,
  p_client_request_id uuid default gen_random_uuid()
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target record; saved uuid; attendee record; notified integer:=0;
begin
 select edge.route_version_id,version.campus_id,campus.college_id
 into target
 from public.route_edges edge
 join public.route_versions version on version.id=edge.route_version_id
 join public.campuses campus on campus.id=version.campus_id
 where edge.id=p_edge_id;
 if actor is null or target.campus_id is null or not private.is_college_admin(target.college_id,actor) then
   raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}';
 end if;

 select id into saved from public.route_closures
 where created_by=actor and client_request_id=p_client_request_id;
 if saved is not null then
   return jsonb_build_object('closure_id',saved,'persisted',true,'route_refresh_required',true,'idempotent_replay',true);
 end if;

 insert into public.route_closures(edge_id,reason,starts_at,ends_at,created_by,client_request_id)
 values(p_edge_id,trim(p_reason),p_starts_at,p_ends_at,actor,p_client_request_id)
 on conflict(created_by,client_request_id) where client_request_id is not null do nothing
 returning id into saved;
 if saved is null then
   select id into saved from public.route_closures
   where created_by=actor and client_request_id=p_client_request_id;
   return jsonb_build_object('closure_id',saved,'persisted',true,'route_refresh_required',true,'idempotent_replay',true);
 end if;

 update public.campuses set route_change_sequence=route_change_sequence+1 where id=target.campus_id;
 for attendee in
   select distinct registration.user_id,edition.id edition_id
   from public.registrations registration
   join public.event_editions edition on edition.id=registration.edition_id
   join public.event_sessions session on session.edition_id=edition.id
   join public.venues venue on venue.id=session.venue_id
   where registration.status in ('registered','waitlisted')
     and venue.campus_id=target.campus_id
     and session.ends_at>p_starts_at
     and (p_ends_at is null or session.starts_at<p_ends_at)
 loop
   perform private.enqueue_notification(attendee.user_id,attendee.edition_id,'venue_change','Campus route changed',trim(p_reason),jsonb_build_object('closure_id',saved,'campus_id',target.campus_id));
   notified:=notified+1;
 end loop;
 insert into public.audit_records(actor_id,action,entity_type,entity_id,detail)
 values(actor,'route.close','route_closure',saved,jsonb_build_object('edge_id',p_edge_id,'notified_attendees',notified));
 return jsonb_build_object('closure_id',saved,'persisted',true,'route_refresh_required',true,'idempotent_replay',false,'notified_attendees',notified);
end $$;

revoke all on function public.add_route_closure(uuid,text,timestamptz,timestamptz,uuid) from public,anon;
grant execute on function public.add_route_closure(uuid,text,timestamptz,timestamptz,uuid) to authenticated;
