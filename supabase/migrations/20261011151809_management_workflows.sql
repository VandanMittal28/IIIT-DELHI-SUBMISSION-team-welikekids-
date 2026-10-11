create table public.event_cohosts (
  event_id uuid not null references public.events(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  added_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key(event_id,organization_id)
);

create table public.saved_events (
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_id uuid not null references public.events(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id,event_id)
);

create function private.can_manage_event(target_event_id uuid,target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path='' as $$
 select target_user_id is not null and exists(
   select 1 from public.events e where e.id=target_event_id and (
     private.is_college_admin(e.college_id,target_user_id)
     or private.has_organization_role(e.organization_id,array['organizer']::public.membership_role[],target_user_id)
   )
 );
$$;
revoke all on function private.can_manage_event(uuid,uuid) from public;
grant execute on function private.can_manage_event(uuid,uuid) to authenticated;

alter table public.campuses add column route_change_sequence bigint not null default 0;
alter table public.event_cohosts enable row level security;
alter table public.saved_events enable row level security;
create policy event_cohosts_anon_read on public.event_cohosts for select to anon
using (exists(select 1 from public.events e where e.id=event_id and e.status='published'));
create policy event_cohosts_authenticated_read on public.event_cohosts for select to authenticated
using (exists(select 1 from public.events e where e.id=event_id and e.status='published') or private.can_manage_event(event_id));
create policy saved_events_self on public.saved_events for all to authenticated
using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id);
grant select on public.event_cohosts to anon,authenticated;
grant select,insert,delete on public.saved_events to authenticated;
create index event_cohosts_organization_idx on public.event_cohosts(organization_id);
create index saved_events_event_idx on public.saved_events(event_id);

create function public.create_organization(p_college_id uuid,p_name text,p_slug text,p_description text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); saved uuid;
begin
 if actor is null or not private.is_college_admin(p_college_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}'; end if;
 insert into public.organizations(college_id,name,slug,description) values(p_college_id,trim(p_name),lower(trim(p_slug)),nullif(trim(p_description),'')) returning id into saved;
 insert into public.memberships(organization_id,user_id,role,status,invited_by) values(saved,actor,'organizer','active',actor);
 insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'organization.create','organization',saved);
 return jsonb_build_object('organization_id',saved,'persisted',true);
end $$;

create function public.update_event_details(p_event_id uuid,p_title text,p_description text,p_category text,p_eligibility text,p_price_minor integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null or not private.can_manage_event(p_event_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer access is required."}',detail='{"status":403}'; end if;
 update public.events set title=trim(p_title),description=trim(p_description),category=trim(p_category),eligibility=nullif(trim(p_eligibility),''),price_minor=p_price_minor,updated_at=now() where id=p_event_id;
 insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'event.update','event',p_event_id);
 return jsonb_build_object('event_id',p_event_id,'persisted',true);
end $$;

create function public.cancel_event(p_event_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); edition record; attendee record;
begin
 if actor is null or not private.can_manage_event(p_event_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer access is required."}',detail='{"status":403}'; end if;
 update public.events set status='cancelled',updated_at=now() where id=p_event_id;
 for edition in select id from public.event_editions where event_id=p_event_id loop
   insert into public.announcements(edition_id,title,body,kind,created_by) values(edition.id,'Event cancelled',trim(p_reason),'emergency',actor);
   for attendee in select user_id from public.registrations where edition_id=edition.id and status in ('registered','waitlisted') loop
     perform private.enqueue_notification(attendee.user_id,edition.id,'event_cancelled','Event cancelled',trim(p_reason),jsonb_build_object('event_id',p_event_id));
   end loop;
 end loop;
 insert into public.audit_records(actor_id,action,entity_type,entity_id,detail) values(actor,'event.cancel','event',p_event_id,jsonb_build_object('reason',trim(p_reason)));
 return jsonb_build_object('event_id',p_event_id,'status','cancelled','persisted',true);
end $$;

create function public.update_edition_capacity(p_edition_id uuid,p_capacity integer,p_waitlist_enabled boolean,p_reentry_allowed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); registered_count integer;
begin
 if actor is null or not private.can_manage_edition(p_edition_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer access is required."}',detail='{"status":403}'; end if;
 select count(*) into registered_count from public.registrations where edition_id=p_edition_id and status='registered';
 if p_capacity<registered_count then raise sqlstate 'PGRST' using message='{"code":"CAPACITY_BELOW_REGISTRATION","message":"Capacity cannot be below confirmed registrations."}',detail='{"status":409}'; end if;
 update public.event_editions set capacity=p_capacity,waitlist_enabled=p_waitlist_enabled,reentry_allowed=p_reentry_allowed where id=p_edition_id;
 insert into public.audit_records(actor_id,action,entity_type,entity_id,detail) values(actor,'edition.capacity','event_edition',p_edition_id,jsonb_build_object('capacity',p_capacity));
 return jsonb_build_object('edition_id',p_edition_id,'capacity',p_capacity,'persisted',true);
end $$;

create function public.create_venue(p_campus_id uuid,p_name text,p_kind text,p_latitude double precision default null,p_longitude double precision default null,p_accessibility_notes text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); college uuid; saved uuid;
begin
 select college_id into college from public.campuses where id=p_campus_id;
 if actor is null or not private.is_college_admin(college,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}'; end if;
 insert into public.venues(campus_id,name,kind,latitude,longitude,accessibility_notes) values(p_campus_id,trim(p_name),p_kind,p_latitude,p_longitude,nullif(trim(p_accessibility_notes),'')) returning id into saved;
 insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'venue.create','venue',saved);
 return jsonb_build_object('venue_id',saved,'persisted',true);
end $$;

create function public.create_floor(p_building_id uuid,p_name text,p_level integer,p_floor_plan_path text,p_image_width_pixels integer,p_image_height_pixels integer,p_meters_per_pixel double precision,p_rotation_degrees double precision default 0,p_origin_latitude double precision default null,p_origin_longitude double precision default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); college uuid; saved uuid;
begin
 select c.college_id into college from public.buildings b join public.campuses c on c.id=b.campus_id where b.id=p_building_id;
 if actor is null or not private.is_college_admin(college,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}'; end if;
 insert into public.floors(building_id,name,level,floor_plan_path,image_width_pixels,image_height_pixels,meters_per_pixel,rotation_degrees,origin_latitude,origin_longitude)
 values(p_building_id,trim(p_name),p_level,nullif(trim(p_floor_plan_path),''),p_image_width_pixels,p_image_height_pixels,p_meters_per_pixel,p_rotation_degrees,p_origin_latitude,p_origin_longitude) returning id into saved;
 insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'floor.create','floor',saved);
 return jsonb_build_object('floor_id',saved,'persisted',true);
end $$;

create function public.create_event_session(p_edition_id uuid,p_venue_id uuid,p_title text,p_starts_at timestamptz,p_ends_at timestamptz)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); saved uuid;
begin
 if actor is null or not private.can_manage_edition(p_edition_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer access is required."}',detail='{"status":403}'; end if;
 insert into public.event_sessions(edition_id,venue_id,title,starts_at,ends_at) values(p_edition_id,p_venue_id,trim(p_title),p_starts_at,p_ends_at) returning id into saved;
 insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'session.create','event_session',saved);
 return jsonb_build_object('session_id',saved,'persisted',true);
end $$;

create function public.assign_event_staff(p_edition_id uuid,p_user_id uuid,p_role public.membership_role)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null or not private.can_manage_edition(p_edition_id,actor) or p_role not in ('event_volunteer','organizer') then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer access and a valid staff role are required."}',detail='{"status":403}'; end if;
 insert into public.event_staff_assignments(edition_id,user_id,role,assigned_by) values(p_edition_id,p_user_id,p_role,actor) on conflict(edition_id,user_id,role) do nothing;
 insert into public.audit_records(actor_id,action,entity_type,entity_id,detail) values(actor,'staff.assign','event_edition',p_edition_id,jsonb_build_object('user_id',p_user_id,'role',p_role));
 return jsonb_build_object('edition_id',p_edition_id,'user_id',p_user_id,'role',p_role,'persisted',true);
end $$;

create function public.add_event_cohost(p_event_id uuid,p_organization_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); event_college uuid; org_college uuid;
begin
 select college_id into event_college from public.events where id=p_event_id;
 select college_id into org_college from public.organizations where id=p_organization_id;
 if actor is null or not private.can_manage_event(p_event_id,actor) or event_college<>org_college then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer access and a same-college co-host are required."}',detail='{"status":403}'; end if;
 insert into public.event_cohosts(event_id,organization_id,added_by) values(p_event_id,p_organization_id,actor) on conflict do nothing;
 return jsonb_build_object('event_id',p_event_id,'organization_id',p_organization_id,'persisted',true);
end $$;

create function public.add_route_closure(p_edge_id uuid,p_reason text,p_starts_at timestamptz default now(),p_ends_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target record; saved uuid;
begin
 select e.route_version_id,rv.campus_id,c.college_id into target from public.route_edges e join public.route_versions rv on rv.id=e.route_version_id join public.campuses c on c.id=rv.campus_id where e.id=p_edge_id;
 if actor is null or not private.is_college_admin(target.college_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}'; end if;
 insert into public.route_closures(edge_id,reason,starts_at,ends_at,created_by) values(p_edge_id,trim(p_reason),p_starts_at,p_ends_at,actor) returning id into saved;
 update public.campuses set route_change_sequence=route_change_sequence+1 where id=target.campus_id;
 insert into public.audit_records(actor_id,action,entity_type,entity_id,detail) values(actor,'route.close','route_closure',saved,jsonb_build_object('edge_id',p_edge_id));
 return jsonb_build_object('closure_id',saved,'persisted',true,'route_refresh_required',true);
end $$;

do $$ declare signature text; begin foreach signature in array array[
'public.create_organization(uuid,text,text,text)','public.update_event_details(uuid,text,text,text,text,integer)','public.cancel_event(uuid,text)',
'public.update_edition_capacity(uuid,integer,boolean,boolean)','public.create_venue(uuid,text,text,double precision,double precision,text)',
'public.create_floor(uuid,text,integer,text,integer,integer,double precision,double precision,double precision,double precision)',
'public.create_event_session(uuid,uuid,text,timestamp with time zone,timestamp with time zone)','public.assign_event_staff(uuid,uuid,public.membership_role)',
'public.add_event_cohost(uuid,uuid)','public.add_route_closure(uuid,text,timestamp with time zone,timestamp with time zone)'
] loop execute 'revoke all on function '||signature||' from public,anon'; execute 'grant execute on function '||signature||' to authenticated'; end loop; end $$;

create policy "event_media_staff_insert" on storage.objects for insert to authenticated with check (
 bucket_id='event-media' and exists(select 1 from public.events e where e.id=((storage.foldername(name))[2])::uuid and e.college_id=((storage.foldername(name))[1])::uuid and private.can_manage_event(e.id))
);
