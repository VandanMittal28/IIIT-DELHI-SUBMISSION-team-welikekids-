-- Chat profile pictures and @mentions on the existing chat rooms.
-- Profile pictures reuse profiles.avatar_path, stored privately and readable only by students who share a room.
-- Mentions are stored by student id beside the unchanged message body, so old messages and clients keep working.

-- Profile pictures -------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-avatars', 'profile-avatars', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Avatars live under "<owner id>/". NOT VALID: checked for new writes only, existing rows are untouched.
alter table public.profiles add constraint profiles_avatar_path_owner
  check (avatar_path is null or split_part(avatar_path, '/', 1) = id::text) not valid;
-- The picture is set through set_profile_avatar, which checks the upload exists.
revoke update (avatar_path) on public.profiles from authenticated;

create function private.shares_chat_room(first_user uuid, second_user uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.channels channel
    where private.can_access_channel(channel.id, first_user) and private.can_access_channel(channel.id, second_user)
  );
$$;
revoke all on function private.shares_chat_room(uuid, uuid) from public, anon, authenticated;

-- Readable by the owner, or when it is an active student's current picture and the viewer shares a room with them.
create function private.can_view_profile_avatar(object_name text, viewer uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select viewer is not null and (
    (storage.foldername(object_name))[1] = viewer::text
    or exists (
      select 1 from public.profiles owner
      where owner.avatar_path = object_name
        and owner.id::text = (storage.foldername(object_name))[1]
        and owner.status = 'active'
        and private.shares_chat_room(owner.id, viewer)
    )
  );
$$;
revoke all on function private.can_view_profile_avatar(text, uuid) from public, anon;
grant execute on function private.can_view_profile_avatar(text, uuid) to authenticated;

create policy profile_avatar_read on storage.objects for select to authenticated
  using (bucket_id = 'profile-avatars' and private.can_view_profile_avatar(name));
create policy profile_avatar_owner_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'profile-avatars' and (storage.foldername(name))[1] = (select auth.uid()::text) and owner_id = (select auth.uid()::text));
create policy profile_avatar_owner_delete on storage.objects for delete to authenticated
  using (bucket_id = 'profile-avatars' and (storage.foldername(name))[1] = (select auth.uid()::text) and owner_id = (select auth.uid()::text));

-- Sets (or clears, with null) the caller's picture; returns the previous path so the client can delete it.
create function public.set_profile_avatar(p_path text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); previous text;
begin
  if actor is null then
    raise sqlstate 'PGRST' using message = '{"code":"AUTH_REQUIRED","message":"Sign in is required."}', detail = '{"status":401}';
  end if;
  if p_path is not null and (
    p_path !~ ('^' || actor::text || '/[0-9a-f-]{36}\.jpg$')
    or not exists (select 1 from storage.objects o where o.bucket_id = 'profile-avatars' and o.name = p_path and o.owner_id = actor::text)
  ) then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_AVATAR","message":"Upload the photo before saving it to your profile."}', detail = '{"status":422}';
  end if;
  select avatar_path into previous from public.profiles where id = actor for update;
  update public.profiles set avatar_path = p_path, updated_at = now() where id = actor;
  return jsonb_build_object('avatar_path', p_path, 'previous_path', previous, 'persisted', true);
end $$;
revoke all on function public.set_profile_avatar(text) from public, anon;
grant execute on function public.set_profile_avatar(text) to authenticated;

-- A picture path is only handed out when it belongs to its owner's folder and the owner is active.
create function private.chat_avatar_path(target public.profiles)
returns text language sql stable security definer set search_path = '' as $$
  select case when target.status = 'active' and split_part(target.avatar_path, '/', 1) = target.id::text then target.avatar_path end;
$$;
revoke all on function private.chat_avatar_path(public.profiles) from public, anon, authenticated;

-- Mentions ----------------------------------------------------------------------

-- display_name is the name as written in the body at send time, so highlighting survives later renames.
create table public.message_mentions (
  message_id uuid not null references public.messages(id) on delete cascade,
  mentioned_user_id uuid not null references public.profiles(id) on delete cascade,
  display_name text not null check (length(display_name) between 1 and 120),
  body_position integer not null,
  created_at timestamptz not null default now(),
  primary key (message_id, mentioned_user_id)
);
create index message_mentions_user_idx on public.message_mentions (mentioned_user_id);
alter table public.message_mentions enable row level security;
-- Read through get_channel_messages only, which checks room access.
revoke all on public.message_mentions from anon, authenticated;

-- Same contract as before plus p_mentions. Every mentioned id must be an active student who can access the room.
-- Mentions whose "@Name" is no longer in the body are dropped, so stored mentions always render.
drop function public.send_channel_message(uuid, text, uuid);
create function public.send_channel_message(
  p_channel_id uuid,
  p_body text,
  p_client_message_id uuid default null,
  p_mentions uuid[] default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  target public.channels;
  trimmed text := trim(coalesce(p_body, ''));
  requested uuid[] := array(select distinct m from unnest(coalesce(p_mentions, '{}'::uuid[])) m where m is not null and m <> actor);
  existing public.messages;
  saved public.messages;
  recent integer;
  author_name text;
  room_title text;
  mention record;
begin
  if actor is null then
    raise sqlstate 'PGRST' using message = '{"code":"AUTH_REQUIRED","message":"Sign in is required."}', detail = '{"status":401}';
  end if;

  if p_client_message_id is not null then
    select * into existing from public.messages where author_id = actor and client_message_id = p_client_message_id;
    if existing.id is not null then
      return jsonb_build_object('message_id', existing.id, 'seq', existing.seq, 'created_at', existing.created_at, 'persisted', true, 'idempotent_replay', true);
    end if;
  end if;

  select * into target from public.channels where id = p_channel_id;
  if target.id is null or target.is_locked or not private.can_access_channel(p_channel_id, actor) then
    raise sqlstate 'PGRST' using message = '{"code":"CHANNEL_UNAVAILABLE","message":"This chat room is unavailable to you."}', detail = '{"status":403}';
  end if;
  if length(trimmed) = 0 then
    raise sqlstate 'PGRST' using message = '{"code":"MESSAGE_EMPTY","message":"Write something before sending."}', detail = '{"status":422}';
  end if;
  if length(trimmed) > 2000 then
    raise sqlstate 'PGRST' using message = '{"code":"MESSAGE_TOO_LONG","message":"Messages can be up to 2000 characters."}', detail = '{"status":422}';
  end if;
  if cardinality(requested) > 10 then
    raise sqlstate 'PGRST' using message = '{"code":"TOO_MANY_MENTIONS","message":"You can mention up to 10 people in one message."}', detail = '{"status":422}';
  end if;
  if exists (
    select 1 from unnest(requested) candidate
    where not exists (select 1 from public.profiles p where p.id = candidate and p.status = 'active')
       or not private.can_access_channel(p_channel_id, candidate)
  ) then
    raise sqlstate 'PGRST' using message = '{"code":"MENTION_UNAVAILABLE","message":"Someone you mentioned can’t see this room."}', detail = '{"status":422}';
  end if;

  -- Serialize one student's sends so the rate limit cannot be raced.
  perform 1 from public.profiles where id = actor for update;
  select count(*)::integer into recent from public.messages
  where author_id = actor and created_at > now() - interval '30 seconds';
  if recent >= 8 then
    raise sqlstate 'PGRST' using message = '{"code":"RATE_LIMITED","message":"You’re sending messages too quickly. Wait a few seconds and try again."}', detail = '{"status":429}';
  end if;

  -- clock_timestamp keeps ordering exact even for several sends in one transaction.
  insert into public.messages (channel_id, author_id, body, client_message_id, created_at, updated_at)
  values (p_channel_id, actor, trimmed, p_client_message_id, clock_timestamp(), clock_timestamp())
  returning * into saved;

  if cardinality(requested) > 0 then
    insert into public.message_mentions (message_id, mentioned_user_id, display_name, body_position)
    select saved.id, p.id, named.display_name, strpos(trimmed, '@' || named.display_name)
    from public.profiles p
    cross join lateral (select coalesce(nullif(trim(p.full_name), ''), 'SideQuest student') display_name) named
    where p.id = any(requested) and strpos(trimmed, '@' || named.display_name) > 0;

    select coalesce(nullif(trim(full_name), ''), 'A student') into author_name from public.profiles where id = actor;
    select coalesce(target.title, event.title, 'a chat room') into room_title
    from (select 1) one
    left join public.event_editions edition on edition.id = target.edition_id
    left join public.events event on event.id = edition.event_id;
    for mention in select mentioned_user_id from public.message_mentions where message_id = saved.id loop
      perform private.enqueue_notification(
        mention.mentioned_user_id, target.edition_id, 'mention',
        author_name || ' mentioned you in ' || room_title,
        left(trimmed, 180),
        jsonb_build_object('channel_id', p_channel_id, 'message_id', saved.id)
      );
    end loop;
  end if;
  return jsonb_build_object('message_id', saved.id, 'seq', saved.seq, 'created_at', saved.created_at, 'persisted', true, 'idempotent_replay', false);
exception
  when unique_violation then
    select * into existing from public.messages where author_id = actor and client_message_id = p_client_message_id;
    if existing.id is null then raise; end if;
    return jsonb_build_object('message_id', existing.id, 'seq', existing.seq, 'created_at', existing.created_at, 'persisted', true, 'idempotent_replay', true);
end $$;
revoke all on function public.send_channel_message(uuid, text, uuid, uuid[]) from public, anon;
grant execute on function public.send_channel_message(uuid, text, uuid, uuid[]) to authenticated;

-- Legacy clients: unchanged contract, no mentions.
create or replace function public.post_message(p_channel_id uuid, p_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  result := public.send_channel_message(p_channel_id, p_body, null, null);
  return jsonb_build_object('message_id', result->>'message_id', 'persisted', true);
end $$;

-- Reading: same rows and cursors as before, plus the sender's picture path and the message's mentions.
drop function public.get_channel_messages(uuid, bigint, bigint, integer);
create function public.get_channel_messages(
  p_channel_id uuid,
  p_before_seq bigint default null,
  p_after_seq bigint default null,
  p_limit integer default 50
)
returns table (
  id uuid, seq bigint, channel_id uuid, author_id uuid, author_name text, author_college text,
  body text, created_at timestamptz, is_mine boolean, author_avatar_path text, mentions jsonb
)
language plpgsql stable security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  room public.channels;
  page_size integer := least(greatest(coalesce(p_limit, 50), 1), 100);
begin
  select * into room from public.channels c where c.id = p_channel_id;
  if actor is null or room.id is null or not private.can_access_channel(p_channel_id, actor) then
    raise sqlstate 'PGRST' using message = '{"code":"CHANNEL_UNAVAILABLE","message":"This chat room is unavailable to you."}', detail = '{"status":403}';
  end if;
  return query
  select m.id, m.seq, m.channel_id, m.author_id,
         coalesce(nullif(trim(p.full_name), ''), 'SideQuest student'),
         private.chat_author_college(m.author_id, room.college_id),
         m.body, m.created_at, m.author_id = actor,
         private.chat_avatar_path(p),
         coalesce((
           select jsonb_agg(jsonb_build_object('user_id', mm.mentioned_user_id, 'display_name', mm.display_name) order by mm.body_position)
           from public.message_mentions mm where mm.message_id = m.id
         ), '[]'::jsonb)
  from public.messages m
  left join public.profiles p on p.id = m.author_id
  where m.channel_id = p_channel_id and m.status = 'visible'
    and (p_before_seq is null or m.seq < p_before_seq)
    and (p_after_seq is null or m.seq > p_after_seq)
  order by case when p_after_seq is null then m.seq end desc,
           case when p_after_seq is not null then m.seq end asc
  limit page_size;
end $$;
revoke all on function public.get_channel_messages(uuid, bigint, bigint, integer) from public, anon;
grant execute on function public.get_channel_messages(uuid, bigint, bigint, integer) to authenticated;

-- Students the caller may mention in a room: only those who can access it, matched by name (login usernames are
-- sign-in credentials and are never searched or returned). An empty query lists recent senders only, so open
-- topic rooms never list every student.
create function public.search_chat_mention_candidates(p_channel_id uuid, p_query text default '', p_limit integer default 20)
returns table (user_id uuid, display_name text, college_name text, avatar_path text, recently_active boolean)
language plpgsql stable security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  room public.channels;
  needle text := lower(left(trim(coalesce(p_query, '')), 60));
  pattern text;
  page_size integer := least(greatest(coalesce(p_limit, 20), 1), 25);
begin
  select * into room from public.channels c where c.id = p_channel_id;
  if actor is null or room.id is null or not private.can_access_channel(p_channel_id, actor) then
    raise sqlstate 'PGRST' using message = '{"code":"CHANNEL_UNAVAILABLE","message":"This chat room is unavailable to you."}', detail = '{"status":403}';
  end if;
  pattern := '%' || replace(replace(replace(needle, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return query
  with recent_authors as (
    select m.author_id, max(m.seq) last_seq from public.messages m
    where m.channel_id = room.id and m.status = 'visible'
    group by m.author_id order by max(m.seq) desc limit 200
  ), pool as (
    select ra.author_id candidate from recent_authors ra
    union
    select membership.user_id from public.college_memberships membership
    where needle <> '' and membership.status = 'active'
      and (room.kind = 'topic' or (room.kind = 'college' and membership.college_id = room.college_id))
    union
    select registration.user_id from public.registrations registration
    where needle <> '' and room.kind = 'event' and registration.edition_id = room.edition_id and registration.status <> 'cancelled'
    union
    -- Event staff are not registrants; they come from the event's college and are filtered by room access below.
    select membership.user_id from public.college_memberships membership
    join public.events event on event.college_id = membership.college_id
    join public.event_editions edition on edition.event_id = event.id
    where needle <> '' and room.kind = 'event' and edition.id = room.edition_id and membership.status = 'active'
  )
  select p.id, trim(p.full_name), private.chat_author_college(p.id, room.college_id), private.chat_avatar_path(p),
         ra.author_id is not null
  from pool
  join public.profiles p on p.id = pool.candidate and p.status = 'active'
  left join recent_authors ra on ra.author_id = p.id
  where p.id <> actor
    and nullif(trim(p.full_name), '') is not null
    and (needle = '' or lower(p.full_name) like pattern)
    and private.can_access_channel(room.id, p.id)
  order by (needle <> '' and lower(trim(p.full_name)) like (needle || '%')) desc, ra.last_seq desc nulls last, lower(trim(p.full_name))
  limit page_size;
end $$;
revoke all on function public.search_chat_mention_candidates(uuid, text, integer) from public, anon;
grant execute on function public.search_chat_mention_candidates(uuid, text, integer) to authenticated;
