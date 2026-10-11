create function public.create_event_edition(
  p_event_id uuid, p_label text, p_registration_opens_at timestamptz,
  p_registration_closes_at timestamptz, p_starts_at timestamptz,
  p_ends_at timestamptz, p_capacity integer, p_waitlist_enabled boolean default true
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); saved uuid;
begin
  if actor is null or not private.can_manage_event(p_event_id,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer access is required."}',detail='{"status":403}';
  end if;
  insert into public.event_editions(event_id,label,registration_opens_at,registration_closes_at,starts_at,ends_at,capacity,waitlist_enabled)
  values(p_event_id,trim(p_label),p_registration_opens_at,p_registration_closes_at,p_starts_at,p_ends_at,p_capacity,p_waitlist_enabled)
  returning id into saved;
  insert into public.channels(edition_id,name) values(saved,'Event discussion');
  insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'edition.create','event_edition',saved);
  return jsonb_build_object('edition_id',saved,'persisted',true);
end $$;

create function public.set_event_cover_image(p_event_id uuid,p_path text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); expected_prefix text;
begin
  if actor is null or not private.can_manage_event(p_event_id,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer access is required."}',detail='{"status":403}';
  end if;
  select college_id::text||'/'||id::text||'/' into expected_prefix from public.events where id=p_event_id;
  if p_path is null or position(expected_prefix in p_path)<>1 then
    raise sqlstate 'PGRST' using message='{"code":"INVALID_MEDIA_PATH","message":"The media path does not belong to this event."}',detail='{"status":422}';
  end if;
  update public.events set cover_image_path=p_path,updated_at=now() where id=p_event_id;
  insert into public.audit_records(actor_id,action,entity_type,entity_id,detail) values(actor,'event.cover_image','event',p_event_id,jsonb_build_object('path',p_path));
  return jsonb_build_object('event_id',p_event_id,'path',p_path,'persisted',true);
end $$;

create function public.get_registration_roster(p_edition_id uuid)
returns table(registration_id uuid,user_id uuid,full_name text,status public.registration_status,registered_at timestamptz,waitlist_position bigint,pass_status public.pass_status)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.can_manage_edition(p_edition_id,auth.uid()) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Event staff access is required."}',detail='{"status":403}';
  end if;
  return query select r.id,r.user_id,p.full_name,r.status,r.registered_at,
    case when w.status='waiting' then row_number() over(partition by w.edition_id,w.status order by w.joined_at,w.id) end,
    ps.status
  from public.registrations r join public.profiles p on p.id=r.user_id
  left join public.waitlist_entries w on w.registration_id=r.id
  left join public.passes ps on ps.registration_id=r.id
  where r.edition_id=p_edition_id order by r.created_at;
end $$;

create function public.correct_occupancy(p_edition_id uuid,p_delta integer,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); saved uuid;
begin
  if actor is null or not private.can_manage_edition(p_edition_id,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Event staff access is required."}',detail='{"status":403}';
  end if;
  insert into public.occupancy_corrections(edition_id,delta,reason,corrected_by)
  values(p_edition_id,p_delta,trim(p_reason),actor) returning id into saved;
  insert into public.audit_records(actor_id,action,entity_type,entity_id,detail)
  values(actor,'occupancy.correct','occupancy_correction',saved,jsonb_build_object('edition_id',p_edition_id,'delta',p_delta,'reason',trim(p_reason)));
  return jsonb_build_object('correction_id',saved,'persisted',true);
end $$;

revoke all on function public.create_event_edition(uuid,text,timestamptz,timestamptz,timestamptz,timestamptz,integer,boolean) from public,anon;
revoke all on function public.set_event_cover_image(uuid,text) from public,anon;
revoke all on function public.get_registration_roster(uuid) from public,anon;
revoke all on function public.correct_occupancy(uuid,integer,text) from public,anon;
grant execute on function public.create_event_edition(uuid,text,timestamptz,timestamptz,timestamptz,timestamptz,integer,boolean) to authenticated;
grant execute on function public.set_event_cover_image(uuid,text) to authenticated;
grant execute on function public.get_registration_roster(uuid) to authenticated;
grant execute on function public.correct_occupancy(uuid,integer,text) to authenticated;

create policy campus_media_published_read on storage.objects for select to anon,authenticated using (
  bucket_id='campus-media' and (
    exists(select 1 from public.floors f where f.floor_plan_path=name and f.is_published)
    or exists(select 1 from public.landmarks l where l.reference_photo_path=name and l.is_active)
  )
);

create or replace view public.my_journey with (security_invoker=true) as
select r.id registration_id,r.status,r.registered_at,r.waitlisted_at,r.cancelled_at,
  ee.id edition_id,e.id event_id,e.title,e.category,e.status event_status,o.name organization_name,
  ee.starts_at,ee.ends_at,
  p.token pass_token,p.status pass_status,
  (select count(*)::integer from public.waitlist_entries ahead where ahead.edition_id=r.edition_id and ahead.status='waiting' and (ahead.joined_at,ahead.id)<=(w.joined_at,w.id)) waitlist_position,
  ee.registration_opens_at,ee.registration_closes_at
from public.registrations r join public.event_editions ee on ee.id=r.edition_id
join public.events e on e.id=ee.event_id join public.organizations o on o.id=e.organization_id
left join public.passes p on p.registration_id=r.id and p.status='active'
left join public.waitlist_entries w on w.registration_id=r.id and w.status='waiting';
grant select on public.my_journey to authenticated;
