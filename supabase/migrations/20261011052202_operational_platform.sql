-- Remaining operational domain: authored navigation, attendance, community,
-- reports, reviews, durable notifications, and audit history.

create type public.route_version_status as enum ('draft', 'validated', 'published', 'retired');
create type public.coordinate_kind as enum ('outdoor_geographic', 'indoor_floor');
create type public.route_edge_kind as enum ('walkway', 'corridor', 'stairs', 'lift', 'entrance', 'doorway');
create type public.attendance_action as enum ('enter', 'exit', 'reenter');
create type public.report_status as enum ('submitted', 'acknowledged', 'assigned', 'in_progress', 'resolved');
create type public.report_priority as enum ('low', 'normal', 'high', 'urgent');
create type public.message_status as enum ('visible', 'hidden', 'removed');
create type public.notification_status as enum ('pending', 'processing', 'delivered', 'failed');

create table public.buildings (
  id uuid primary key default gen_random_uuid(),
  campus_id uuid not null references public.campuses(id) on delete cascade,
  name text not null check (length(trim(name)) between 2 and 160),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  orientation_degrees double precision not null default 0 check (orientation_degrees >= 0 and orientation_degrees < 360),
  created_at timestamptz not null default now(),
  unique (campus_id, name)
);

create table public.floors (
  id uuid primary key default gen_random_uuid(),
  building_id uuid not null references public.buildings(id) on delete cascade,
  name text not null,
  level integer not null,
  floor_plan_path text,
  image_width_pixels integer check (image_width_pixels > 0),
  image_height_pixels integer check (image_height_pixels > 0),
  meters_per_pixel double precision check (meters_per_pixel > 0),
  rotation_degrees double precision not null default 0 check (rotation_degrees >= 0 and rotation_degrees < 360),
  origin_latitude double precision check (origin_latitude between -90 and 90),
  origin_longitude double precision check (origin_longitude between -180 and 180),
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  unique (building_id, level),
  check (
    floor_plan_path is null
    or (image_width_pixels is not null and image_height_pixels is not null and meters_per_pixel is not null)
  )
);

create table public.landmarks (
  id uuid primary key default gen_random_uuid(),
  campus_id uuid not null references public.campuses(id) on delete cascade,
  floor_id uuid references public.floors(id) on delete cascade,
  venue_id uuid references public.venues(id) on delete set null,
  name text not null check (length(trim(name)) between 2 and 160),
  coordinate_kind public.coordinate_kind not null,
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  x_pixels double precision,
  y_pixels double precision,
  reference_photo_path text,
  facing_degrees double precision check (facing_degrees >= 0 and facing_degrees < 360),
  facing_instruction text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  check (
    (coordinate_kind = 'outdoor_geographic' and floor_id is null and latitude is not null and longitude is not null and x_pixels is null and y_pixels is null)
    or
    (coordinate_kind = 'indoor_floor' and floor_id is not null and x_pixels is not null and y_pixels is not null and latitude is null and longitude is null)
  )
);

create table public.route_versions (
  id uuid primary key default gen_random_uuid(),
  campus_id uuid not null references public.campuses(id) on delete cascade,
  version integer not null check (version > 0),
  status public.route_version_status not null default 'draft',
  physical_validation_complete boolean not null default false,
  validation_notes text,
  validated_by uuid references public.profiles(id) on delete set null,
  validated_at timestamptz,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  unique (campus_id, version),
  check ((status in ('validated', 'published') and validated_at is not null) or status not in ('validated', 'published')),
  check ((status = 'published' and published_at is not null) or status <> 'published')
);

create table public.route_nodes (
  id uuid primary key default gen_random_uuid(),
  route_version_id uuid not null references public.route_versions(id) on delete cascade,
  floor_id uuid references public.floors(id) on delete cascade,
  landmark_id uuid references public.landmarks(id) on delete set null,
  coordinate_kind public.coordinate_kind not null,
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  x_pixels double precision,
  y_pixels double precision,
  node_kind text not null check (node_kind in ('path', 'landmark', 'stairs', 'lift', 'entrance', 'hall')),
  is_accessible boolean not null default true,
  unique (route_version_id, id),
  check (
    (coordinate_kind = 'outdoor_geographic' and floor_id is null and latitude is not null and longitude is not null and x_pixels is null and y_pixels is null)
    or
    (coordinate_kind = 'indoor_floor' and floor_id is not null and x_pixels is not null and y_pixels is not null and latitude is null and longitude is null)
  )
);

create table public.route_edges (
  id uuid primary key default gen_random_uuid(),
  route_version_id uuid not null references public.route_versions(id) on delete cascade,
  from_node_id uuid not null,
  to_node_id uuid not null,
  kind public.route_edge_kind not null,
  distance_meters double precision not null check (distance_meters > 0),
  geometry jsonb not null default '[]'::jsonb check (jsonb_typeof(geometry) = 'array'),
  instruction text not null,
  is_accessible boolean not null default true,
  is_bidirectional boolean not null default true,
  created_at timestamptz not null default now(),
  foreign key (route_version_id, from_node_id) references public.route_nodes(route_version_id, id) on delete cascade,
  foreign key (route_version_id, to_node_id) references public.route_nodes(route_version_id, id) on delete cascade,
  check (from_node_id <> to_node_id)
);

create table public.route_closures (
  id uuid primary key default gen_random_uuid(),
  edge_id uuid not null references public.route_edges(id) on delete cascade,
  reason text not null check (length(trim(reason)) between 3 and 500),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (ends_at is null or ends_at > starts_at)
);

create table public.attendance_transitions (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references public.event_editions(id) on delete cascade,
  registration_id uuid not null references public.registrations(id) on delete cascade,
  pass_id uuid not null references public.passes(id) on delete restrict,
  action public.attendance_action not null,
  scanned_by uuid not null references public.profiles(id) on delete restrict,
  client_request_id uuid not null,
  recorded_at timestamptz not null default now(),
  unique (scanned_by, client_request_id)
);

create table public.occupancy_corrections (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references public.event_editions(id) on delete cascade,
  delta integer not null check (delta <> 0),
  reason text not null check (length(trim(reason)) between 5 and 500),
  corrected_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references public.event_editions(id) on delete cascade,
  title text not null check (length(trim(title)) between 2 and 160),
  body text not null check (length(trim(body)) between 2 and 5000),
  kind text not null default 'official' check (kind in ('official', 'venue_change', 'closure', 'emergency')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.channels (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null unique references public.event_editions(id) on delete cascade,
  is_locked boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.channels(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 2000),
  status public.message_status not null default 'visible',
  moderated_by uuid references public.profiles(id) on delete set null,
  moderated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.follows (
  user_id uuid not null references public.profiles(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, organization_id)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references public.event_editions(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete restrict,
  category text not null check (length(trim(category)) between 2 and 80),
  description text not null check (length(trim(description)) between 5 and 5000),
  priority public.report_priority not null default 'normal',
  status public.report_status not null default 'submitted',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table public.report_attachments (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports(id) on delete cascade,
  storage_path text not null,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.report_assignments (
  report_id uuid not null references public.reports(id) on delete cascade,
  assignee_id uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  primary key (report_id, assignee_id)
);

create table public.report_status_history (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports(id) on delete cascade,
  from_status public.report_status,
  to_status public.report_status not null,
  changed_by uuid not null references public.profiles(id) on delete restrict,
  note text,
  created_at timestamptz not null default now()
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  edition_id uuid not null references public.event_editions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  body text check (body is null or length(trim(body)) between 3 and 3000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, user_id)
);

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('ios')),
  environment text not null check (environment in ('sandbox', 'production')),
  is_active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  edition_id uuid references public.event_editions(id) on delete cascade,
  kind text not null,
  title text not null,
  body text not null,
  payload jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.notification_delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete cascade,
  device_token_id uuid not null references public.device_tokens(id) on delete cascade,
  status public.notification_status not null default 'pending',
  attempts integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  last_error text,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  unique (notification_id, device_token_id)
);

create table public.audit_records (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index buildings_campus_idx on public.buildings(campus_id);
create index floors_building_idx on public.floors(building_id);
create index landmarks_campus_idx on public.landmarks(campus_id);
create index landmarks_floor_idx on public.landmarks(floor_id);
create index landmarks_venue_idx on public.landmarks(venue_id);
create index route_versions_campus_status_idx on public.route_versions(campus_id, status, version desc);
create index route_nodes_version_idx on public.route_nodes(route_version_id);
create index route_nodes_floor_idx on public.route_nodes(floor_id);
create index route_nodes_landmark_idx on public.route_nodes(landmark_id);
create index route_edges_version_from_idx on public.route_edges(route_version_id, from_node_id);
create index route_edges_version_to_idx on public.route_edges(route_version_id, to_node_id);
create index route_closures_edge_active_idx on public.route_closures(edge_id, starts_at, ends_at);
create index attendance_edition_time_idx on public.attendance_transitions(edition_id, recorded_at);
create index attendance_registration_time_idx on public.attendance_transitions(registration_id, recorded_at desc);
create index attendance_pass_idx on public.attendance_transitions(pass_id);
create index occupancy_corrections_edition_idx on public.occupancy_corrections(edition_id);
create index announcements_edition_time_idx on public.announcements(edition_id, created_at desc);
create index messages_channel_time_idx on public.messages(channel_id, created_at);
create index messages_author_idx on public.messages(author_id);
create index follows_organization_idx on public.follows(organization_id);
create index reports_edition_status_idx on public.reports(edition_id, status, created_at);
create index reports_reporter_idx on public.reports(reporter_id);
create index report_attachments_report_idx on public.report_attachments(report_id);
create index report_attachments_uploader_idx on public.report_attachments(uploaded_by);
create index report_assignments_assignee_idx on public.report_assignments(assignee_id);
create index report_assignments_assigner_idx on public.report_assignments(assigned_by);
create index report_history_report_idx on public.report_status_history(report_id, created_at);
create index report_history_actor_idx on public.report_status_history(changed_by);
create index reviews_edition_idx on public.reviews(edition_id);
create index reviews_user_idx on public.reviews(user_id);
create index device_tokens_user_idx on public.device_tokens(user_id);
create index notifications_user_time_idx on public.notifications(user_id, created_at desc);
create index notifications_edition_idx on public.notifications(edition_id);
create index delivery_jobs_due_idx on public.notification_delivery_jobs(status, next_attempt_at);
create index delivery_jobs_device_idx on public.notification_delivery_jobs(device_token_id);
create index audit_actor_time_idx on public.audit_records(actor_id, created_at desc);

create function private.edition_event_id(target_edition_id uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select ee.event_id from public.event_editions ee where ee.id = target_edition_id;
$$;

create function private.can_access_edition(target_edition_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null and (
    exists (
      select 1 from public.registrations r
      where r.edition_id = target_edition_id and r.user_id = target_user_id and r.status <> 'cancelled'
    )
    or private.can_manage_edition(target_edition_id, target_user_id)
  );
$$;

revoke all on function private.edition_event_id(uuid) from public;
revoke all on function private.can_access_edition(uuid, uuid) from public;
grant execute on function private.edition_event_id(uuid) to authenticated;
grant execute on function private.can_access_edition(uuid, uuid) to authenticated;

-- Every exposed operational table is RLS protected.
alter table public.buildings enable row level security;
alter table public.floors enable row level security;
alter table public.landmarks enable row level security;
alter table public.route_versions enable row level security;
alter table public.route_nodes enable row level security;
alter table public.route_edges enable row level security;
alter table public.route_closures enable row level security;
alter table public.attendance_transitions enable row level security;
alter table public.occupancy_corrections enable row level security;
alter table public.announcements enable row level security;
alter table public.channels enable row level security;
alter table public.messages enable row level security;
alter table public.follows enable row level security;
alter table public.reports enable row level security;
alter table public.report_attachments enable row level security;
alter table public.report_assignments enable row level security;
alter table public.report_status_history enable row level security;
alter table public.reviews enable row level security;
alter table public.device_tokens enable row level security;
alter table public.notifications enable row level security;
alter table public.notification_delivery_jobs enable row level security;
alter table public.audit_records enable row level security;

create policy buildings_read on public.buildings for select to anon, authenticated using (true);
create policy floors_read on public.floors for select to anon, authenticated using (is_published or exists (select 1 from public.buildings b join public.campuses c on c.id=b.campus_id where b.id=building_id and private.is_college_admin(c.college_id)));
create policy landmarks_read on public.landmarks for select to anon, authenticated using (is_active);
create policy route_versions_read on public.route_versions for select to anon, authenticated using (status='published');
create policy route_nodes_read on public.route_nodes for select to anon, authenticated using (exists (select 1 from public.route_versions rv where rv.id=route_version_id and rv.status='published'));
create policy route_edges_read on public.route_edges for select to anon, authenticated using (exists (select 1 from public.route_versions rv where rv.id=route_version_id and rv.status='published'));
create policy route_closures_read on public.route_closures for select to anon, authenticated using (true);
create policy attendance_read on public.attendance_transitions for select to authenticated using (exists (select 1 from public.registrations r where r.id=registration_id and ((select auth.uid())=r.user_id or private.can_manage_edition(r.edition_id))));
create policy occupancy_corrections_read on public.occupancy_corrections for select to authenticated using (private.can_manage_edition(edition_id));
create policy announcements_read on public.announcements for select to authenticated using (private.can_access_edition(edition_id));
create policy channels_read on public.channels for select to authenticated using (private.can_access_edition(edition_id));
create policy messages_read on public.messages for select to authenticated using (status='visible' and exists (select 1 from public.channels c where c.id=channel_id and private.can_access_edition(c.edition_id)));
create policy follows_self on public.follows for all to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
create policy reports_read on public.reports for select to authenticated using ((select auth.uid())=reporter_id or private.can_manage_edition(edition_id));
create policy report_attachments_read on public.report_attachments for select to authenticated using (exists (select 1 from public.reports r where r.id=report_id and ((select auth.uid())=r.reporter_id or private.can_manage_edition(r.edition_id))));
create policy report_assignments_read on public.report_assignments for select to authenticated using ((select auth.uid())=assignee_id or exists (select 1 from public.reports r where r.id=report_id and private.can_manage_edition(r.edition_id)));
create policy report_history_read on public.report_status_history for select to authenticated using (exists (select 1 from public.reports r where r.id=report_id and ((select auth.uid())=r.reporter_id or private.can_manage_edition(r.edition_id))));
create policy reviews_read on public.reviews for select to anon, authenticated using (true);
create policy device_tokens_self on public.device_tokens for all to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
create policy notifications_self on public.notifications for select to authenticated using ((select auth.uid())=user_id);
create policy notifications_update_self on public.notifications for update to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);

grant select on public.buildings, public.floors, public.landmarks, public.route_versions, public.route_nodes, public.route_edges, public.route_closures to anon, authenticated;
grant select on public.attendance_transitions, public.occupancy_corrections, public.announcements, public.channels, public.messages, public.reports, public.report_attachments, public.report_assignments, public.report_status_history, public.device_tokens, public.notifications to authenticated;
grant select, insert, delete on public.follows to authenticated;
grant select on public.reviews to anon, authenticated;
grant insert, update, delete on public.device_tokens to authenticated;
grant update (read_at) on public.notifications to authenticated;

create view public.edition_occupancy
with (security_invoker = true)
as
select
  ee.id as edition_id,
  greatest(0,
    count(at.id) filter (where at.action in ('enter','reenter'))
    - count(at.id) filter (where at.action='exit')
    + coalesce((select sum(oc.delta) from public.occupancy_corrections oc where oc.edition_id=ee.id),0)
  )::integer as estimated_inside,
  max(at.recorded_at) as fresh_at
from public.event_editions ee
left join public.attendance_transitions at on at.edition_id=ee.id
group by ee.id;

create view public.event_review_summary
with (security_invoker = true)
as
select event_id, count(*)::integer as sample_size, avg(rating)::numeric(3,2) as average_rating
from public.reviews group by event_id;

grant select on public.edition_occupancy to authenticated;
grant select on public.event_review_summary to anon, authenticated;

create function private.enqueue_notification(
  target_user_id uuid,
  target_edition_id uuid,
  notification_kind text,
  notification_title text,
  notification_body text,
  notification_payload jsonb default '{}'::jsonb
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare created_id uuid;
begin
  insert into public.notifications(user_id, edition_id, kind, title, body, payload)
  values(target_user_id, target_edition_id, notification_kind, notification_title, notification_body, notification_payload)
  returning id into created_id;

  insert into public.notification_delivery_jobs(notification_id, device_token_id)
  select created_id, dt.id from public.device_tokens dt
  where dt.user_id=target_user_id and dt.is_active
  on conflict do nothing;
  return created_id;
end;
$$;
revoke all on function private.enqueue_notification(uuid,uuid,text,text,text,jsonb) from public;

create function public.calculate_route(
  p_start_landmark_id uuid,
  p_destination_landmark_id uuid,
  p_accessible_only boolean default false
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare selected_route record;
declare route_nodes_json jsonb;
declare route_edges_json jsonb;
begin
  with recursive
  version_choice as (
    select rv.* from public.route_versions rv
    join public.landmarks l on l.campus_id=rv.campus_id
    where l.id=p_start_landmark_id and rv.status='published'
    order by rv.version desc limit 1
  ),
  directed_edges as (
    select e.id, e.route_version_id, e.from_node_id, e.to_node_id, e.distance_meters, e.kind, e.geometry, e.instruction, e.is_accessible
    from public.route_edges e join version_choice v on v.id=e.route_version_id
    where (not p_accessible_only or e.is_accessible)
      and not exists (select 1 from public.route_closures c where c.edge_id=e.id and c.starts_at<=now() and (c.ends_at is null or c.ends_at>now()))
    union all
    select e.id, e.route_version_id, e.to_node_id, e.from_node_id, e.distance_meters, e.kind,
           (select coalesce(jsonb_agg(value order by ord desc),'[]'::jsonb) from jsonb_array_elements(e.geometry) with ordinality x(value,ord)),
           e.instruction, e.is_accessible
    from public.route_edges e join version_choice v on v.id=e.route_version_id
    where e.is_bidirectional and (not p_accessible_only or e.is_accessible)
      and not exists (select 1 from public.route_closures c where c.edge_id=e.id and c.starts_at<=now() and (c.ends_at is null or c.ends_at>now()))
  ),
  start_node as (
    select n.id, n.route_version_id from public.route_nodes n join version_choice v on v.id=n.route_version_id
    where n.landmark_id=p_start_landmark_id limit 1
  ),
  destination_node as (
    select n.id from public.route_nodes n join version_choice v on v.id=n.route_version_id
    where n.landmark_id=p_destination_landmark_id limit 1
  ),
  walk as (
    select s.route_version_id, s.id as node_id, array[s.id]::uuid[] as node_path, array[]::uuid[] as edge_path, 0::double precision as total_distance
    from start_node s
    union all
    select w.route_version_id, de.to_node_id, w.node_path || de.to_node_id, w.edge_path || de.id, w.total_distance + de.distance_meters
    from walk w join directed_edges de on de.from_node_id=w.node_id
    where not de.to_node_id=any(w.node_path) and cardinality(w.node_path)<200
  )
  select w.route_version_id, w.node_path, w.edge_path, w.total_distance
  into selected_route
  from walk w join destination_node d on d.id=w.node_id
  order by w.total_distance limit 1;

  if selected_route.route_version_id is null then
    raise sqlstate 'PGRST' using message = '{"code":"NO_ROUTE","message":"No published route is currently available."}', detail = '{"status":404}';
  end if;

  select jsonb_agg(jsonb_build_object(
    'id',n.id,'coordinate_kind',n.coordinate_kind,'floor_id',n.floor_id,
    'latitude',n.latitude,'longitude',n.longitude,'x_pixels',n.x_pixels,'y_pixels',n.y_pixels,
    'node_kind',n.node_kind,'landmark_id',n.landmark_id
  ) order by p.ordinality)
  into route_nodes_json
  from unnest(selected_route.node_path) with ordinality p(node_id,ordinality)
  join public.route_nodes n on n.id=p.node_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'kind',e.kind,'distance_meters',e.distance_meters,'geometry',e.geometry,
    'instruction',e.instruction,'from_node_id',p.from_node_id,'to_node_id',p.to_node_id
  ) order by p.ordinality),'[]'::jsonb)
  into route_edges_json
  from (
    select edge_id, ordinality,
           selected_route.node_path[ordinality] as from_node_id,
           selected_route.node_path[ordinality+1] as to_node_id
    from unnest(selected_route.edge_path) with ordinality ep(edge_id,ordinality)
  ) p join public.route_edges e on e.id=p.edge_id;

  return jsonb_build_object(
    'route_version_id',selected_route.route_version_id,
    'total_distance_meters',selected_route.total_distance,
    'physical_validation_complete',(select rv.physical_validation_complete from public.route_versions rv where rv.id=selected_route.route_version_id),
    'nodes',route_nodes_json,'edges',route_edges_json
  );
end;
$$;
revoke all on function public.calculate_route(uuid,uuid,boolean) from public;
grant execute on function public.calculate_route(uuid,uuid,boolean) to anon, authenticated;

create function public.publish_route_version(p_route_version_id uuid, p_validation_notes text, p_physical_validation_complete boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target public.route_versions;
begin
  select * into target from public.route_versions where id=p_route_version_id for update;
  if actor is null or target.id is null or not exists (
    select 1 from public.campuses c where c.id=target.campus_id and private.is_college_admin(c.college_id,actor)
  ) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}'; end if;
  if not exists(select 1 from public.route_nodes n where n.route_version_id=target.id)
     or not exists(select 1 from public.route_edges e where e.route_version_id=target.id) then
    raise sqlstate 'PGRST' using message='{"code":"ROUTE_INCOMPLETE","message":"Add route nodes and edges before publishing."}',detail='{"status":422}';
  end if;
  update public.route_versions set status='retired' where campus_id=target.campus_id and status='published' and id<>target.id;
  update public.route_versions set status='published',validation_notes=nullif(trim(p_validation_notes),''),physical_validation_complete=p_physical_validation_complete,validated_by=actor,validated_at=now(),published_at=now() where id=target.id;
  insert into public.audit_records(actor_id,action,entity_type,entity_id,detail) values(actor,'route.publish','route_version',target.id,jsonb_build_object('physical_validation_complete',p_physical_validation_complete));
  return jsonb_build_object('route_version_id',target.id,'status','published','physical_validation_complete',p_physical_validation_complete);
end;
$$;
revoke all on function public.publish_route_version(uuid,text,boolean) from public,anon;
grant execute on function public.publish_route_version(uuid,text,boolean) to authenticated;

create function public.record_attendance(p_pass_token uuid,p_action public.attendance_action,p_client_request_id uuid)
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
  insert into public.attendance_transitions(edition_id,registration_id,pass_id,action,scanned_by,client_request_id)
  values(target.edition_id,target.registration_id,target.pass_id,p_action,actor,p_client_request_id) returning id into transition_id;
  select estimated_inside into inside from public.edition_occupancy where edition_id=target.edition_id;
  return jsonb_build_object('transition_id',transition_id,'action',p_action,'estimated_inside',inside,'idempotent_replay',false);
end;
$$;
revoke all on function public.record_attendance(uuid,public.attendance_action,uuid) from public,anon;
grant execute on function public.record_attendance(uuid,public.attendance_action,uuid) to authenticated;

create function public.publish_announcement(p_edition_id uuid,p_title text,p_body text,p_kind text default 'official')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); created_id uuid; attendee record;
begin
  if actor is null or not private.can_manage_edition(p_edition_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Event staff access is required."}',detail='{"status":403}'; end if;
  insert into public.announcements(edition_id,title,body,kind,created_by) values(p_edition_id,trim(p_title),trim(p_body),p_kind,actor) returning id into created_id;
  for attendee in select user_id from public.registrations where edition_id=p_edition_id and status in ('registered','waitlisted') loop
    perform private.enqueue_notification(attendee.user_id,p_edition_id,'announcement',p_title,p_body,jsonb_build_object('announcement_id',created_id));
  end loop;
  insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'announcement.publish','announcement',created_id);
  return jsonb_build_object('announcement_id',created_id,'persisted',true);
end;
$$;
revoke all on function public.publish_announcement(uuid,text,text,text) from public,anon;
grant execute on function public.publish_announcement(uuid,text,text,text) to authenticated;

create function public.change_session_venue(p_session_id uuid,p_venue_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target record; notice jsonb;
begin
  select es.*,ee.id edition_id into target from public.event_sessions es join public.event_editions ee on ee.id=es.edition_id where es.id=p_session_id for update of es;
  if actor is null or target.id is null or not private.can_manage_edition(target.edition_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Event staff access is required."}',detail='{"status":403}'; end if;
  update public.event_sessions set venue_id=p_venue_id where id=p_session_id;
  notice:=public.publish_announcement(target.edition_id,'Venue changed',trim(p_reason),'venue_change');
  insert into public.audit_records(actor_id,action,entity_type,entity_id,detail) values(actor,'session.venue_change','event_session',p_session_id,jsonb_build_object('venue_id',p_venue_id));
  return jsonb_build_object('session_id',p_session_id,'venue_id',p_venue_id,'announcement',notice);
end;
$$;
revoke all on function public.change_session_venue(uuid,uuid,text) from public,anon;
grant execute on function public.change_session_venue(uuid,uuid,text) to authenticated;

create function public.submit_report(p_edition_id uuid,p_category text,p_description text,p_priority public.report_priority default 'normal')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); created_id uuid;
begin
  if actor is null or not private.can_access_edition(p_edition_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"An active event registration is required."}',detail='{"status":403}'; end if;
  insert into public.reports(edition_id,reporter_id,category,description,priority) values(p_edition_id,actor,trim(p_category),trim(p_description),p_priority) returning id into created_id;
  insert into public.report_status_history(report_id,to_status,changed_by) values(created_id,'submitted',actor);
  return jsonb_build_object('report_id',created_id,'status','submitted');
end;
$$;
revoke all on function public.submit_report(uuid,text,text,public.report_priority) from public,anon;
grant execute on function public.submit_report(uuid,text,text,public.report_priority) to authenticated;

create function public.transition_report(p_report_id uuid,p_status public.report_status,p_assignee_id uuid default null,p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target public.reports;
begin
  select * into target from public.reports where id=p_report_id for update;
  if actor is null or target.id is null or not private.can_manage_edition(target.edition_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Assigned event staff access is required."}',detail='{"status":403}'; end if;
  if (target.status='submitted' and p_status<>'acknowledged') or (target.status='acknowledged' and p_status not in ('assigned','in_progress')) or (target.status='assigned' and p_status<>'in_progress') or (target.status='in_progress' and p_status<>'resolved') or target.status='resolved' then
    raise sqlstate 'PGRST' using message='{"code":"INVALID_REPORT_TRANSITION","message":"That report status transition is not allowed."}',detail='{"status":409}';
  end if;
  update public.reports set status=p_status,updated_at=now(),resolved_at=case when p_status='resolved' then now() end where id=p_report_id;
  if p_assignee_id is not null then insert into public.report_assignments(report_id,assignee_id,assigned_by) values(p_report_id,p_assignee_id,actor) on conflict do nothing; end if;
  insert into public.report_status_history(report_id,from_status,to_status,changed_by,note) values(p_report_id,target.status,p_status,actor,nullif(trim(p_note),''));
  perform private.enqueue_notification(target.reporter_id,target.edition_id,'report_status','Report updated','Your report is now '||replace(p_status::text,'_',' ')||'.',jsonb_build_object('report_id',p_report_id));
  return jsonb_build_object('report_id',p_report_id,'status',p_status);
end;
$$;
revoke all on function public.transition_report(uuid,public.report_status,uuid,text) from public,anon;
grant execute on function public.transition_report(uuid,public.report_status,uuid,text) to authenticated;

create function public.post_message(p_channel_id uuid,p_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target public.channels; created_id uuid;
begin
  select * into target from public.channels where id=p_channel_id;
  if actor is null or target.id is null or target.is_locked or not private.can_access_edition(target.edition_id,actor) then raise sqlstate 'PGRST' using message='{"code":"CHANNEL_UNAVAILABLE","message":"This discussion is unavailable."}',detail='{"status":403}'; end if;
  insert into public.messages(channel_id,author_id,body) values(p_channel_id,actor,trim(p_body)) returning id into created_id;
  return jsonb_build_object('message_id',created_id,'persisted',true);
end;
$$;
revoke all on function public.post_message(uuid,text) from public,anon;
grant execute on function public.post_message(uuid,text) to authenticated;

create function public.moderate_message(p_message_id uuid,p_status public.message_status)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target record;
begin
  select m.*,c.edition_id into target from public.messages m join public.channels c on c.id=m.channel_id where m.id=p_message_id for update of m;
  if actor is null or target.id is null or not private.can_manage_edition(target.edition_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Moderator access is required."}',detail='{"status":403}'; end if;
  update public.messages set status=p_status,moderated_by=actor,moderated_at=now(),updated_at=now() where id=p_message_id;
  insert into public.audit_records(actor_id,action,entity_type,entity_id,detail) values(actor,'message.moderate','message',p_message_id,jsonb_build_object('status',p_status));
  return jsonb_build_object('message_id',p_message_id,'status',p_status);
end;
$$;
revoke all on function public.moderate_message(uuid,public.message_status) from public,anon;
grant execute on function public.moderate_message(uuid,public.message_status) to authenticated;

create function public.submit_review(p_edition_id uuid,p_rating integer,p_body text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target_event uuid; saved_id uuid;
begin
  if actor is null then raise sqlstate 'PGRST' using message='{"code":"AUTH_REQUIRED","message":"Sign in is required."}',detail='{"status":401}'; end if;
  select ee.event_id into target_event from public.event_editions ee where ee.id=p_edition_id;
  if not exists(select 1 from public.attendance_transitions at join public.registrations r on r.id=at.registration_id where r.edition_id=p_edition_id and r.user_id=actor and at.action in ('enter','reenter')) then
    raise sqlstate 'PGRST' using message='{"code":"ATTENDANCE_REQUIRED","message":"Only verified attendees can review this event."}',detail='{"status":403}';
  end if;
  insert into public.reviews(event_id,edition_id,user_id,rating,body) values(target_event,p_edition_id,actor,p_rating,nullif(trim(p_body),''))
  on conflict(event_id,user_id) do update set edition_id=excluded.edition_id,rating=excluded.rating,body=excluded.body,updated_at=now()
  returning id into saved_id;
  return jsonb_build_object('review_id',saved_id,'persisted',true);
end;
$$;
revoke all on function public.submit_review(uuid,integer,text) from public,anon;
grant execute on function public.submit_review(uuid,integer,text) to authenticated;

create function public.register_device_token(p_token text,p_environment text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); saved_id uuid;
begin
  if actor is null then raise sqlstate 'PGRST' using message='{"code":"AUTH_REQUIRED","message":"Sign in is required."}',detail='{"status":401}'; end if;
  insert into public.device_tokens(user_id,token,platform,environment) values(actor,trim(p_token),'ios',p_environment)
  on conflict(token) do update set user_id=actor,environment=excluded.environment,is_active=true,last_seen_at=now()
  returning id into saved_id;
  return jsonb_build_object('device_token_id',saved_id,'persisted',true);
end;
$$;
revoke all on function public.register_device_token(text,text) from public,anon;
grant execute on function public.register_device_token(text,text) to authenticated;

-- Realtime is an invalidation signal; durable rows remain authoritative.
alter publication supabase_realtime add table public.announcements;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.reports;
alter publication supabase_realtime add table public.notifications;
