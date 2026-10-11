alter table public.venues add column destination_landmark_id uuid references public.landmarks(id) on delete set null;
alter table public.venues add column designated_gate_landmark_id uuid references public.landmarks(id) on delete set null;
create index venues_destination_landmark_idx on public.venues(destination_landmark_id);
create index venues_gate_landmark_idx on public.venues(designated_gate_landmark_id);

create function public.set_venue_navigation(p_venue_id uuid,p_destination_landmark_id uuid,p_designated_gate_landmark_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target public.venues; college uuid;
begin
  select * into target from public.venues where id=p_venue_id;
  select c.college_id into college from public.campuses c where c.id=target.campus_id;
  if actor is null or target.id is null or not private.is_college_admin(college,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}';
  end if;
  if not exists(select 1 from public.landmarks l where l.id=p_destination_landmark_id and l.campus_id=target.campus_id)
    or (p_designated_gate_landmark_id is not null and not exists(select 1 from public.landmarks l where l.id=p_designated_gate_landmark_id and l.campus_id=target.campus_id)) then
    raise sqlstate 'PGRST' using message='{"code":"INVALID_VENUE_LANDMARK","message":"Venue landmarks must belong to the same campus."}',detail='{"status":422}';
  end if;
  update public.venues set destination_landmark_id=p_destination_landmark_id,designated_gate_landmark_id=p_designated_gate_landmark_id where id=p_venue_id;
  insert into public.audit_records(actor_id,action,entity_type,entity_id,detail) values(actor,'venue.navigation','venue',p_venue_id,jsonb_build_object('destination_landmark_id',p_destination_landmark_id,'designated_gate_landmark_id',p_designated_gate_landmark_id));
  return jsonb_build_object('venue_id',p_venue_id,'persisted',true);
end $$;
revoke all on function public.set_venue_navigation(uuid,uuid,uuid) from public,anon;
grant execute on function public.set_venue_navigation(uuid,uuid,uuid) to authenticated;

create or replace view public.published_event_feed with (security_invoker=true) as
select e.id,e.title,e.description,e.category,e.visibility,e.price_minor,e.currency,e.eligibility,e.cover_image_path,e.published_at,
 e.college_id,c.name college_name,e.organization_id,o.name organization_name,
 ee.id edition_id,ee.registration_opens_at,ee.registration_closes_at,ee.starts_at,ee.ends_at,ee.capacity,ee.waitlist_enabled,
 venue.id venue_id,venue.name venue_name,venue.destination_landmark_id,venue.designated_gate_landmark_id
from public.events e join public.colleges c on c.id=e.college_id join public.organizations o on o.id=e.organization_id
join lateral(select edition.* from public.event_editions edition where edition.event_id=e.id order by edition.starts_at asc limit 1) ee on true
left join lateral(select es.venue_id from public.event_sessions es where es.edition_id=ee.id order by es.starts_at asc limit 1) session on true
left join public.venues venue on venue.id=session.venue_id where e.status='published';
grant select on public.published_event_feed to anon,authenticated;

create or replace view public.my_journey with (security_invoker=true) as
select r.id registration_id,r.status,r.registered_at,r.waitlisted_at,r.cancelled_at,ee.id edition_id,e.id event_id,e.title,e.category,e.status event_status,o.name organization_name,
 ee.starts_at,ee.ends_at,p.token pass_token,p.status pass_status,
 (select count(*)::integer from public.waitlist_entries ahead where ahead.edition_id=r.edition_id and ahead.status='waiting' and (ahead.joined_at,ahead.id)<=(w.joined_at,w.id)) waitlist_position,
 ee.registration_opens_at,ee.registration_closes_at,
 venue.id venue_id,venue.name venue_name,venue.destination_landmark_id,venue.designated_gate_landmark_id
from public.registrations r join public.event_editions ee on ee.id=r.edition_id join public.events e on e.id=ee.event_id join public.organizations o on o.id=e.organization_id
left join public.passes p on p.registration_id=r.id and p.status='active' left join public.waitlist_entries w on w.registration_id=r.id and w.status='waiting'
left join lateral(select es.venue_id from public.event_sessions es where es.edition_id=ee.id order by es.starts_at asc limit 1) session on true
left join public.venues venue on venue.id=session.venue_id;
grant select on public.my_journey to authenticated;
