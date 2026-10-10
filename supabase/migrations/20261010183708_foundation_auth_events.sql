-- Sidequest foundation: identity, contextual authorization, event authoring, and discovery.
-- Operational data is intentionally absent. Bootstrap data is created explicitly by an administrator.

create extension if not exists pgcrypto with schema extensions;

create type public.account_status as enum ('active', 'suspended', 'deleted');
create type public.membership_role as enum ('member', 'event_volunteer', 'organizer');
create type public.membership_status as enum ('invited', 'active', 'revoked');
create type public.event_status as enum ('draft', 'pending_approval', 'published', 'cancelled');
create type public.event_visibility as enum ('public', 'college_only', 'organization_only');

create table public.colleges (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  name text not null check (length(trim(name)) between 2 and 160),
  timezone text not null default 'Asia/Kolkata',
  event_approval_required boolean not null default false,
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  college_id uuid references public.colleges(id) on delete set null,
  full_name text check (full_name is null or length(trim(full_name)) between 1 and 120),
  avatar_path text,
  status public.account_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.college_memberships (
  id uuid primary key default gen_random_uuid(),
  college_id uuid not null references public.colleges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  is_admin boolean not null default false,
  status public.membership_status not null default 'invited',
  invited_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (college_id, user_id)
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  college_id uuid not null references public.colleges(id) on delete cascade,
  slug text not null,
  name text not null check (length(trim(name)) between 2 and 160),
  description text,
  logo_path text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (college_id, slug)
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.membership_role not null,
  status public.membership_status not null default 'invited',
  invited_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, user_id, role)
);

create table public.campuses (
  id uuid primary key default gen_random_uuid(),
  college_id uuid not null references public.colleges(id) on delete cascade,
  name text not null,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  created_at timestamptz not null default now(),
  unique (college_id, name)
);

create table public.venues (
  id uuid primary key default gen_random_uuid(),
  campus_id uuid not null references public.campuses(id) on delete cascade,
  name text not null,
  kind text not null default 'outdoor' check (kind in ('outdoor', 'building', 'floor', 'hall')),
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  accessibility_notes text,
  created_at timestamptz not null default now(),
  unique (campus_id, name)
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  college_id uuid not null references public.colleges(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  title text not null check (length(trim(title)) between 3 and 160),
  description text not null check (length(trim(description)) between 10 and 10000),
  category text not null check (length(trim(category)) between 2 and 64),
  visibility public.event_visibility not null default 'public',
  price_minor integer not null default 0 check (price_minor >= 0),
  currency text not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  eligibility text,
  status public.event_status not null default 'draft',
  cover_image_path text,
  created_by uuid not null references public.profiles(id) on delete restrict,
  client_request_id uuid not null,
  published_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (created_by, client_request_id),
  check ((status = 'published' and published_at is not null) or status <> 'published'),
  check ((status = 'cancelled' and cancelled_at is not null) or status <> 'cancelled')
);

create table public.event_editions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  label text not null default 'Main edition',
  registration_opens_at timestamptz not null,
  registration_closes_at timestamptz not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  capacity integer not null check (capacity > 0),
  waitlist_enabled boolean not null default true,
  reentry_allowed boolean not null default false,
  created_at timestamptz not null default now(),
  unique (event_id, label),
  check (registration_opens_at < registration_closes_at),
  check (registration_closes_at <= ends_at),
  check (starts_at < ends_at)
);

create table public.event_sessions (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references public.event_editions(id) on delete cascade,
  venue_id uuid references public.venues(id) on delete restrict,
  title text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  check (starts_at < ends_at)
);

create table public.event_staff_assignments (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references public.event_editions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.membership_role not null check (role in ('event_volunteer', 'organizer')),
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (edition_id, user_id, role)
);

create index memberships_user_active_idx on public.memberships (user_id, organization_id, role) where status = 'active';
create index college_memberships_user_active_idx on public.college_memberships (user_id, college_id) where status = 'active';
create index events_discovery_idx on public.events (status, college_id, category, published_at desc);
create index editions_dates_idx on public.event_editions (starts_at, ends_at);
create index sessions_edition_start_idx on public.event_sessions (edition_id, starts_at);

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create function private.is_college_admin(target_college_id uuid, target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_user_id is not null and exists (
    select 1 from public.college_memberships cm
    where cm.college_id = target_college_id
      and cm.user_id = target_user_id
      and cm.is_admin
      and cm.status = 'active'
  );
$$;

create function private.has_organization_role(
  target_organization_id uuid,
  allowed_roles public.membership_role[],
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_user_id is not null and (
    exists (
      select 1 from public.memberships m
      where m.organization_id = target_organization_id
        and m.user_id = target_user_id
        and m.role = any(allowed_roles)
        and m.status = 'active'
    )
    or exists (
      select 1 from public.organizations o
      where o.id = target_organization_id
        and private.is_college_admin(o.college_id, target_user_id)
    )
  );
$$;

revoke all on function private.is_college_admin(uuid, uuid) from public;
revoke all on function private.has_organization_role(uuid, public.membership_role[], uuid) from public;
grant execute on function private.is_college_admin(uuid, uuid) to authenticated;
grant execute on function private.has_organization_role(uuid, public.membership_role[], uuid) to authenticated;

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''));
  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create function public.create_event(
  p_client_request_id uuid,
  p_organization_id uuid,
  p_title text,
  p_description text,
  p_category text,
  p_visibility public.event_visibility,
  p_price_minor integer,
  p_currency text,
  p_eligibility text,
  p_registration_opens_at timestamptz,
  p_registration_closes_at timestamptz,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_capacity integer,
  p_waitlist_enabled boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target_college_id uuid;
  created_event public.events;
  created_edition public.event_editions;
  was_replay boolean := true;
begin
  if actor_id is null then
    raise sqlstate 'PGRST' using message = '{"code":"AUTH_REQUIRED","message":"Sign in is required."}', detail = '{"status":401}';
  end if;

  select o.college_id into target_college_id
  from public.organizations o
  where o.id = p_organization_id and o.is_active;

  if target_college_id is null then
    raise sqlstate 'PGRST' using message = '{"code":"ORGANIZATION_NOT_FOUND","message":"The organization is unavailable."}', detail = '{"status":404}';
  end if;

  if not private.has_organization_role(p_organization_id, array['organizer']::public.membership_role[], actor_id) then
    raise sqlstate 'PGRST' using message = '{"code":"FORBIDDEN","message":"Organizer access is required."}', detail = '{"status":403}';
  end if;

  if p_registration_opens_at >= p_registration_closes_at
    or p_registration_closes_at > p_ends_at
    or p_starts_at >= p_ends_at
    or p_capacity <= 0 then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_EVENT_SCHEDULE","message":"Check registration dates, event dates, and capacity."}', detail = '{"status":422}';
  end if;

  select * into created_event
  from public.events
  where created_by = actor_id and client_request_id = p_client_request_id;

  if created_event.id is null then
    was_replay := false;
    insert into public.events (
      college_id, organization_id, title, description, category, visibility,
      price_minor, currency, eligibility, created_by, client_request_id
    ) values (
      target_college_id, p_organization_id, trim(p_title), trim(p_description), trim(p_category), p_visibility,
      p_price_minor, upper(p_currency), nullif(trim(p_eligibility), ''), actor_id, p_client_request_id
    ) returning * into created_event;

    insert into public.event_editions (
      event_id, registration_opens_at, registration_closes_at, starts_at, ends_at,
      capacity, waitlist_enabled
    ) values (
      created_event.id, p_registration_opens_at, p_registration_closes_at, p_starts_at, p_ends_at,
      p_capacity, p_waitlist_enabled
    ) returning * into created_edition;
  else
    select * into created_edition from public.event_editions where event_id = created_event.id order by created_at limit 1;
  end if;

  return jsonb_build_object(
    'event_id', created_event.id,
    'edition_id', created_edition.id,
    'status', created_event.status,
    'idempotent_replay', was_replay
  );
exception
  when unique_violation then
    select * into created_event from public.events where created_by = actor_id and client_request_id = p_client_request_id;
    select * into created_edition from public.event_editions where event_id = created_event.id order by created_at limit 1;
    return jsonb_build_object('event_id', created_event.id, 'edition_id', created_edition.id, 'status', created_event.status, 'idempotent_replay', true);
end;
$$;

revoke all on function public.create_event(uuid, uuid, text, text, text, public.event_visibility, integer, text, text, timestamptz, timestamptz, timestamptz, timestamptz, integer, boolean) from public, anon;
grant execute on function public.create_event(uuid, uuid, text, text, text, public.event_visibility, integer, text, text, timestamptz, timestamptz, timestamptz, timestamptz, integer, boolean) to authenticated;

alter table public.colleges enable row level security;
alter table public.profiles enable row level security;
alter table public.college_memberships enable row level security;
alter table public.organizations enable row level security;
alter table public.memberships enable row level security;
alter table public.campuses enable row level security;
alter table public.venues enable row level security;
alter table public.events enable row level security;
alter table public.event_editions enable row level security;
alter table public.event_sessions enable row level security;
alter table public.event_staff_assignments enable row level security;

create policy colleges_read on public.colleges for select to anon, authenticated using (true);
create policy profiles_read_self on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy profiles_update_self on public.profiles for update to authenticated
  using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy college_memberships_read_scoped on public.college_memberships for select to authenticated
  using ((select auth.uid()) = user_id or private.is_college_admin(college_id));
create policy organizations_read on public.organizations for select to anon, authenticated using (is_active);
create policy memberships_read_scoped on public.memberships for select to authenticated
  using ((select auth.uid()) = user_id or private.has_organization_role(organization_id, array['organizer']::public.membership_role[]));
create policy campuses_read on public.campuses for select to anon, authenticated using (true);
create policy venues_read on public.venues for select to anon, authenticated using (true);
create policy published_events_read on public.events for select to anon, authenticated
  using (status = 'published');
create policy staff_events_read on public.events for select to authenticated
  using (private.has_organization_role(organization_id, array['organizer', 'event_volunteer']::public.membership_role[]));
create policy editions_read on public.event_editions for select to anon, authenticated
  using (exists (select 1 from public.events e where e.id = event_id));
create policy sessions_read on public.event_sessions for select to anon, authenticated
  using (exists (select 1 from public.event_editions ee join public.events e on e.id = ee.event_id where ee.id = edition_id));
create policy staff_read_scoped on public.event_staff_assignments for select to authenticated
  using ((select auth.uid()) = user_id or exists (
    select 1 from public.event_editions ee join public.events e on e.id = ee.event_id
    where ee.id = edition_id and private.has_organization_role(e.organization_id, array['organizer']::public.membership_role[])
  ));

grant usage on schema public to anon, authenticated;
grant select on public.colleges, public.organizations, public.campuses, public.venues, public.events, public.event_editions, public.event_sessions to anon, authenticated;
grant select, update (college_id, full_name, avatar_path, updated_at) on public.profiles to authenticated;
grant select on public.college_memberships, public.memberships, public.event_staff_assignments to authenticated;

create view public.published_event_feed
with (security_invoker = true)
as
select
  e.id,
  e.title,
  e.description,
  e.category,
  e.visibility,
  e.price_minor,
  e.currency,
  e.eligibility,
  e.cover_image_path,
  e.published_at,
  e.college_id,
  c.name as college_name,
  e.organization_id,
  o.name as organization_name,
  ee.id as edition_id,
  ee.registration_opens_at,
  ee.registration_closes_at,
  ee.starts_at,
  ee.ends_at,
  ee.capacity,
  ee.waitlist_enabled
from public.events e
join public.colleges c on c.id = e.college_id
join public.organizations o on o.id = e.organization_id
join lateral (
  select edition.* from public.event_editions edition
  where edition.event_id = e.id
  order by edition.starts_at asc limit 1
) ee on true
where e.status = 'published';

grant select on public.published_event_feed to anon, authenticated;

comment on function public.create_event is 'Atomic, idempotent event and initial-edition creation for authorized organizers.';
comment on view public.published_event_feed is 'Authoritative published discovery projection shared by web and iOS clients.';

create function public.publish_event(p_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target_event record;
  next_status public.event_status;
begin
  if actor_id is null then
    raise sqlstate 'PGRST' using message = '{"code":"AUTH_REQUIRED","message":"Sign in is required."}', detail = '{"status":401}';
  end if;

  select e.*, c.event_approval_required
    into target_event
  from public.events e
  join public.colleges c on c.id = e.college_id
  where e.id = p_event_id
  for update of e;

  if target_event.id is null then
    raise sqlstate 'PGRST' using message = '{"code":"EVENT_NOT_FOUND","message":"The event is unavailable."}', detail = '{"status":404}';
  end if;

  if not private.has_organization_role(target_event.organization_id, array['organizer']::public.membership_role[], actor_id) then
    raise sqlstate 'PGRST' using message = '{"code":"FORBIDDEN","message":"Organizer access is required."}', detail = '{"status":403}';
  end if;

  if target_event.status = 'cancelled' then
    raise sqlstate 'PGRST' using message = '{"code":"EVENT_CANCELLED","message":"A cancelled event cannot be published."}', detail = '{"status":409}';
  end if;

  if target_event.event_approval_required and not private.is_college_admin(target_event.college_id, actor_id) then
    next_status := 'pending_approval';
  else
    next_status := 'published';
  end if;

  update public.events
  set status = next_status,
      published_at = case when next_status = 'published' then coalesce(published_at, now()) else null end,
      updated_at = now()
  where id = p_event_id;

  return jsonb_build_object('event_id', p_event_id, 'status', next_status);
end;
$$;

revoke all on function public.publish_event(uuid) from public, anon;
grant execute on function public.publish_event(uuid) to authenticated;
comment on function public.publish_event is 'Publishes an event or submits it for approval according to stored college configuration.';
