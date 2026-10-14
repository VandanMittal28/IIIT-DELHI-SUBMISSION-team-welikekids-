-- Student-hosted Open Meetups.
-- Any active student with an administrator-granted college membership can host a meetup.
-- Hosting never grants recognition: host_verified still comes only from meetup_hosts.

-- Hosts are profiles; recognised-host cards remain optional.
alter table public.open_meetups drop constraint open_meetups_host_id_fkey;
alter table public.open_meetups
  add constraint open_meetups_host_id_fkey foreign key (host_id) references public.profiles(id) on delete restrict;

-- Public name a student chooses to show as host. Recognised hosts keep their host card name.
alter table public.open_meetups
  add column host_display_name text check (host_display_name is null or length(trim(host_display_name)) between 2 and 80);

-- The meetup's own host (active account) or the home college administrator can manage it.
create or replace function private.can_manage_open_meetup(target_meetup_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null and exists (
    select 1 from public.open_meetups meetup
    where meetup.id = target_meetup_id
      and (
        (
          meetup.host_id = target_user_id
          and exists (select 1 from public.profiles profile where profile.id = target_user_id and profile.status = 'active')
        )
        or private.is_college_admin(meetup.college_id, target_user_id)
      )
  );
$$;

-- Same columns as before (order preserved), host name falls back to the student's display name, plus is_host.
create or replace view public.open_meetup_feed
with (security_invoker = true)
as
select
  meetup.id,
  meetup.title,
  meetup.description,
  meetup.location_note,
  meetup.icebreaker,
  meetup.audience,
  meetup.capacity,
  meetup.going_count,
  meetup.starts_at,
  meetup.ends_at,
  meetup.status,
  meetup.college_id,
  home.name as college_name,
  coalesce(host.display_name, meetup.host_display_name, 'Sidequest student') as host_name,
  host.headline as host_headline,
  private.is_active_meetup_host(meetup.host_id) as host_verified,
  venue.id as venue_id,
  venue.name as venue_name,
  campus.name as campus_name,
  venue.destination_landmark_id,
  venue.designated_gate_landmark_id,
  coalesce((
    select array_agg(college.name order by college.name)
    from public.open_meetup_colleges allowed
    join public.colleges college on college.id = allowed.college_id
    where allowed.meetup_id = meetup.id
  ), '{}') as participating_colleges,
  (
    select registration.status
    from public.open_meetup_registrations registration
    where registration.meetup_id = meetup.id and registration.user_id = (select auth.uid())
  ) as my_status,
  private.is_eligible_for_open_meetup(meetup.id) as is_eligible,
  meetup.host_id = (select auth.uid()) as is_host
from public.open_meetups meetup
join public.colleges home on home.id = meetup.college_id
left join public.meetup_hosts host on host.user_id = meetup.host_id
join public.venues venue on venue.id = meetup.venue_id
join public.campuses campus on campus.id = venue.campus_id;

-- Read-only for signed-in students; drops the default write/anon grants the view received originally.
revoke all on public.open_meetup_feed from anon, authenticated;
grant select on public.open_meetup_feed to authenticated;

-- The signed-in student is always the host; no client-supplied host identity is accepted.
create function public.host_open_meetup(
  p_client_request_id uuid,
  p_college_id uuid,
  p_venue_id uuid,
  p_title text,
  p_description text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_capacity integer,
  p_host_display_name text,
  p_audience public.open_meetup_audience default 'selected_colleges',
  p_college_ids uuid[] default '{}',
  p_icebreaker text default null,
  p_location_note text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  venue_college uuid;
  upcoming integer;
  saved public.open_meetups;
  new_id uuid := gen_random_uuid();
begin
  if actor is null then
    raise sqlstate 'PGRST' using message = '{"code":"AUTH_REQUIRED","message":"Sign in is required."}', detail = '{"status":401}';
  end if;

  select * into saved from public.open_meetups where created_by = actor and client_request_id = p_client_request_id;
  if saved.id is not null then
    return jsonb_build_object('meetup_id', saved.id, 'status', saved.status, 'idempotent_replay', true);
  end if;

  if not exists (select 1 from public.profiles profile where profile.id = actor and profile.status = 'active')
    or not exists (
      select 1 from public.college_memberships membership
      where membership.user_id = actor and membership.college_id = p_college_id and membership.status = 'active'
    ) then
    raise sqlstate 'PGRST' using message = '{"code":"NOT_COLLEGE_MEMBER","message":"Only active students of this college can host a meetup here."}', detail = '{"status":403}';
  end if;

  select campus.college_id into venue_college
  from public.venues venue join public.campuses campus on campus.id = venue.campus_id
  where venue.id = p_venue_id;
  if venue_college is distinct from p_college_id then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_VENUE","message":"Choose a venue on your college campus."}', detail = '{"status":422}';
  end if;

  if p_starts_at is null or p_ends_at is null or p_starts_at <= now() or p_ends_at <= p_starts_at
    or p_ends_at > p_starts_at + interval '12 hours' or p_starts_at > now() + interval '180 days' then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_MEETUP_SCHEDULE","message":"Pick a future start time and an end time within 12 hours of it."}', detail = '{"status":422}';
  end if;

  if p_capacity is null or p_capacity not between 2 and 500 then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_CAPACITY","message":"Capacity must be between 2 and 500."}', detail = '{"status":422}';
  end if;

  if length(trim(coalesce(p_title, ''))) not between 3 and 120
    or length(trim(coalesce(p_description, ''))) not between 10 and 2000
    or length(trim(coalesce(p_host_display_name, ''))) not between 2 and 80
    or (nullif(trim(p_icebreaker), '') is not null and length(trim(p_icebreaker)) not between 10 and 280)
    or (nullif(trim(p_location_note), '') is not null and length(trim(p_location_note)) not between 2 and 160) then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_MEETUP_DETAILS","message":"Check the title, description, host name and icebreaker lengths."}', detail = '{"status":422}';
  end if;

  if p_audience = 'selected_colleges' and exists (
    select 1 from unnest(coalesce(p_college_ids, '{}'::uuid[])) as requested(college_id)
    where not exists (select 1 from public.colleges college where college.id = requested.college_id)
  ) then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_COLLEGE","message":"Choose available colleges."}', detail = '{"status":422}';
  end if;

  -- Serialize this student's hosting requests so the upcoming-meetup limit cannot be raced.
  perform 1 from public.profiles where id = actor for update;
  if not private.is_active_meetup_host(actor) then
    select count(*)::integer into upcoming
    from public.open_meetups meetup
    where meetup.host_id = actor and meetup.status <> 'cancelled' and meetup.ends_at > now();
    if upcoming >= 3 then
      raise sqlstate 'PGRST' using message = '{"code":"HOSTING_LIMIT","message":"You can host up to 3 upcoming meetups at a time."}', detail = '{"status":409}';
    end if;
  end if;

  insert into public.open_meetups (
    id, college_id, host_id, host_display_name, venue_id, title, description, location_note, icebreaker,
    audience, capacity, starts_at, ends_at, status, created_by, client_request_id, published_at
  ) values (
    new_id, p_college_id, actor, trim(p_host_display_name), p_venue_id, trim(p_title), trim(p_description), nullif(trim(p_location_note), ''),
    coalesce(nullif(trim(p_icebreaker), ''), private.default_meetup_icebreaker(new_id)),
    p_audience, p_capacity, p_starts_at, p_ends_at, 'published', actor, p_client_request_id, now()
  ) returning * into saved;

  -- The host college is always included in a selected-college audience.
  if p_audience = 'selected_colleges' then
    insert into public.open_meetup_colleges (meetup_id, college_id)
    select saved.id, requested.college_id
    from unnest(array_append(coalesce(p_college_ids, '{}'::uuid[]), p_college_id)) as requested(college_id)
    on conflict do nothing;
  end if;

  insert into public.audit_records (actor_id, action, entity_type, entity_id)
  values (actor, 'open_meetup.host', 'open_meetup', saved.id);
  return jsonb_build_object('meetup_id', saved.id, 'status', saved.status, 'idempotent_replay', false);
exception
  when unique_violation then
    select * into saved from public.open_meetups where created_by = actor and client_request_id = p_client_request_id;
    if saved.id is null then raise; end if;
    return jsonb_build_object('meetup_id', saved.id, 'status', saved.status, 'idempotent_replay', true);
end $$;

revoke all on function public.host_open_meetup(uuid, uuid, uuid, text, text, timestamptz, timestamptz, integer, text, public.open_meetup_audience, uuid[], text, text) from public, anon;
grant execute on function public.host_open_meetup(uuid, uuid, uuid, text, text, timestamptz, timestamptz, integer, text, public.open_meetup_audience, uuid[], text, text) to authenticated;
comment on function public.host_open_meetup is 'Idempotent Open Meetup publication by the signed-in student for their own active college. Never grants recognised-host status.';

-- A deleted account also cancels the upcoming meetups it hosts, releasing every spot.
create or replace function private.release_open_meetup_spots()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  spot record;
begin
  for spot in
    select registration.meetup_id from public.open_meetup_registrations registration
    where registration.user_id = new.id and registration.status = 'going'
    order by registration.meetup_id
  loop
    perform 1 from public.open_meetups where id = spot.meetup_id for update;
    update public.open_meetup_registrations
    set status = 'cancelled', cancelled_at = now(), updated_at = now()
    where meetup_id = spot.meetup_id and user_id = new.id and status = 'going';
    update public.open_meetups meetup
    set going_count = (select count(*) from public.open_meetup_registrations r where r.meetup_id = meetup.id and r.status = 'going')
    where meetup.id = spot.meetup_id;
  end loop;

  for spot in
    select meetup.id from public.open_meetups meetup
    where meetup.host_id = new.id and meetup.status <> 'cancelled' and meetup.ends_at > now()
    order by meetup.id
    for update
  loop
    update public.open_meetup_registrations
    set status = 'cancelled', cancelled_at = now(), updated_at = now()
    where meetup_id = spot.id and status = 'going';
    update public.open_meetups
    set status = 'cancelled', cancelled_at = now(), going_count = 0, updated_at = now()
    where id = spot.id;
  end loop;
  return new;
end $$;
