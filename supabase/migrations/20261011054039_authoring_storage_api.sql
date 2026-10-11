-- Authenticated authoring APIs. Each function performs its authorization check
-- before writing and leaves a durable audit record.

create function public.create_campus(p_college_id uuid, p_name text, p_latitude double precision, p_longitude double precision)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); saved uuid;
begin
  if actor is null or not private.is_college_admin(p_college_id,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}';
  end if;
  insert into public.campuses(college_id,name,latitude,longitude)
  values(p_college_id,trim(p_name),p_latitude,p_longitude) returning id into saved;
  insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'campus.create','campus',saved);
  return jsonb_build_object('campus_id',saved,'persisted',true);
end; $$;

create function public.create_building(p_campus_id uuid, p_name text, p_latitude double precision, p_longitude double precision, p_orientation_degrees double precision default 0)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target_college uuid; saved uuid;
begin
  select college_id into target_college from public.campuses where id=p_campus_id;
  if actor is null or not private.is_college_admin(target_college,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}';
  end if;
  insert into public.buildings(campus_id,name,latitude,longitude,orientation_degrees)
  values(p_campus_id,trim(p_name),p_latitude,p_longitude,p_orientation_degrees) returning id into saved;
  insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'building.create','building',saved);
  return jsonb_build_object('building_id',saved,'persisted',true);
end; $$;

create function public.create_landmark(
  p_campus_id uuid,p_name text,p_coordinate_kind public.coordinate_kind,
  p_latitude double precision default null,p_longitude double precision default null,
  p_floor_id uuid default null,p_x_pixels double precision default null,p_y_pixels double precision default null,
  p_facing_degrees double precision default null,p_facing_instruction text default null,p_reference_photo_path text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target_college uuid; saved uuid;
begin
  select college_id into target_college from public.campuses where id=p_campus_id;
  if actor is null or not private.is_college_admin(target_college,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}';
  end if;
  if p_floor_id is not null and not exists (
    select 1 from public.floors f join public.buildings b on b.id=f.building_id
    where f.id=p_floor_id and b.campus_id=p_campus_id
  ) then raise sqlstate 'PGRST' using message='{"code":"INVALID_FLOOR","message":"The floor does not belong to this campus."}',detail='{"status":422}'; end if;
  insert into public.landmarks(campus_id,floor_id,name,coordinate_kind,latitude,longitude,x_pixels,y_pixels,reference_photo_path,facing_degrees,facing_instruction)
  values(p_campus_id,p_floor_id,trim(p_name),p_coordinate_kind,p_latitude,p_longitude,p_x_pixels,p_y_pixels,nullif(trim(p_reference_photo_path),''),p_facing_degrees,nullif(trim(p_facing_instruction),'')) returning id into saved;
  insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'landmark.create','landmark',saved);
  return jsonb_build_object('landmark_id',saved,'persisted',true);
end; $$;

create function public.create_route_draft(p_campus_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target_college uuid; next_version integer; saved uuid;
begin
  select college_id into target_college from public.campuses where id=p_campus_id;
  if actor is null or not private.is_college_admin(target_college,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}';
  end if;
  select coalesce(max(version),0)+1 into next_version from public.route_versions where campus_id=p_campus_id;
  insert into public.route_versions(campus_id,version) values(p_campus_id,next_version) returning id into saved;
  insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'route.create','route_version',saved);
  return jsonb_build_object('route_version_id',saved,'version',next_version,'status','draft');
end; $$;

create function public.add_route_node(
  p_route_version_id uuid,p_node_kind text,p_coordinate_kind public.coordinate_kind,p_landmark_id uuid default null,
  p_latitude double precision default null,p_longitude double precision default null,p_floor_id uuid default null,
  p_x_pixels double precision default null,p_y_pixels double precision default null,p_is_accessible boolean default true
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target_college uuid; saved uuid;
begin
  select c.college_id into target_college from public.route_versions rv join public.campuses c on c.id=rv.campus_id where rv.id=p_route_version_id and rv.status='draft';
  if actor is null or not private.is_college_admin(target_college,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"A draft route and college administrator access are required."}',detail='{"status":403}';
  end if;
  insert into public.route_nodes(route_version_id,floor_id,landmark_id,coordinate_kind,latitude,longitude,x_pixels,y_pixels,node_kind,is_accessible)
  values(p_route_version_id,p_floor_id,p_landmark_id,p_coordinate_kind,p_latitude,p_longitude,p_x_pixels,p_y_pixels,p_node_kind,p_is_accessible) returning id into saved;
  return jsonb_build_object('node_id',saved,'persisted',true);
end; $$;

create function public.add_route_edge(
  p_route_version_id uuid,p_from_node_id uuid,p_to_node_id uuid,p_kind public.route_edge_kind,
  p_distance_meters double precision,p_geometry jsonb,p_instruction text,p_is_accessible boolean default true,p_is_bidirectional boolean default true
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target_college uuid; saved uuid;
begin
  select c.college_id into target_college from public.route_versions rv join public.campuses c on c.id=rv.campus_id where rv.id=p_route_version_id and rv.status='draft';
  if actor is null or not private.is_college_admin(target_college,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"A draft route and college administrator access are required."}',detail='{"status":403}';
  end if;
  insert into public.route_edges(route_version_id,from_node_id,to_node_id,kind,distance_meters,geometry,instruction,is_accessible,is_bidirectional)
  values(p_route_version_id,p_from_node_id,p_to_node_id,p_kind,p_distance_meters,coalesce(p_geometry,'[]'::jsonb),trim(p_instruction),p_is_accessible,p_is_bidirectional) returning id into saved;
  return jsonb_build_object('edge_id',saved,'persisted',true);
end; $$;

create function public.assign_context_role(p_organization_id uuid,p_user_id uuid,p_role public.membership_role)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); target_college uuid;
begin
  select college_id into target_college from public.organizations where id=p_organization_id;
  if actor is null or (
    not private.is_college_admin(target_college,actor)
    and not private.has_organization_role(p_organization_id,array['organizer']::public.membership_role[],actor)
  ) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer or college administrator access is required."}',detail='{"status":403}'; end if;
  if not exists(select 1 from public.profiles where id=p_user_id) then
    raise sqlstate 'PGRST' using message='{"code":"UNKNOWN_USER","message":"The user must create an account before they can be invited."}',detail='{"status":422}';
  end if;
  insert into public.memberships(organization_id,user_id,role,status,invited_by)
  values(p_organization_id,p_user_id,p_role,'invited',actor)
  on conflict(organization_id,user_id,role) do update set status='invited',invited_by=actor,updated_at=now();
  insert into public.audit_records(actor_id,action,entity_type,entity_id,detail)
  values(actor,'membership.invite','organization',p_organization_id,jsonb_build_object('user_id',p_user_id,'role',p_role));
  return jsonb_build_object('organization_id',p_organization_id,'user_id',p_user_id,'role',p_role,'status','invited');
end; $$;

do $$ declare signature text; begin
  foreach signature in array array[
    'public.create_campus(uuid,text,double precision,double precision)',
    'public.create_building(uuid,text,double precision,double precision,double precision)',
    'public.create_landmark(uuid,text,public.coordinate_kind,double precision,double precision,uuid,double precision,double precision,double precision,text,text)',
    'public.create_route_draft(uuid)',
    'public.add_route_node(uuid,text,public.coordinate_kind,uuid,double precision,double precision,uuid,double precision,double precision,boolean)',
    'public.add_route_edge(uuid,uuid,uuid,public.route_edge_kind,double precision,jsonb,text,boolean,boolean)',
    'public.assign_context_role(uuid,uuid,public.membership_role)'
  ] loop execute 'revoke all on function '||signature||' from public,anon'; execute 'grant execute on function '||signature||' to authenticated'; end loop;
end $$;

-- Private media buckets. Object paths begin with the owning college UUID.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
('event-media','event-media',false,10485760,array['image/jpeg','image/png','image/webp']),
('campus-media','campus-media',false,20971520,array['image/jpeg','image/png','image/webp','application/pdf']),
('report-attachments','report-attachments',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do nothing;

create policy "authenticated_media_read" on storage.objects for select to authenticated
using (bucket_id in ('event-media','campus-media','report-attachments'));

create policy "college_admin_media_insert" on storage.objects for insert to authenticated
with check (
  bucket_id in ('event-media','campus-media')
  and private.is_college_admin(((storage.foldername(name))[1])::uuid)
);

create policy "college_admin_media_update" on storage.objects for update to authenticated
using (bucket_id in ('event-media','campus-media') and private.is_college_admin(((storage.foldername(name))[1])::uuid))
with check (bucket_id in ('event-media','campus-media') and private.is_college_admin(((storage.foldername(name))[1])::uuid));

create policy "reporter_attachment_insert" on storage.objects for insert to authenticated
with check (bucket_id='report-attachments' and owner_id=(select auth.uid()::text));
