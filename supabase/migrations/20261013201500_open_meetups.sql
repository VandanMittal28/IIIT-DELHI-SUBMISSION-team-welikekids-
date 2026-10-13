-- Open Meetups: casual, public social gatherings where students meet new people.
-- Deliberately separate from events so meetups do not inherit organizations,
-- passes, waitlists, attendance scanning, reminders, or event community channels.

create type public.open_meetup_status as enum ('draft', 'published', 'cancelled');
create type public.open_meetup_audience as enum ('selected_colleges', 'all_colleges');
create type public.open_meetup_registration_status as enum ('going', 'cancelled');

-- A recognised host is granted by a college administrator, never by creating a meetup.
-- display_name and headline are the only host details shown to students.
create table public.meetup_hosts (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  college_id uuid not null references public.colleges(id) on delete cascade,
  display_name text not null check (length(trim(display_name)) between 2 and 80),
  headline text check (headline is null or length(trim(headline)) between 2 and 120),
  verified_by uuid references public.profiles(id) on delete set null,
  verified_at timestamptz not null default now(),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.open_meetups (
  id uuid primary key default gen_random_uuid(),
  college_id uuid not null references public.colleges(id) on delete restrict,
  host_id uuid not null references public.meetup_hosts(user_id) on delete restrict,
  venue_id uuid not null references public.venues(id) on delete restrict,
  title text not null check (length(trim(title)) between 3 and 120),
  description text not null check (length(trim(description)) between 10 and 2000),
  location_note text check (location_note is null or length(trim(location_note)) between 2 and 160),
  icebreaker text not null check (length(trim(icebreaker)) between 10 and 280),
  audience public.open_meetup_audience not null default 'selected_colleges',
  capacity integer not null check (capacity between 2 and 500),
  going_count integer not null default 0 check (going_count >= 0 and going_count <= capacity),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status public.open_meetup_status not null default 'draft',
  created_by uuid not null references public.profiles(id) on delete restrict,
  client_request_id uuid not null,
  published_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (created_by, client_request_id),
  check (starts_at < ends_at),
  check ((status = 'published' and published_at is not null) or status <> 'published'),
  check ((status = 'cancelled' and cancelled_at is not null) or status <> 'cancelled')
);

-- Colleges whose students may join a 'selected_colleges' meetup.
create table public.open_meetup_colleges (
  meetup_id uuid not null references public.open_meetups(id) on delete cascade,
  college_id uuid not null references public.colleges(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (meetup_id, college_id)
);

create table public.open_meetup_registrations (
  id uuid primary key default gen_random_uuid(),
  meetup_id uuid not null references public.open_meetups(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status public.open_meetup_registration_status not null,
  joined_at timestamptz not null default now(),
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (meetup_id, user_id),
  check ((status = 'cancelled' and cancelled_at is not null) or status <> 'cancelled')
);

create index meetup_hosts_college_idx on public.meetup_hosts (college_id);
create index meetup_hosts_verified_by_idx on public.meetup_hosts (verified_by);
create index open_meetups_discovery_idx on public.open_meetups (status, starts_at);
create index open_meetups_college_idx on public.open_meetups (college_id);
create index open_meetups_host_idx on public.open_meetups (host_id);
create index open_meetups_venue_idx on public.open_meetups (venue_id);
create index open_meetups_created_by_idx on public.open_meetups (created_by);
create index open_meetup_colleges_college_idx on public.open_meetup_colleges (college_id);
create index open_meetup_registrations_meetup_status_idx on public.open_meetup_registrations (meetup_id, status);
create index open_meetup_registrations_user_idx on public.open_meetup_registrations (user_id);

-- Recognition lapses when the host account or their college membership is no longer active.
create function private.is_active_meetup_host(target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null and exists (
    select 1
    from public.meetup_hosts host
    join public.profiles profile on profile.id = host.user_id and profile.status = 'active'
    join public.college_memberships membership
      on membership.user_id = host.user_id and membership.college_id = host.college_id and membership.status = 'active'
    where host.user_id = target_user_id and host.revoked_at is null
  );
$$;

create function private.can_manage_open_meetup(target_meetup_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null and exists (
    select 1 from public.open_meetups meetup
    where meetup.id = target_meetup_id
      and (
        (meetup.host_id = target_user_id and private.is_active_meetup_host(target_user_id))
        or private.is_college_admin(meetup.college_id, target_user_id)
      )
  );
$$;

-- Eligibility uses administrator-granted college memberships, not the self-editable profile college.
create function private.is_eligible_for_open_meetup(target_meetup_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null
    and exists (select 1 from public.profiles profile where profile.id = target_user_id and profile.status = 'active')
    and exists (
      select 1 from public.open_meetups meetup
      where meetup.id = target_meetup_id
        and (
          (
            meetup.audience = 'all_colleges'
            and exists (
              select 1 from public.college_memberships membership
              where membership.user_id = target_user_id and membership.status = 'active'
            )
          )
          or exists (
            select 1
            from public.open_meetup_colleges allowed
            join public.college_memberships membership
              on membership.college_id = allowed.college_id and membership.user_id = target_user_id and membership.status = 'active'
            where allowed.meetup_id = meetup.id
          )
        )
    );
$$;

create function private.default_meetup_icebreaker(seed uuid)
returns text language sql immutable set search_path = '' as $$
  select (array[
    'What''s one thing about college you wish someone had told you earlier?',
    'What''s something new you''d like to try this semester?',
    'What''s a random thing you''re really passionate about?',
    'What''s been the best part of your week?',
    'If you could add one thing to campus, what would it be?',
    'What''s a small thing that always makes your day better?'
  ])[1 + ((hashtext(seed::text) % 6) + 6) % 6];
$$;

revoke all on function private.is_active_meetup_host(uuid) from public;
revoke all on function private.can_manage_open_meetup(uuid, uuid) from public;
revoke all on function private.is_eligible_for_open_meetup(uuid, uuid) from public;
revoke all on function private.default_meetup_icebreaker(uuid) from public;
grant execute on function private.is_active_meetup_host(uuid) to authenticated;
grant execute on function private.can_manage_open_meetup(uuid, uuid) to authenticated;
grant execute on function private.is_eligible_for_open_meetup(uuid, uuid) to authenticated;

alter table public.meetup_hosts enable row level security;
alter table public.open_meetups enable row level security;
alter table public.open_meetup_colleges enable row level security;
alter table public.open_meetup_registrations enable row level security;

-- Host cards are intentionally public to signed-in students; only safe columns are granted below.
create policy meetup_hosts_read on public.meetup_hosts for select to authenticated using (true);
create policy open_meetups_read on public.open_meetups for select to authenticated
  using (
    (status = 'published' and private.is_eligible_for_open_meetup(id))
    or private.can_manage_open_meetup(id)
    or exists (
      select 1 from public.open_meetup_registrations registration
      where registration.meetup_id = open_meetups.id and registration.user_id = (select auth.uid())
    )
  );
create policy open_meetup_colleges_read on public.open_meetup_colleges for select to authenticated
  using (exists (select 1 from public.open_meetups meetup where meetup.id = meetup_id));
create policy open_meetup_registrations_read on public.open_meetup_registrations for select to authenticated
  using ((select auth.uid()) = user_id or private.can_manage_open_meetup(meetup_id));

-- All writes go through the functions below; clients get read access only.
revoke all on public.meetup_hosts, public.open_meetups, public.open_meetup_colleges, public.open_meetup_registrations from anon, authenticated;
grant select (user_id, college_id, display_name, headline, verified_at, revoked_at) on public.meetup_hosts to authenticated;
grant select on public.open_meetups, public.open_meetup_colleges, public.open_meetup_registrations to authenticated;

create view public.open_meetup_feed
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
  host.display_name as host_name,
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
  private.is_eligible_for_open_meetup(meetup.id) as is_eligible
from public.open_meetups meetup
join public.colleges home on home.id = meetup.college_id
join public.meetup_hosts host on host.user_id = meetup.host_id
join public.venues venue on venue.id = meetup.venue_id
join public.campuses campus on campus.id = venue.campus_id;

grant select on public.open_meetup_feed to authenticated;
comment on view public.open_meetup_feed is 'RLS-scoped Open Meetups discovery projection with public host card, audience, and the caller''s own status.';

create function public.set_meetup_host(p_user_id uuid, p_college_id uuid, p_display_name text, p_headline text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null or not private.is_college_admin(p_college_id, actor) then
    raise sqlstate 'PGRST' using message = '{"code":"FORBIDDEN","message":"College administrator access is required."}', detail = '{"status":403}';
  end if;
  if not exists (
    select 1 from public.college_memberships membership
    join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
    where membership.user_id = p_user_id and membership.college_id = p_college_id and membership.status = 'active'
  ) then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_HOST","message":"Hosts must be active members of this college."}', detail = '{"status":422}';
  end if;
  insert into public.meetup_hosts (user_id, college_id, display_name, headline, verified_by, verified_at, revoked_at)
  values (p_user_id, p_college_id, trim(p_display_name), nullif(trim(p_headline), ''), actor, now(), null)
  on conflict (user_id) do update
    set college_id = excluded.college_id, display_name = excluded.display_name, headline = excluded.headline,
        verified_by = actor, verified_at = now(), revoked_at = null, updated_at = now();
  insert into public.audit_records (actor_id, action, entity_type, entity_id, detail)
  values (actor, 'meetup_host.verify', 'profile', p_user_id, jsonb_build_object('college_id', p_college_id));
  return jsonb_build_object('user_id', p_user_id, 'verified', true);
end $$;

create function public.revoke_meetup_host(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  target public.meetup_hosts;
begin
  select * into target from public.meetup_hosts where user_id = p_user_id for update;
  if actor is null or target.user_id is null or not private.is_college_admin(target.college_id, actor) then
    raise sqlstate 'PGRST' using message = '{"code":"FORBIDDEN","message":"College administrator access is required."}', detail = '{"status":403}';
  end if;
  if target.revoked_at is null then
    update public.meetup_hosts set revoked_at = now(), updated_at = now() where user_id = p_user_id;
    insert into public.audit_records (actor_id, action, entity_type, entity_id)
    values (actor, 'meetup_host.revoke', 'profile', p_user_id);
  end if;
  return jsonb_build_object('user_id', p_user_id, 'verified', false);
end $$;

create function public.create_open_meetup(
  p_client_request_id uuid,
  p_host_id uuid,
  p_venue_id uuid,
  p_title text,
  p_description text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_capacity integer,
  p_audience public.open_meetup_audience default 'selected_colleges',
  p_college_ids uuid[] default '{}',
  p_icebreaker text default null,
  p_location_note text default null,
  p_publish boolean default true
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  target_host public.meetup_hosts;
  venue_college uuid;
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

  select * into target_host from public.meetup_hosts where user_id = p_host_id;
  if target_host.user_id is null or not private.is_active_meetup_host(p_host_id) then
    raise sqlstate 'PGRST' using message = '{"code":"HOST_NOT_RECOGNISED","message":"Meetups must be hosted by a recognised host."}', detail = '{"status":422}';
  end if;

  if not (actor = p_host_id or private.is_college_admin(target_host.college_id, actor)) then
    raise sqlstate 'PGRST' using message = '{"code":"FORBIDDEN","message":"Only the recognised host or a college administrator can create this meetup."}', detail = '{"status":403}';
  end if;

  select campus.college_id into venue_college
  from public.venues venue join public.campuses campus on campus.id = venue.campus_id
  where venue.id = p_venue_id;
  if venue_college is distinct from target_host.college_id then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_VENUE","message":"Choose a venue on the host college campus."}', detail = '{"status":422}';
  end if;

  if p_starts_at <= now() or p_ends_at <= p_starts_at or p_capacity is null or p_capacity not between 2 and 500 then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_MEETUP_SCHEDULE","message":"Check the meetup time and capacity (2–500)."}', detail = '{"status":422}';
  end if;

  if p_audience = 'selected_colleges' and exists (
    select 1 from unnest(coalesce(p_college_ids, '{}'::uuid[])) as requested(college_id)
    where not exists (select 1 from public.colleges college where college.id = requested.college_id)
  ) then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_COLLEGE","message":"Choose available colleges."}', detail = '{"status":422}';
  end if;

  insert into public.open_meetups (
    id, college_id, host_id, venue_id, title, description, location_note, icebreaker,
    audience, capacity, starts_at, ends_at, status, created_by, client_request_id, published_at
  ) values (
    new_id, target_host.college_id, p_host_id, p_venue_id, trim(p_title), trim(p_description), nullif(trim(p_location_note), ''),
    coalesce(nullif(trim(p_icebreaker), ''), private.default_meetup_icebreaker(new_id)),
    p_audience, p_capacity, p_starts_at, p_ends_at,
    case when p_publish then 'published'::public.open_meetup_status else 'draft'::public.open_meetup_status end,
    actor, p_client_request_id, case when p_publish then now() end
  ) returning * into saved;

  -- The host college is always included in a selected-college audience.
  if p_audience = 'selected_colleges' then
    insert into public.open_meetup_colleges (meetup_id, college_id)
    select saved.id, requested.college_id
    from unnest(array_append(coalesce(p_college_ids, '{}'::uuid[]), target_host.college_id)) as requested(college_id)
    on conflict do nothing;
  end if;

  insert into public.audit_records (actor_id, action, entity_type, entity_id)
  values (actor, 'open_meetup.create', 'open_meetup', saved.id);
  return jsonb_build_object('meetup_id', saved.id, 'status', saved.status, 'idempotent_replay', false);
exception
  when unique_violation then
    select * into saved from public.open_meetups where created_by = actor and client_request_id = p_client_request_id;
    if saved.id is null then raise; end if;
    return jsonb_build_object('meetup_id', saved.id, 'status', saved.status, 'idempotent_replay', true);
end $$;

create function public.set_open_meetup_status(p_meetup_id uuid, p_status public.open_meetup_status)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  target public.open_meetups;
  released integer := 0;
begin
  select * into target from public.open_meetups where id = p_meetup_id for update;
  if actor is null or target.id is null or not private.can_manage_open_meetup(p_meetup_id, actor) then
    raise sqlstate 'PGRST' using message = '{"code":"FORBIDDEN","message":"Only the recognised host or a college administrator can manage this meetup."}', detail = '{"status":403}';
  end if;
  if p_status = 'draft' then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_STATUS","message":"A meetup can only be published or cancelled."}', detail = '{"status":422}';
  end if;
  if target.status = p_status then
    return jsonb_build_object('meetup_id', p_meetup_id, 'status', p_status, 'idempotent_replay', true);
  end if;
  if target.status = 'cancelled' then
    raise sqlstate 'PGRST' using message = '{"code":"MEETUP_CANCELLED","message":"A cancelled meetup cannot be published."}', detail = '{"status":409}';
  end if;

  if p_status = 'published' then
    update public.open_meetups set status = 'published', published_at = coalesce(published_at, now()), updated_at = now() where id = p_meetup_id;
  else
    update public.open_meetup_registrations
    set status = 'cancelled', cancelled_at = now(), updated_at = now()
    where meetup_id = p_meetup_id and status = 'going';
    get diagnostics released = row_count;
    update public.open_meetups set status = 'cancelled', cancelled_at = now(), going_count = 0, updated_at = now() where id = p_meetup_id;
  end if;

  insert into public.audit_records (actor_id, action, entity_type, entity_id, detail)
  values (actor, 'open_meetup.' || p_status::text, 'open_meetup', p_meetup_id, jsonb_build_object('released_spots', released));
  return jsonb_build_object('meetup_id', p_meetup_id, 'status', p_status, 'idempotent_replay', false);
end $$;

-- The meetup row lock serializes every join/leave for one meetup, so the
-- capacity check and the counter update cannot race.
create function public.join_open_meetup(p_meetup_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  target public.open_meetups;
  existing public.open_meetup_registrations;
  saved public.open_meetup_registrations;
  current_going integer;
begin
  if actor is null then
    raise sqlstate 'PGRST' using message = '{"code":"AUTH_REQUIRED","message":"Sign in is required."}', detail = '{"status":401}';
  end if;
  if not exists (select 1 from public.profiles profile where profile.id = actor and profile.status = 'active') then
    raise sqlstate 'PGRST' using message = '{"code":"ACCOUNT_UNAVAILABLE","message":"This account cannot join meetups."}', detail = '{"status":403}';
  end if;

  select * into target from public.open_meetups where id = p_meetup_id for update;
  if target.id is null or target.status <> 'published' then
    raise sqlstate 'PGRST' using message = '{"code":"MEETUP_UNAVAILABLE","message":"This meetup is not open right now."}', detail = '{"status":404}';
  end if;
  if now() >= target.ends_at then
    raise sqlstate 'PGRST' using message = '{"code":"MEETUP_ENDED","message":"This meetup has already ended."}', detail = '{"status":409}';
  end if;
  if not private.is_eligible_for_open_meetup(p_meetup_id, actor) then
    raise sqlstate 'PGRST' using message = '{"code":"NOT_ELIGIBLE","message":"This meetup is not open to students from your college."}', detail = '{"status":403}';
  end if;

  select * into existing from public.open_meetup_registrations where meetup_id = p_meetup_id and user_id = actor;
  if existing.id is not null and existing.status = 'going' then
    return jsonb_build_object('registration_id', existing.id, 'status', 'going', 'going_count', target.going_count, 'capacity', target.capacity, 'idempotent_replay', true);
  end if;

  select count(*)::integer into current_going from public.open_meetup_registrations where meetup_id = p_meetup_id and status = 'going';
  if current_going >= target.capacity then
    raise sqlstate 'PGRST' using message = '{"code":"MEETUP_FULL","message":"This meetup is full. Check back later in case someone cancels."}', detail = '{"status":409}';
  end if;

  insert into public.open_meetup_registrations (meetup_id, user_id, status, joined_at)
  values (p_meetup_id, actor, 'going', now())
  on conflict (meetup_id, user_id) do update
    set status = 'going', joined_at = now(), cancelled_at = null, updated_at = now()
  returning * into saved;

  update public.open_meetups set going_count = current_going + 1 where id = p_meetup_id;
  return jsonb_build_object('registration_id', saved.id, 'status', 'going', 'going_count', current_going + 1, 'capacity', target.capacity, 'idempotent_replay', false);
end $$;

create function public.leave_open_meetup(p_meetup_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  target public.open_meetups;
  existing public.open_meetup_registrations;
  current_going integer;
begin
  if actor is null then
    raise sqlstate 'PGRST' using message = '{"code":"AUTH_REQUIRED","message":"Sign in is required."}', detail = '{"status":401}';
  end if;

  select * into target from public.open_meetups where id = p_meetup_id for update;
  select * into existing from public.open_meetup_registrations where meetup_id = p_meetup_id and user_id = actor;
  if target.id is null or existing.id is null then
    raise sqlstate 'PGRST' using message = '{"code":"REGISTRATION_NOT_FOUND","message":"You have not joined this meetup."}', detail = '{"status":404}';
  end if;
  if existing.status = 'cancelled' then
    return jsonb_build_object('registration_id', existing.id, 'status', 'cancelled', 'going_count', target.going_count, 'capacity', target.capacity, 'idempotent_replay', true);
  end if;
  if now() >= target.ends_at then
    raise sqlstate 'PGRST' using message = '{"code":"MEETUP_ENDED","message":"This meetup has already ended."}', detail = '{"status":409}';
  end if;

  update public.open_meetup_registrations
  set status = 'cancelled', cancelled_at = now(), updated_at = now()
  where id = existing.id;
  select count(*)::integer into current_going from public.open_meetup_registrations where meetup_id = p_meetup_id and status = 'going';
  update public.open_meetups set going_count = current_going where id = p_meetup_id;
  return jsonb_build_object('registration_id', existing.id, 'status', 'cancelled', 'going_count', current_going, 'capacity', target.capacity, 'idempotent_replay', false);
end $$;

-- A deleted account releases its meetup spots so counts stay truthful.
create function private.release_open_meetup_spots()
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
  return new;
end $$;

revoke all on function private.release_open_meetup_spots() from public, anon, authenticated;
create trigger release_open_meetup_spots
after update of status on public.profiles
for each row when (new.status = 'deleted' and old.status is distinct from new.status)
execute function private.release_open_meetup_spots();

revoke all on function public.set_meetup_host(uuid, uuid, text, text) from public, anon;
revoke all on function public.revoke_meetup_host(uuid) from public, anon;
revoke all on function public.create_open_meetup(uuid, uuid, uuid, text, text, timestamptz, timestamptz, integer, public.open_meetup_audience, uuid[], text, text, boolean) from public, anon;
revoke all on function public.set_open_meetup_status(uuid, public.open_meetup_status) from public, anon;
revoke all on function public.join_open_meetup(uuid) from public, anon;
revoke all on function public.leave_open_meetup(uuid) from public, anon;
grant execute on function public.set_meetup_host(uuid, uuid, text, text) to authenticated;
grant execute on function public.revoke_meetup_host(uuid) to authenticated;
grant execute on function public.create_open_meetup(uuid, uuid, uuid, text, text, timestamptz, timestamptz, integer, public.open_meetup_audience, uuid[], text, text, boolean) to authenticated;
grant execute on function public.set_open_meetup_status(uuid, public.open_meetup_status) to authenticated;
grant execute on function public.join_open_meetup(uuid) to authenticated;
grant execute on function public.leave_open_meetup(uuid) to authenticated;

comment on function public.set_meetup_host is 'College administrators recognise an active member of their college as a meetup host.';
comment on function public.create_open_meetup is 'Idempotent Open Meetup creation by a recognised host or their college administrator.';
comment on function public.join_open_meetup is 'Atomic, capacity-safe and idempotent "I''m Going" registration for the signed-in student.';
comment on function public.leave_open_meetup is 'Idempotent cancellation of the signed-in student''s meetup spot.';
