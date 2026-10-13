alter table public.announcements add column client_request_id uuid;
create unique index announcements_creator_request_idx
  on public.announcements(created_by,client_request_id)
  where client_request_id is not null;

drop function public.publish_announcement(uuid,text,text,text);
create function public.publish_announcement(
  p_edition_id uuid,p_title text,p_body text,p_kind text default 'official',p_client_request_id uuid default gen_random_uuid()
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); created_id uuid; attendee record; notified integer:=0;
begin
 if actor is null or not private.can_manage_edition(p_edition_id,actor) then
   raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Event staff access is required."}',detail='{"status":403}';
 end if;
 select id into created_id from public.announcements where created_by=actor and client_request_id=p_client_request_id;
 if created_id is not null then
   return jsonb_build_object('announcement_id',created_id,'persisted',true,'idempotent_replay',true);
 end if;
 insert into public.announcements(edition_id,title,body,kind,created_by,client_request_id)
 values(p_edition_id,trim(p_title),trim(p_body),p_kind,actor,p_client_request_id)
 on conflict(created_by,client_request_id) where client_request_id is not null do nothing
 returning id into created_id;
 if created_id is null then
   select id into created_id from public.announcements where created_by=actor and client_request_id=p_client_request_id;
   return jsonb_build_object('announcement_id',created_id,'persisted',true,'idempotent_replay',true);
 end if;
 for attendee in select user_id from public.registrations where edition_id=p_edition_id and status in ('registered','waitlisted') loop
   perform private.enqueue_notification(attendee.user_id,p_edition_id,p_kind,p_title,p_body,jsonb_build_object('announcement_id',created_id));
   notified:=notified+1;
 end loop;
 insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'announcement.publish','announcement',created_id);
 return jsonb_build_object('announcement_id',created_id,'persisted',true,'idempotent_replay',false,'notified_attendees',notified);
end $$;

drop function public.change_session_venue(uuid,uuid,text);
create function public.change_session_venue(p_session_id uuid,p_venue_id uuid,p_reason text,p_client_request_id uuid default gen_random_uuid())
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target record; venue_college uuid; notice jsonb;
begin
 select session.*,edition.id edition_id,event.college_id
 into target
 from public.event_sessions session
 join public.event_editions edition on edition.id=session.edition_id
 join public.events event on event.id=edition.event_id
 where session.id=p_session_id for update of session;
 if actor is null or target.id is null or not private.can_manage_edition(target.edition_id,actor) then
   raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Event staff access is required."}',detail='{"status":403}';
 end if;
 select campus.college_id into venue_college from public.venues venue join public.campuses campus on campus.id=venue.campus_id where venue.id=p_venue_id;
 if venue_college is null or venue_college<>target.college_id then
   raise sqlstate 'PGRST' using message='{"code":"INVALID_VENUE","message":"Choose a venue from the event college."}',detail='{"status":422}';
 end if;
 notice:=public.publish_announcement(target.edition_id,'Venue changed',trim(p_reason),'venue_change',p_client_request_id);
 if (notice->>'idempotent_replay')::boolean then
   return jsonb_build_object('session_id',p_session_id,'venue_id',p_venue_id,'announcement',notice,'persisted',true,'idempotent_replay',true);
 end if;
 update public.event_sessions set venue_id=p_venue_id where id=p_session_id;
 insert into public.audit_records(actor_id,action,entity_type,entity_id,detail)
 values(actor,'session.venue_change','event_session',p_session_id,jsonb_build_object('venue_id',p_venue_id,'request_id',p_client_request_id));
 return jsonb_build_object('session_id',p_session_id,'venue_id',p_venue_id,'announcement',notice,'persisted',true,'idempotent_replay',false);
end $$;

create or replace function public.cancel_event(p_event_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target public.events; edition record; attendee record; notified integer:=0;
begin
 select * into target from public.events where id=p_event_id for update;
 if actor is null or target.id is null or not private.can_manage_event(p_event_id,actor) then
   raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer access is required."}',detail='{"status":403}';
 end if;
 if target.status='cancelled' then
   return jsonb_build_object('event_id',p_event_id,'status','cancelled','persisted',true,'idempotent_replay',true);
 end if;
 update public.events set status='cancelled',cancelled_at=now(),updated_at=now() where id=p_event_id;
 for edition in select id from public.event_editions where event_id=p_event_id loop
   insert into public.announcements(edition_id,title,body,kind,created_by)
   values(edition.id,'Event cancelled',trim(p_reason),'emergency',actor);
   for attendee in select user_id from public.registrations where edition_id=edition.id and status in ('registered','waitlisted') loop
     perform private.enqueue_notification(attendee.user_id,edition.id,'event_cancelled','Event cancelled',trim(p_reason),jsonb_build_object('event_id',p_event_id));
     notified:=notified+1;
   end loop;
 end loop;
 insert into public.audit_records(actor_id,action,entity_type,entity_id,detail)
 values(actor,'event.cancel','event',p_event_id,jsonb_build_object('reason',trim(p_reason),'notified_attendees',notified));
 return jsonb_build_object('event_id',p_event_id,'status','cancelled','persisted',true,'idempotent_replay',false,'notified_attendees',notified);
end $$;

revoke all on function public.publish_announcement(uuid,text,text,text,uuid),public.change_session_venue(uuid,uuid,text,uuid),public.cancel_event(uuid,text) from public,anon;
grant execute on function public.publish_announcement(uuid,text,text,text,uuid),public.change_session_venue(uuid,uuid,text,uuid),public.cancel_event(uuid,text) to authenticated;
