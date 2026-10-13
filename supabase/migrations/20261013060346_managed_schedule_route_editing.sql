-- Keep contextual authority tied to an active account even if an older JWT is
-- still valid or the Auth session has not yet been administratively revoked.
create or replace function private.is_college_admin(target_college_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null
    and exists (select 1 from public.profiles profile where profile.id=target_user_id and profile.status='active')
    and exists (
      select 1 from public.college_memberships membership
      where membership.college_id=target_college_id and membership.user_id=target_user_id
        and membership.is_admin and membership.status='active'
    );
$$;

create or replace function private.has_organization_role(
  target_organization_id uuid,
  allowed_roles public.membership_role[],
  target_user_id uuid default auth.uid()
)
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null
    and exists (select 1 from public.profiles profile where profile.id=target_user_id and profile.status='active')
    and (
      exists (
        select 1 from public.memberships membership
        where membership.organization_id=target_organization_id and membership.user_id=target_user_id
          and membership.role=any(allowed_roles) and membership.status='active'
      )
      or exists (
        select 1 from public.organizations organization
        where organization.id=target_organization_id
          and private.is_college_admin(organization.college_id,target_user_id)
      )
    );
$$;

create or replace function private.can_manage_edition(target_edition_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null
    and exists (select 1 from public.profiles profile where profile.id=target_user_id and profile.status='active')
    and exists (
      select 1 from public.event_editions edition
      join public.events event on event.id=edition.event_id
      where edition.id=target_edition_id and (
        private.is_college_admin(event.college_id,target_user_id)
        or private.has_organization_role(event.organization_id,array['organizer']::public.membership_role[],target_user_id)
        or exists (
          select 1 from public.event_cohosts cohost
          where cohost.event_id=event.id
            and private.has_organization_role(cohost.organization_id,array['organizer']::public.membership_role[],target_user_id)
        )
        or exists (
          select 1 from public.event_staff_assignments assignment
          where assignment.edition_id=edition.id and assignment.user_id=target_user_id
        )
      )
    );
$$;

create or replace function private.can_access_edition(target_edition_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null
    and exists (
      select 1 from public.profiles profile
      where profile.id = target_user_id and profile.status = 'active'
    )
    and (
      exists (
        select 1 from public.registrations registration
        where registration.edition_id = target_edition_id
          and registration.user_id = target_user_id
          and registration.status <> 'cancelled'
      )
      or private.can_manage_edition(target_edition_id, target_user_id)
    );
$$;

revoke all on function private.can_access_edition(uuid, uuid) from public;
revoke all on function private.is_college_admin(uuid, uuid) from public;
revoke all on function private.has_organization_role(uuid, public.membership_role[], uuid) from public;
revoke all on function private.can_manage_edition(uuid, uuid) from public;
grant execute on function private.can_access_edition(uuid, uuid) to authenticated;
grant execute on function private.is_college_admin(uuid, uuid) to authenticated;
grant execute on function private.has_organization_role(uuid, public.membership_role[], uuid) to authenticated;
grant execute on function private.can_manage_edition(uuid, uuid) to authenticated;

create function public.update_event_session(
  p_session_id uuid,
  p_title text,
  p_venue_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  target record;
  venue_college uuid;
begin
  select session.id, session.edition_id, event.college_id,
         edition.starts_at as edition_starts_at, edition.ends_at as edition_ends_at
  into target
  from public.event_sessions session
  join public.event_editions edition on edition.id = session.edition_id
  join public.events event on event.id = edition.event_id
  where session.id = p_session_id
  for update of session;

  if actor is null or target.id is null or not private.can_manage_edition(target.edition_id, actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Event manager access is required."}',detail='{"status":403}';
  end if;
  if p_title is null or length(trim(p_title)) < 2 or p_starts_at is null or p_ends_at is null or p_starts_at >= p_ends_at
     or p_starts_at < target.edition_starts_at or p_ends_at > target.edition_ends_at then
    raise sqlstate 'PGRST' using message='{"code":"INVALID_SESSION","message":"Use a title and times within the edition schedule."}',detail='{"status":422}';
  end if;
  select campus.college_id into venue_college
  from public.venues venue join public.campuses campus on campus.id = venue.campus_id
  where venue.id = p_venue_id;
  if venue_college is distinct from target.college_id then
    raise sqlstate 'PGRST' using message='{"code":"INVALID_VENUE","message":"The venue must belong to the event college."}',detail='{"status":422}';
  end if;

  update public.event_sessions
  set title = trim(p_title), venue_id = p_venue_id, starts_at = p_starts_at, ends_at = p_ends_at
  where id = p_session_id;
  insert into public.audit_records(actor_id, action, entity_type, entity_id, detail)
  values(actor, 'session.update', 'event_session', p_session_id,
    jsonb_build_object('venue_id', p_venue_id, 'starts_at', p_starts_at, 'ends_at', p_ends_at));
  return jsonb_build_object('session_id', p_session_id, 'persisted', true);
end;
$$;

create function public.update_landmark(
  p_landmark_id uuid,
  p_name text,
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_floor_id uuid default null,
  p_x_pixels double precision default null,
  p_y_pixels double precision default null,
  p_facing_degrees double precision default null,
  p_facing_instruction text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  target record;
begin
  select landmark.id, landmark.campus_id, landmark.coordinate_kind, campus.college_id
  into target
  from public.landmarks landmark join public.campuses campus on campus.id = landmark.campus_id
  where landmark.id = p_landmark_id
  for update of landmark;
  if actor is null or target.id is null or not private.is_college_admin(target.college_id, actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}';
  end if;
  if p_name is null or length(trim(p_name)) < 2 or p_facing_degrees is not null and (p_facing_degrees < 0 or p_facing_degrees >= 360) then
    raise sqlstate 'PGRST' using message='{"code":"INVALID_LANDMARK","message":"The landmark name or facing direction is invalid."}',detail='{"status":422}';
  end if;
  if target.coordinate_kind = 'outdoor_geographic' and (
      p_floor_id is not null or p_x_pixels is not null or p_y_pixels is not null
      or p_latitude is null or p_longitude is null
    ) then
    raise sqlstate 'PGRST' using message='{"code":"INVALID_COORDINATES","message":"Outdoor landmarks require geographic coordinates only."}',detail='{"status":422}';
  end if;
  if target.coordinate_kind = 'indoor_floor' and (
      p_latitude is not null or p_longitude is not null
      or p_floor_id is null or p_x_pixels is null or p_y_pixels is null
      or not exists (
        select 1 from public.floors floor
        join public.buildings building on building.id = floor.building_id
        where floor.id = p_floor_id and building.campus_id = target.campus_id
      )
    ) then
    raise sqlstate 'PGRST' using message='{"code":"INVALID_COORDINATES","message":"Indoor landmarks require coordinates on a floor in the same campus."}',detail='{"status":422}';
  end if;

  update public.landmarks
  set name = trim(p_name), latitude = p_latitude, longitude = p_longitude,
      floor_id = p_floor_id, x_pixels = p_x_pixels, y_pixels = p_y_pixels,
      facing_degrees = p_facing_degrees,
      facing_instruction = nullif(trim(p_facing_instruction), '')
  where id = p_landmark_id;
  insert into public.audit_records(actor_id, action, entity_type, entity_id)
  values(actor, 'landmark.update', 'landmark', p_landmark_id);
  return jsonb_build_object('landmark_id', p_landmark_id, 'persisted', true);
end;
$$;

create function public.update_route_edge(
  p_edge_id uuid,
  p_kind public.route_edge_kind,
  p_distance_meters double precision,
  p_geometry jsonb,
  p_instruction text,
  p_is_accessible boolean,
  p_is_bidirectional boolean
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  target record;
begin
  select edge.id, edge.route_version_id, route.status, campus.college_id
  into target
  from public.route_edges edge
  join public.route_versions route on route.id = edge.route_version_id
  join public.campuses campus on campus.id = route.campus_id
  where edge.id = p_edge_id
  for update of edge;
  if actor is null or target.id is null or target.status <> 'draft'
     or not private.is_college_admin(target.college_id, actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"A draft route and college administrator access are required."}',detail='{"status":403}';
  end if;
  if p_distance_meters is null or p_distance_meters <= 0 or p_instruction is null or length(trim(p_instruction)) < 2
     or jsonb_typeof(coalesce(p_geometry, '[]'::jsonb)) <> 'array' then
    raise sqlstate 'PGRST' using message='{"code":"INVALID_EDGE","message":"Use a positive distance, instruction and geometry array."}',detail='{"status":422}';
  end if;
  update public.route_edges
  set kind = p_kind, distance_meters = p_distance_meters,
      geometry = coalesce(p_geometry, '[]'::jsonb), instruction = trim(p_instruction),
      is_accessible = p_is_accessible, is_bidirectional = p_is_bidirectional
  where id = p_edge_id;
  insert into public.audit_records(actor_id, action, entity_type, entity_id)
  values(actor, 'route.edge.update', 'route_edge', p_edge_id);
  return jsonb_build_object('edge_id', p_edge_id, 'persisted', true);
end;
$$;

do $$ declare signature text; begin
  foreach signature in array array[
    'public.update_event_session(uuid,text,uuid,timestamp with time zone,timestamp with time zone)',
    'public.update_landmark(uuid,text,double precision,double precision,uuid,double precision,double precision,double precision,text)',
    'public.update_route_edge(uuid,public.route_edge_kind,double precision,jsonb,text,boolean,boolean)'
  ] loop
    execute 'revoke all on function ' || signature || ' from public, anon';
    execute 'grant execute on function ' || signature || ' to authenticated';
  end loop;
end $$;
