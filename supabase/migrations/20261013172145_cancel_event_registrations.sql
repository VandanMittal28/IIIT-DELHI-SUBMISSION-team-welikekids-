create or replace function public.cancel_event(p_event_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor uuid:=auth.uid();
  target public.events;
  edition_row record;
  attendee record;
  notified integer:=0;
  cancelled_registrations integer:=0;
  cancelled_on timestamptz:=clock_timestamp();
  was_cancelled boolean;
begin
  select * into target from public.events where id=p_event_id for update;
  if actor is null or target.id is null or not private.can_manage_event(p_event_id,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer access is required."}',detail='{"status":403}';
  end if;

  was_cancelled:=target.status='cancelled';

  -- Serialize against registration allocation for every edition before changing
  -- event and attendee state.
  perform ee.id
  from public.event_editions ee
  where ee.event_id=p_event_id
  order by ee.id
  for update;

  if not was_cancelled then
    update public.events
    set status='cancelled',cancelled_at=cancelled_on,updated_at=cancelled_on
    where id=p_event_id;

    for edition_row in select id from public.event_editions where event_id=p_event_id loop
      insert into public.announcements(edition_id,title,body,kind,created_by)
      values(edition_row.id,'Event cancelled',trim(p_reason),'emergency',actor);
      for attendee in
        select user_id
        from public.registrations
        where edition_id=edition_row.id and status in ('registered','waitlisted')
      loop
        perform private.enqueue_notification(
          attendee.user_id,
          edition_row.id,
          'event_cancelled',
          'Event cancelled',
          trim(p_reason),
          jsonb_build_object('event_id',p_event_id)
        );
        notified:=notified+1;
      end loop;
    end loop;
  end if;

  update public.waitlist_entries waitlist
  set status='cancelled',cancelled_at=coalesce(waitlist.cancelled_at,cancelled_on)
  from public.registrations registration
  join public.event_editions edition on edition.id=registration.edition_id
  where waitlist.registration_id=registration.id
    and edition.event_id=p_event_id
    and waitlist.status='waiting';

  update public.passes pass
  set status='revoked',revoked_at=coalesce(pass.revoked_at,cancelled_on)
  from public.registrations registration
  join public.event_editions edition on edition.id=registration.edition_id
  where pass.registration_id=registration.id
    and edition.event_id=p_event_id
    and pass.status='active';

  update public.registrations registration
  set status='cancelled',cancelled_at=coalesce(registration.cancelled_at,cancelled_on),updated_at=cancelled_on
  from public.event_editions edition
  where registration.edition_id=edition.id
    and edition.event_id=p_event_id
    and registration.status in ('registered','waitlisted');
  get diagnostics cancelled_registrations=row_count;

  if was_cancelled then
    return jsonb_build_object(
      'event_id',p_event_id,
      'status','cancelled',
      'persisted',true,
      'idempotent_replay',true,
      'cancelled_registrations',cancelled_registrations
    );
  end if;

  insert into public.audit_records(actor_id,action,entity_type,entity_id,detail)
  values(
    actor,
    'event.cancel',
    'event',
    p_event_id,
    jsonb_build_object(
      'reason',trim(p_reason),
      'notified_attendees',notified,
      'cancelled_registrations',cancelled_registrations
    )
  );
  return jsonb_build_object(
    'event_id',p_event_id,
    'status','cancelled',
    'persisted',true,
    'idempotent_replay',false,
    'notified_attendees',notified,
    'cancelled_registrations',cancelled_registrations
  );
end $$;

revoke all on function public.cancel_event(uuid,text) from public,anon;
grant execute on function public.cancel_event(uuid,text) to authenticated;

comment on function public.cancel_event is
  'Atomically cancels an event, every active registration and waitlist entry, and every active attendee pass.';
