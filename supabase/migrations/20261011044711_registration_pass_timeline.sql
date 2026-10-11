create type public.registration_status as enum ('registered', 'waitlisted', 'cancelled');
create type public.waitlist_status as enum ('waiting', 'promoted', 'cancelled');
create type public.pass_status as enum ('active', 'revoked');

create table public.registrations (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references public.event_editions(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status public.registration_status not null,
  client_request_id uuid not null,
  registered_at timestamptz,
  waitlisted_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (edition_id, user_id),
  unique (user_id, client_request_id),
  check ((status = 'registered' and registered_at is not null) or status <> 'registered'),
  check ((status = 'waitlisted' and waitlisted_at is not null) or status <> 'waitlisted'),
  check ((status = 'cancelled' and cancelled_at is not null) or status <> 'cancelled')
);

create table public.waitlist_entries (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references public.event_editions(id) on delete cascade,
  registration_id uuid not null unique references public.registrations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status public.waitlist_status not null default 'waiting',
  joined_at timestamptz not null default now(),
  promoted_at timestamptz,
  cancelled_at timestamptz,
  unique (edition_id, user_id),
  check ((status = 'promoted' and promoted_at is not null) or status <> 'promoted'),
  check ((status = 'cancelled' and cancelled_at is not null) or status <> 'cancelled')
);

create table public.passes (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null unique references public.registrations(id) on delete cascade,
  token uuid not null unique default gen_random_uuid(),
  status public.pass_status not null default 'active',
  issued_at timestamptz not null default now(),
  revoked_at timestamptz,
  check ((status = 'revoked' and revoked_at is not null) or status <> 'revoked')
);

create index registrations_edition_status_idx
  on public.registrations (edition_id, status);
create index registrations_user_timeline_idx
  on public.registrations (user_id, created_at desc);
create index waitlist_entries_queue_idx
  on public.waitlist_entries (edition_id, status, joined_at, id);
create index waitlist_entries_user_idx
  on public.waitlist_entries (user_id);

create function private.can_manage_edition(
  target_edition_id uuid,
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_user_id is not null and exists (
    select 1
    from public.event_editions ee
    join public.events e on e.id = ee.event_id
    where ee.id = target_edition_id
      and (
        private.has_organization_role(
          e.organization_id,
          array['organizer']::public.membership_role[],
          target_user_id
        )
        or exists (
          select 1 from public.event_staff_assignments esa
          where esa.edition_id = target_edition_id
            and esa.user_id = target_user_id
        )
      )
  );
$$;

create function private.has_event_registration(
  target_event_id uuid,
  target_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_user_id is not null and exists (
    select 1
    from public.registrations r
    join public.event_editions ee on ee.id = r.edition_id
    where ee.event_id = target_event_id
      and r.user_id = target_user_id
  );
$$;

revoke all on function private.can_manage_edition(uuid, uuid) from public;
revoke all on function private.has_event_registration(uuid, uuid) from public;
grant execute on function private.can_manage_edition(uuid, uuid) to authenticated;
grant execute on function private.has_event_registration(uuid, uuid) to authenticated;

alter table public.registrations enable row level security;
alter table public.waitlist_entries enable row level security;
alter table public.passes enable row level security;

create policy registrations_read_scoped
  on public.registrations for select to authenticated
  using ((select auth.uid()) = user_id or private.can_manage_edition(edition_id));

create policy waitlist_entries_read_scoped
  on public.waitlist_entries for select to authenticated
  using ((select auth.uid()) = user_id or private.can_manage_edition(edition_id));

create policy passes_read_scoped
  on public.passes for select to authenticated
  using (
    exists (
      select 1 from public.registrations r
      where r.id = registration_id
        and ((select auth.uid()) = r.user_id or private.can_manage_edition(r.edition_id))
    )
  );

grant select on public.registrations, public.waitlist_entries, public.passes to authenticated;

drop policy published_events_read on public.events;
drop policy authenticated_events_read on public.events;

create policy published_events_read
  on public.events for select to anon
  using (status = 'published' and visibility = 'public');

create policy authenticated_events_read
  on public.events for select to authenticated
  using (
    (
      status = 'published'
      and (
        visibility = 'public'
        or (
          visibility = 'college_only'
          and exists (
            select 1 from public.profiles p
            where p.id = (select auth.uid()) and p.college_id = events.college_id
          )
        )
        or (
          visibility = 'organization_only'
          and exists (
            select 1 from public.memberships m
            where m.organization_id = events.organization_id
              and m.user_id = (select auth.uid())
              and m.status = 'active'
          )
        )
      )
    )
    or private.has_organization_role(
      organization_id,
      array['organizer', 'event_volunteer']::public.membership_role[]
    )
    or private.has_event_registration(id)
  );

create function public.register_for_event(
  p_edition_id uuid,
  p_client_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target record;
  existing public.registrations;
  saved public.registrations;
  saved_pass public.passes;
  registered_count integer;
  queue_position integer;
  next_status public.registration_status;
begin
  if actor_id is null then
    raise sqlstate 'PGRST' using message = '{"code":"AUTH_REQUIRED","message":"Sign in is required."}', detail = '{"status":401}';
  end if;

  if not exists (select 1 from public.profiles p where p.id = actor_id and p.status = 'active') then
    raise sqlstate 'PGRST' using message = '{"code":"ACCOUNT_UNAVAILABLE","message":"This account cannot register."}', detail = '{"status":403}';
  end if;

  select * into existing
  from public.registrations r
  where r.user_id = actor_id and r.client_request_id = p_client_request_id;

  if existing.id is not null then
    select * into saved_pass from public.passes p where p.registration_id = existing.id and p.status = 'active';
    select count(*)::integer into queue_position
    from public.waitlist_entries w
    join public.waitlist_entries mine on mine.registration_id = existing.id
    where w.edition_id = existing.edition_id and w.status = 'waiting'
      and (w.joined_at < mine.joined_at or (w.joined_at = mine.joined_at and w.id <= mine.id));
    return jsonb_build_object(
      'registration_id', existing.id,
      'status', existing.status,
      'pass_token', saved_pass.token,
      'waitlist_position', nullif(queue_position, 0),
      'idempotent_replay', true
    );
  end if;

  select ee.*, e.status as event_status
  into target
  from public.event_editions ee
  join public.events e on e.id = ee.event_id
  where ee.id = p_edition_id
  for update of ee;

  if target.id is null or target.event_status <> 'published' then
    raise sqlstate 'PGRST' using message = '{"code":"EVENT_UNAVAILABLE","message":"This event is not open for registration."}', detail = '{"status":404}';
  end if;

  if now() < target.registration_opens_at then
    raise sqlstate 'PGRST' using message = '{"code":"REGISTRATION_NOT_OPEN","message":"Registration has not opened yet."}', detail = '{"status":409}';
  end if;

  if now() >= target.registration_closes_at or now() >= target.ends_at then
    raise sqlstate 'PGRST' using message = '{"code":"REGISTRATION_CLOSED","message":"Registration is closed."}', detail = '{"status":409}';
  end if;

  select * into existing
  from public.registrations r
  where r.edition_id = p_edition_id and r.user_id = actor_id
  for update;

  if existing.id is not null and existing.status in ('registered', 'waitlisted') then
    select * into saved_pass from public.passes p where p.registration_id = existing.id and p.status = 'active';
    return jsonb_build_object(
      'registration_id', existing.id,
      'status', existing.status,
      'pass_token', saved_pass.token,
      'waitlist_position', null,
      'idempotent_replay', true
    );
  end if;

  select count(*)::integer into registered_count
  from public.registrations r
  where r.edition_id = p_edition_id and r.status = 'registered';

  if registered_count < target.capacity then
    next_status := 'registered';
  elsif target.waitlist_enabled then
    next_status := 'waitlisted';
  else
    raise sqlstate 'PGRST' using message = '{"code":"EVENT_FULL","message":"This event is full and has no waitlist."}', detail = '{"status":409}';
  end if;

  if existing.id is null then
    insert into public.registrations (
      edition_id, user_id, status, client_request_id, registered_at, waitlisted_at
    ) values (
      p_edition_id, actor_id, next_status, p_client_request_id,
      case when next_status = 'registered' then now() end,
      case when next_status = 'waitlisted' then now() end
    ) returning * into saved;
  else
    update public.registrations
    set status = next_status,
        client_request_id = p_client_request_id,
        registered_at = case when next_status = 'registered' then now() end,
        waitlisted_at = case when next_status = 'waitlisted' then now() end,
        cancelled_at = null,
        updated_at = now()
    where id = existing.id
    returning * into saved;
  end if;

  if next_status = 'registered' then
    update public.waitlist_entries
    set status = 'cancelled', cancelled_at = now()
    where registration_id = saved.id and status = 'waiting';

    insert into public.passes (registration_id, token, status, issued_at, revoked_at)
    values (saved.id, gen_random_uuid(), 'active', now(), null)
    on conflict (registration_id) do update
      set token = excluded.token, status = 'active', issued_at = now(), revoked_at = null
    returning * into saved_pass;
  else
    insert into public.waitlist_entries (edition_id, registration_id, user_id, status, joined_at)
    values (p_edition_id, saved.id, actor_id, 'waiting', now())
    on conflict (edition_id, user_id) do update
      set registration_id = excluded.registration_id,
          status = 'waiting', joined_at = now(), promoted_at = null, cancelled_at = null;

    select count(*)::integer into queue_position
    from public.waitlist_entries w
    join public.waitlist_entries mine on mine.registration_id = saved.id
    where w.edition_id = p_edition_id and w.status = 'waiting'
      and (w.joined_at < mine.joined_at or (w.joined_at = mine.joined_at and w.id <= mine.id));
  end if;

  return jsonb_build_object(
    'registration_id', saved.id,
    'status', saved.status,
    'pass_token', saved_pass.token,
    'waitlist_position', nullif(queue_position, 0),
    'idempotent_replay', false
  );
end;
$$;

revoke all on function public.register_for_event(uuid, uuid) from public, anon;
grant execute on function public.register_for_event(uuid, uuid) to authenticated;
comment on function public.register_for_event is 'Atomic, capacity-safe and idempotent registration or waitlist allocation.';

create function public.cancel_registration(p_registration_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  target public.registrations;
  promoted public.registrations;
begin
  if actor_id is null then
    raise sqlstate 'PGRST' using message = '{"code":"AUTH_REQUIRED","message":"Sign in is required."}', detail = '{"status":401}';
  end if;

  select r.* into target
  from public.registrations r
  join public.event_editions ee on ee.id = r.edition_id
  where r.id = p_registration_id
  for update of ee, r;

  if target.id is null then
    raise sqlstate 'PGRST' using message = '{"code":"REGISTRATION_NOT_FOUND","message":"The registration is unavailable."}', detail = '{"status":404}';
  end if;

  if target.user_id <> actor_id then
    raise sqlstate 'PGRST' using message = '{"code":"FORBIDDEN","message":"You can only cancel your own registration."}', detail = '{"status":403}';
  end if;

  if target.status = 'cancelled' then
    return jsonb_build_object('registration_id', target.id, 'status', 'cancelled', 'idempotent_replay', true);
  end if;

  update public.registrations
  set status = 'cancelled', cancelled_at = now(), updated_at = now()
  where id = target.id;

  update public.waitlist_entries
  set status = 'cancelled', cancelled_at = now()
  where registration_id = target.id and status = 'waiting';

  update public.passes
  set status = 'revoked', revoked_at = now()
  where registration_id = target.id and status = 'active';

  if target.status = 'registered' then
    select r.* into promoted
    from public.registrations r
    join public.waitlist_entries w on w.registration_id = r.id
    where r.edition_id = target.edition_id
      and r.status = 'waitlisted'
      and w.status = 'waiting'
    order by w.joined_at, w.id
    limit 1
    for update of r, w;

    if promoted.id is not null then
      update public.registrations
      set status = 'registered', registered_at = now(), waitlisted_at = null, updated_at = now()
      where id = promoted.id;

      update public.waitlist_entries
      set status = 'promoted', promoted_at = now()
      where registration_id = promoted.id;

      insert into public.passes (registration_id, token, status, issued_at, revoked_at)
      values (promoted.id, gen_random_uuid(), 'active', now(), null)
      on conflict (registration_id) do update
        set token = excluded.token, status = 'active', issued_at = now(), revoked_at = null;
    end if;
  end if;

  return jsonb_build_object(
    'registration_id', target.id,
    'status', 'cancelled',
    'promoted_registration_id', promoted.id,
    'idempotent_replay', false
  );
end;
$$;

revoke all on function public.cancel_registration(uuid) from public, anon;
grant execute on function public.cancel_registration(uuid) to authenticated;
comment on function public.cancel_registration is 'Idempotent cancellation with pass revocation and FIFO waitlist promotion.';

create view public.my_journey
with (security_invoker = true)
as
select
  r.id as registration_id,
  r.status,
  r.registered_at,
  r.waitlisted_at,
  r.cancelled_at,
  ee.id as edition_id,
  e.id as event_id,
  e.title,
  e.category,
  e.status as event_status,
  o.name as organization_name,
  ee.starts_at,
  ee.ends_at,
  p.token as pass_token,
  p.status as pass_status,
  (
    select count(*)::integer
    from public.waitlist_entries ahead
    where ahead.edition_id = r.edition_id
      and ahead.status = 'waiting'
      and (ahead.joined_at, ahead.id) <= (w.joined_at, w.id)
  ) as waitlist_position
from public.registrations r
join public.event_editions ee on ee.id = r.edition_id
join public.events e on e.id = ee.event_id
join public.organizations o on o.id = e.organization_id
left join public.passes p on p.registration_id = r.id and p.status = 'active'
left join public.waitlist_entries w on w.registration_id = r.id and w.status = 'waiting';

grant select on public.my_journey to authenticated;
comment on view public.my_journey is 'Authenticated registration, waitlist and pass timeline protected by underlying RLS.';

create view public.edition_registration_summary
with (security_invoker = true)
as
select
  ee.id as edition_id,
  ee.event_id,
  ee.capacity,
  count(r.id) filter (where r.status = 'registered')::integer as registered_count,
  count(r.id) filter (where r.status = 'waitlisted')::integer as waitlisted_count,
  count(r.id) filter (where r.status = 'cancelled')::integer as cancelled_count
from public.event_editions ee
left join public.registrations r on r.edition_id = ee.id
group by ee.id;

grant select on public.edition_registration_summary to authenticated;
comment on view public.edition_registration_summary is 'RLS-scoped authoritative registration and waitlist counts for event staff.';
