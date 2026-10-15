create or replace function public.register_for_event(
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
  target_event_id uuid;
  existing public.registrations;
  saved public.registrations;
  saved_pass public.passes;
  registered_count integer;
  queue_position integer;
  next_status public.registration_status;
begin
  if actor_id is null then
    raise sqlstate 'PT401' using message = 'Sign in is required.';
  end if;

  if not exists (select 1 from public.profiles p where p.id = actor_id and p.status = 'active') then
    raise sqlstate 'PT403' using message = 'This account cannot register.';
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

  -- Cancellation locks event then editions. Use the same order so registration
  -- cannot pass a stale published-status read while cancellation is in flight.
  select ee.event_id into target_event_id
  from public.event_editions ee
  where ee.id = p_edition_id;

  if target_event_id is null then
    raise sqlstate 'PT404' using message = 'This event is not open for registration.';
  end if;

  perform 1 from public.events e where e.id = target_event_id for update;

  select ee.*, e.status as event_status
  into target
  from public.event_editions ee
  join public.events e on e.id = ee.event_id
  where ee.id = p_edition_id
  for update of ee;

  if target.id is null or target.event_status <> 'published' then
    raise sqlstate 'PT404' using message = 'This event is not open for registration.';
  end if;

  if now() < target.registration_opens_at then
    raise sqlstate 'PT409' using message = 'Registration has not opened yet.';
  end if;

  if now() >= target.registration_closes_at or now() >= target.ends_at then
    raise sqlstate 'PT409' using message = 'Registration is closed.';
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
    raise sqlstate 'PT409' using message = 'This event is full and has no waitlist.';
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
comment on function public.register_for_event is 'Atomic, capacity-safe, event-lock-serialized and idempotent registration or waitlist allocation with HTTP-mapped errors.';
