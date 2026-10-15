-- Student chatrooms built on the existing event channels/messages.
-- Adds college lounges and inter-college topic rooms, sender identity for room members,
-- idempotent validated sending, unread tracking, and moderation for the new room kinds.
-- Event-room access and moderation rules are unchanged.

-- Rooms ---------------------------------------------------------------------

alter table public.channels
  add column kind text not null default 'event' check (kind in ('event', 'college', 'topic')),
  add column college_id uuid references public.colleges(id) on delete cascade,
  add column slug text check (slug is null or slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  add column title text check (title is null or length(trim(title)) between 2 and 80),
  add column description text check (description is null or length(trim(description)) <= 280),
  add column sort_order integer not null default 100;
alter table public.channels alter column edition_id drop not null;
alter table public.channels add constraint channels_kind_shape check (
  (kind = 'event' and edition_id is not null and college_id is null)
  or (kind = 'college' and edition_id is null and college_id is not null)
  or (kind = 'topic' and edition_id is null and college_id is null and slug is not null and title is not null)
);
create unique index channels_college_lounge_idx on public.channels (college_id) where kind = 'college';
create unique index channels_topic_slug_idx on public.channels (slug) where kind = 'topic';

-- One lounge per college, kept in step with new colleges.
create function private.ensure_college_lounge()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.channels (kind, college_id, title, description, sort_order)
  values ('college', new.id, left(new.name, 70) || ' Lounge', 'Hang out with students from your college.', 1)
  on conflict do nothing;
  return new;
end $$;
revoke all on function private.ensure_college_lounge() from public, anon, authenticated;
create trigger ensure_college_lounge after insert on public.colleges
for each row execute function private.ensure_college_lounge();

insert into public.channels (kind, college_id, title, description, sort_order)
select 'college', college.id, left(college.name, 70) || ' Lounge', 'Hang out with students from your college.', 1
from public.colleges college
on conflict do nothing;

insert into public.channels (kind, slug, title, description, sort_order) values
  ('topic', 'commons', 'SideQuest Commons', 'Meet students from every college on SideQuest.', 10),
  ('topic', 'coding', 'Coding', 'Projects, hackathons, and help with code.', 20),
  ('topic', 'music', 'Music', 'Jams, gigs, playlists, and open mics.', 30),
  ('topic', 'gaming', 'Gaming', 'Find teammates and talk games.', 40),
  ('topic', 'plans-events', 'Plans & Events', 'What''s happening this week and who''s going.', 50)
on conflict do nothing;

-- Messages: client request IDs make retries safe; seq gives an exact, gap-free ordering cursor
-- (timestamps can tie). Existing rows are numbered when the column is added.
alter table public.messages add column client_message_id uuid;
alter table public.messages add column seq bigint generated always as identity;
create unique index messages_author_client_id_idx on public.messages (author_id, client_message_id) where client_message_id is not null;
create unique index messages_channel_seq_idx on public.messages (channel_id, seq desc);

-- Access ---------------------------------------------------------------------

-- Event rooms keep can_access_edition. College lounges need an active membership in that college;
-- topic rooms need an active membership in any college. Profile college is never trusted.
create function private.can_access_channel(target_channel_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null and exists (
    select 1 from public.channels channel
    where channel.id = target_channel_id
      and (
        (channel.kind = 'event' and private.can_access_edition(channel.edition_id, target_user_id))
        or (
          channel.kind in ('college', 'topic')
          and exists (select 1 from public.profiles profile where profile.id = target_user_id and profile.status = 'active')
          and exists (
            select 1 from public.college_memberships membership
            where membership.user_id = target_user_id and membership.status = 'active'
              and (channel.kind = 'topic' or membership.college_id = channel.college_id)
          )
        )
      )
  );
$$;

create function private.can_moderate_channel(target_channel_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null and exists (
    select 1 from public.channels channel
    where channel.id = target_channel_id
      and (
        (channel.kind = 'event' and private.can_manage_edition(channel.edition_id, target_user_id))
        or (channel.kind = 'college' and private.is_college_admin(channel.college_id, target_user_id))
        or (channel.kind = 'topic' and private.is_platform_admin(target_user_id))
      )
  );
$$;

revoke all on function private.can_access_channel(uuid, uuid) from public;
revoke all on function private.can_moderate_channel(uuid, uuid) from public;
grant execute on function private.can_access_channel(uuid, uuid) to authenticated;
grant execute on function private.can_moderate_channel(uuid, uuid) to authenticated;

-- Same semantics for event rooms; Realtime postgres_changes delivery is filtered by these policies.
drop policy channels_read on public.channels;
create policy channels_read on public.channels for select to authenticated
  using (private.can_access_channel(id));

drop policy messages_read on public.messages;
create policy messages_read on public.messages for select to authenticated
  using ((status = 'visible' and private.can_access_channel(channel_id)) or private.can_moderate_channel(channel_id));

-- Sending --------------------------------------------------------------------

create function public.send_channel_message(p_channel_id uuid, p_body text, p_client_message_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  target public.channels;
  trimmed text := trim(coalesce(p_body, ''));
  existing public.messages;
  saved public.messages;
  recent integer;
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
  return jsonb_build_object('message_id', saved.id, 'seq', saved.seq, 'created_at', saved.created_at, 'persisted', true, 'idempotent_replay', false);
exception
  when unique_violation then
    select * into existing from public.messages where author_id = actor and client_message_id = p_client_message_id;
    if existing.id is null then raise; end if;
    return jsonb_build_object('message_id', existing.id, 'seq', existing.seq, 'created_at', existing.created_at, 'persisted', true, 'idempotent_replay', true);
end $$;

-- Existing clients keep the same contract, now with the shared validation and access rules.
create or replace function public.post_message(p_channel_id uuid, p_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  result := public.send_channel_message(p_channel_id, p_body, null);
  return jsonb_build_object('message_id', result->>'message_id', 'persisted', true);
end $$;

revoke all on function public.send_channel_message(uuid, text, uuid) from public, anon;
grant execute on function public.send_channel_message(uuid, text, uuid) to authenticated;

-- Reading with sender identity ------------------------------------------------

-- Display name: profile full name (or "SideQuest student"); college comes from an active membership,
-- preferring the room's college. Only callers who can read the room get any rows.
create function private.chat_author_college(target_user_id uuid, preferred_college uuid)
returns text language sql stable security definer set search_path = '' as $$
  select college.name
  from public.college_memberships membership
  join public.colleges college on college.id = membership.college_id
  where membership.user_id = target_user_id and membership.status = 'active'
  order by (membership.college_id = preferred_college) desc nulls last, college.name
  limit 1;
$$;
revoke all on function private.chat_author_college(uuid, uuid) from public, anon, authenticated;

-- Newest-first page before a seq cursor, or oldest-first rows after one (gap fill / live refresh).
create function public.get_channel_messages(
  p_channel_id uuid,
  p_before_seq bigint default null,
  p_after_seq bigint default null,
  p_limit integer default 50
)
returns table (
  id uuid, seq bigint, channel_id uuid, author_id uuid, author_name text, author_college text,
  body text, created_at timestamptz, is_mine boolean
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
         m.body, m.created_at, m.author_id = actor
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

-- Unread tracking ---------------------------------------------------------------

create table public.channel_reads (
  user_id uuid not null references public.profiles(id) on delete cascade,
  channel_id uuid not null references public.channels(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (user_id, channel_id)
);
create index channel_reads_channel_idx on public.channel_reads (channel_id);
alter table public.channel_reads enable row level security;
create policy channel_reads_self on public.channel_reads for select to authenticated using ((select auth.uid()) = user_id);
revoke all on public.channel_reads from anon, authenticated;
grant select on public.channel_reads to authenticated;

create function public.mark_channel_read(p_channel_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null or not private.can_access_channel(p_channel_id, actor) then
    raise sqlstate 'PGRST' using message = '{"code":"CHANNEL_UNAVAILABLE","message":"This chat room is unavailable to you."}', detail = '{"status":403}';
  end if;
  insert into public.channel_reads (user_id, channel_id, last_read_at) values (actor, p_channel_id, clock_timestamp())
  on conflict (user_id, channel_id) do update set last_read_at = greatest(public.channel_reads.last_read_at, excluded.last_read_at);
  return jsonb_build_object('channel_id', p_channel_id, 'read', true);
end $$;
revoke all on function public.mark_channel_read(uuid) from public, anon;
grant execute on function public.mark_channel_read(uuid) to authenticated;

-- Every room the caller can read, with last-message preview and unread count (others' messages only).
create function public.get_my_chat_rooms()
returns table (
  id uuid, kind text, title text, description text, college_name text, starts_at timestamptz,
  last_message_body text, last_message_author text, last_message_at timestamptz, unread_count integer, sort_order integer
)
language plpgsql stable security definer set search_path = '' as $$
declare actor uuid := auth.uid();
begin
  if actor is null then
    raise sqlstate 'PGRST' using message = '{"code":"AUTH_REQUIRED","message":"Sign in is required."}', detail = '{"status":401}';
  end if;
  return query
  select c.id, c.kind,
         coalesce(c.title, event.title, 'Event room'),
         coalesce(c.description, case when c.kind = 'event' then 'Attendees of ' || event.title end),
         college.name,
         edition.starts_at,
         left(last_message.body, 140),
         coalesce(nullif(trim(last_author.full_name), ''), case when last_message.id is not null then 'SideQuest student' end),
         last_message.created_at,
         (select least(count(*), 99)::integer from public.messages unread
          where unread.channel_id = c.id and unread.status = 'visible' and unread.author_id <> actor
            and unread.created_at > coalesce(read_state.last_read_at, '-infinity'::timestamptz)),
         c.sort_order
  from public.channels c
  left join public.event_editions edition on edition.id = c.edition_id
  left join public.events event on event.id = edition.event_id
  left join public.colleges college on college.id = c.college_id
  left join public.channel_reads read_state on read_state.channel_id = c.id and read_state.user_id = actor
  left join lateral (
    select m.id, m.body, m.created_at, m.author_id from public.messages m
    where m.channel_id = c.id and m.status = 'visible'
    order by m.seq desc limit 1
  ) last_message on true
  left join public.profiles last_author on last_author.id = last_message.author_id
  where private.can_access_channel(c.id, actor)
    and (c.kind <> 'event' or event.status <> 'cancelled')
  order by c.sort_order, coalesce(last_message.created_at, c.created_at) desc;
end $$;
revoke all on function public.get_my_chat_rooms() from public, anon;
grant execute on function public.get_my_chat_rooms() to authenticated;

-- Moderation and reporting ------------------------------------------------------

create or replace function public.moderate_message(p_message_id uuid, p_status public.message_status)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); target public.messages;
begin
  select * into target from public.messages where id = p_message_id for update;
  if actor is null or target.id is null or not private.can_moderate_channel(target.channel_id, actor) then
    raise sqlstate 'PGRST' using message = '{"code":"FORBIDDEN","message":"Moderator access is required."}', detail = '{"status":403}';
  end if;
  update public.messages set status = p_status, moderated_by = actor, moderated_at = now(), updated_at = now() where id = p_message_id;
  insert into public.audit_records (actor_id, action, entity_type, entity_id, detail)
  values (actor, 'message.moderate', 'message', p_message_id, jsonb_build_object('status', p_status));
  return jsonb_build_object('message_id', p_message_id, 'status', p_status);
end $$;

-- Reports for lounge/topic messages have no event edition; moderators of the room can read them.
alter table public.reports alter column edition_id drop not null;
alter table public.reports add constraint reports_edition_or_message check (edition_id is not null or reported_message_id is not null);

drop policy reports_read on public.reports;
create policy reports_read on public.reports for select to authenticated using (
  (select auth.uid()) = reporter_id
  or (edition_id is not null and private.can_manage_edition(edition_id))
  or (
    reported_message_id is not null
    and exists (select 1 from public.messages m where m.id = reported_message_id and private.can_moderate_channel(m.channel_id))
  )
);

create or replace function public.submit_message_report(p_message_id uuid, p_description text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); target record; saved_id uuid; created boolean := false;
begin
  select message.id, message.author_id, message.status, message.channel_id, channel.edition_id
  into target
  from public.messages message
  join public.channels channel on channel.id = message.channel_id
  where message.id = p_message_id;
  if actor is null or target.id is null or not private.can_access_channel(target.channel_id, actor) then
    raise sqlstate 'PGRST' using message = '{"code":"FORBIDDEN","message":"This discussion message is unavailable."}', detail = '{"status":403}';
  end if;
  select id into saved_id from public.reports where reporter_id = actor and reported_message_id = target.id;
  if saved_id is not null then
    return jsonb_build_object('report_id', saved_id, 'status', 'submitted', 'persisted', true, 'idempotent_replay', true);
  end if;
  if target.status <> 'visible' then
    raise sqlstate 'PGRST' using message = '{"code":"MESSAGE_UNAVAILABLE","message":"This discussion message is no longer visible."}', detail = '{"status":409}';
  end if;
  if target.author_id = actor then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_REPORT","message":"You cannot report your own message."}', detail = '{"status":422}';
  end if;
  if length(trim(coalesce(p_description, ''))) < 5 then
    raise sqlstate 'PGRST' using message = '{"code":"INVALID_REPORT","message":"Tell moderators why this message should be reviewed."}', detail = '{"status":422}';
  end if;

  insert into public.reports (edition_id, reporter_id, category, description, priority, reported_message_id)
  values (target.edition_id, actor, 'Discussion message', trim(p_description), 'normal', target.id)
  on conflict (reporter_id, reported_message_id) where reported_message_id is not null do nothing
  returning id into saved_id;
  if saved_id is null then
    select id into saved_id from public.reports where reporter_id = actor and reported_message_id = target.id;
  else
    created := true;
    insert into public.report_status_history (report_id, to_status, changed_by) values (saved_id, 'submitted', actor);
  end if;
  return jsonb_build_object('report_id', saved_id, 'status', 'submitted', 'persisted', true, 'idempotent_replay', not created);
end $$;

-- College forum: visibility follows administrator-granted memberships, not the self-editable profile college.
create function private.is_active_college_member(target_college_id uuid, target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null
    and exists (select 1 from public.profiles profile where profile.id = target_user_id and profile.status = 'active')
    and exists (
      select 1 from public.college_memberships membership
      where membership.user_id = target_user_id and membership.college_id = target_college_id and membership.status = 'active'
    );
$$;
revoke all on function private.is_active_college_member(uuid, uuid) from public;
grant execute on function private.is_active_college_member(uuid, uuid) to authenticated;

drop policy discussion_threads_same_college_read on public.discussion_threads;
create policy discussion_threads_same_college_read on public.discussion_threads
  for select to authenticated using (private.is_active_college_member(college_id));

drop policy discussion_replies_same_college_read on public.discussion_replies;
create policy discussion_replies_same_college_read on public.discussion_replies
  for select to authenticated using (
    exists (select 1 from public.discussion_threads t where t.id = discussion_replies.thread_id and private.is_active_college_member(t.college_id))
  );

create or replace function public.create_discussion_thread(p_title text, p_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); college uuid; saved uuid;
begin
  -- Prefer the profile's college when it is a confirmed membership; otherwise the first confirmed one.
  select membership.college_id into college
  from public.college_memberships membership
  join public.profiles profile on profile.id = membership.user_id and profile.status = 'active'
  where membership.user_id = actor and membership.status = 'active'
  order by (membership.college_id = profile.college_id) desc nulls last, membership.created_at
  limit 1;
  if actor is null or college is null then
    raise sqlstate 'PGRST' using message = '{"code":"PROFILE_COLLEGE_REQUIRED","message":"A confirmed college membership is required to start a discussion."}', detail = '{"status":422}';
  end if;
  insert into public.discussion_threads (college_id, author_id, title, body)
  values (college, actor, trim(p_title), trim(p_body)) returning id into saved;
  return jsonb_build_object('thread_id', saved, 'persisted', true);
end $$;

create or replace function public.reply_discussion_thread(p_thread_id uuid, p_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); saved uuid;
begin
  if actor is null or not exists (
    select 1 from public.discussion_threads t where t.id = p_thread_id and private.is_active_college_member(t.college_id, actor)
  ) then
    raise sqlstate 'PGRST' using message = '{"code":"THREAD_NOT_AVAILABLE","message":"This discussion is not available to your college account."}', detail = '{"status":404}';
  end if;
  insert into public.discussion_replies (thread_id, author_id, body) values (p_thread_id, actor, trim(p_body)) returning id into saved;
  update public.discussion_threads set updated_at = now() where id = p_thread_id;
  return jsonb_build_object('reply_id', saved, 'persisted', true);
end $$;
