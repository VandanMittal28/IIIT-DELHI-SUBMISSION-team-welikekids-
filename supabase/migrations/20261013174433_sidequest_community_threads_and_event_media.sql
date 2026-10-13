-- College forums are available to every active signed-in student;
-- event media remains private to people registered for that edition and staff.

create table public.discussion_threads (
  id uuid primary key default gen_random_uuid(),
  college_id uuid not null references public.colleges(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (length(trim(title)) between 4 and 160),
  body text not null check (length(trim(body)) between 5 and 5000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index discussion_threads_college_time_idx on public.discussion_threads(college_id, created_at desc);
create index discussion_threads_author_idx on public.discussion_threads(author_id, created_at desc);
alter table public.discussion_threads enable row level security;
create policy discussion_threads_same_college_read on public.discussion_threads
  for select to authenticated using (
    exists (select 1 from public.profiles p where p.id=(select auth.uid()) and p.status='active' and p.college_id=discussion_threads.college_id)
  );
grant select on public.discussion_threads to authenticated;

create table public.discussion_replies (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.discussion_threads(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (length(trim(body)) between 1 and 3000),
  created_at timestamptz not null default now()
);
create index discussion_replies_thread_time_idx on public.discussion_replies(thread_id, created_at);
alter table public.discussion_replies enable row level security;
create policy discussion_replies_same_college_read on public.discussion_replies
  for select to authenticated using (
    exists (
      select 1 from public.discussion_threads t join public.profiles p on p.id=(select auth.uid())
      where t.id=discussion_replies.thread_id and p.status='active' and p.college_id=t.college_id
    )
  );
grant select on public.discussion_replies to authenticated;

create function public.create_discussion_thread(p_title text,p_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); college uuid; saved uuid;
begin
  select p.college_id into college from public.profiles p where p.id=actor and p.status='active';
  if actor is null or college is null then
    raise sqlstate 'PGRST' using message='{"code":"PROFILE_COLLEGE_REQUIRED","message":"Choose your college in Profile before starting a discussion."}',detail='{"status":422}';
  end if;
  insert into public.discussion_threads(college_id,author_id,title,body)
  values(college,actor,trim(p_title),trim(p_body)) returning id into saved;
  return jsonb_build_object('thread_id',saved,'persisted',true);
end;
$$;

create function public.reply_discussion_thread(p_thread_id uuid,p_body text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); college uuid; saved uuid;
begin
  select p.college_id into college from public.profiles p where p.id=actor and p.status='active';
  if actor is null or college is null or not exists(select 1 from public.discussion_threads t where t.id=p_thread_id and t.college_id=college) then
    raise sqlstate 'PGRST' using message='{"code":"THREAD_NOT_AVAILABLE","message":"This discussion is not available to your college account."}',detail='{"status":404}';
  end if;
  insert into public.discussion_replies(thread_id,author_id,body) values(p_thread_id,actor,trim(p_body)) returning id into saved;
  update public.discussion_threads set updated_at=now() where id=p_thread_id;
  return jsonb_build_object('reply_id',saved,'persisted',true);
end;
$$;
revoke all on function public.create_discussion_thread(text,text),public.reply_discussion_thread(uuid,text) from public,anon;
grant execute on function public.create_discussion_thread(text,text),public.reply_discussion_thread(uuid,text) to authenticated;

create table public.event_media (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references public.event_editions(id) on delete cascade,
  uploaded_by uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null unique,
  caption text check (caption is null or length(trim(caption))<=500),
  created_at timestamptz not null default now(),
  check (storage_path like edition_id::text || '/' || uploaded_by::text || '/%')
);
create index event_media_edition_time_idx on public.event_media(edition_id,created_at desc);
create function private.can_access_event_media(target_edition_id uuid,target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null and exists(
    select 1 from public.profiles p where p.id=target_user_id and p.status='active'
      and (exists(select 1 from public.registrations r where r.edition_id=target_edition_id and r.user_id=target_user_id and r.status='registered')
        or private.can_manage_edition(target_edition_id,target_user_id))
  );
$$;
revoke all on function private.can_access_event_media(uuid,uuid) from public;
grant execute on function private.can_access_event_media(uuid,uuid) to authenticated;
alter table public.event_media enable row level security;
create policy event_media_attendee_read on public.event_media for select to authenticated
  using (private.can_access_event_media(edition_id) and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.status='active'));
grant select on public.event_media to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('event-attendee-media','event-attendee-media',false,10485760,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

create policy event_attendee_media_upload on storage.objects for insert to authenticated with check (
  bucket_id='event-attendee-media'
  and (storage.foldername(name))[2]=(select auth.uid())::text
  and private.can_access_event_media(((storage.foldername(name))[1])::uuid)
);
create policy event_attendee_media_read on storage.objects for select to authenticated using (
  bucket_id='event-attendee-media'
  and private.can_access_event_media(((storage.foldername(name))[1])::uuid)
);

create function public.add_event_media(p_edition_id uuid,p_storage_path text,p_caption text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid:=auth.uid(); saved uuid;
begin
  if actor is null or not private.can_access_event_media(p_edition_id,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"An active event registration is required to share event photos."}',detail='{"status":403}';
  end if;
  if p_storage_path !~ ('^'||p_edition_id::text||'/'||actor::text||'/[A-Za-z0-9._-]+$') then
    raise sqlstate 'PGRST' using message='{"code":"INVALID_MEDIA_PATH","message":"The photo path is not valid for this event."}',detail='{"status":422}';
  end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='event-attendee-media' and o.name=p_storage_path and o.owner_id=actor::text) then
    raise sqlstate 'PGRST' using message='{"code":"MEDIA_NOT_FOUND","message":"Upload the photo before sharing it."}',detail='{"status":404}';
  end if;
  insert into public.event_media(edition_id,uploaded_by,storage_path,caption)
  values(p_edition_id,actor,p_storage_path,nullif(trim(p_caption),''))
  on conflict(storage_path) do nothing returning id into saved;
  if saved is null then select id into saved from public.event_media where storage_path=p_storage_path; end if;
  return jsonb_build_object('media_id',saved,'persisted',true);
end;
$$;
revoke all on function public.add_event_media(uuid,text,text) from public,anon;
grant execute on function public.add_event_media(uuid,text,text) to authenticated;

-- Creating an event with a venue is one transaction; an unavailable venue or
-- failed session insert rolls the event and edition back together.
create function public.create_event_with_venue(
  p_client_request_id uuid,p_organization_id uuid,p_title text,p_description text,p_category text,
  p_visibility public.event_visibility,p_price_minor integer,p_currency text,p_eligibility text,
  p_registration_opens_at timestamptz,p_registration_closes_at timestamptz,p_starts_at timestamptz,
  p_ends_at timestamptz,p_capacity integer,p_waitlist_enabled boolean,p_venue_id uuid
)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare result jsonb; edition uuid;
begin
  if p_venue_id is null then
    raise sqlstate 'PGRST' using message='{"code":"VENUE_REQUIRED","message":"Choose a venue before creating the event."}',detail='{"status":422}';
  end if;
  result:=public.create_event(p_client_request_id,p_organization_id,p_title,p_description,p_category,p_visibility,p_price_minor,p_currency,p_eligibility,p_registration_opens_at,p_registration_closes_at,p_starts_at,p_ends_at,p_capacity,p_waitlist_enabled);
  edition:=(result->>'edition_id')::uuid;
  if not exists(
    select 1 from public.event_editions ee join public.events e on e.id=ee.event_id
    join public.venues v on v.id=p_venue_id join public.campuses c on c.id=v.campus_id
    where ee.id=edition and c.college_id=e.college_id
  ) then
    raise sqlstate 'PGRST' using message='{"code":"INVALID_VENUE","message":"Choose a venue from the event organization’s college."}',detail='{"status":422}';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(edition::text,0));
  if not exists(select 1 from public.event_sessions s where s.edition_id=edition) then
    perform public.create_event_session(edition,p_venue_id,trim(p_title),p_starts_at,p_ends_at);
  end if;
  return result||jsonb_build_object('venue_id',p_venue_id,'persisted',true);
end;
$$;
revoke all on function public.create_event_with_venue(uuid,uuid,text,text,text,public.event_visibility,integer,text,text,timestamptz,timestamptz,timestamptz,timestamptz,integer,boolean,uuid) from public,anon;
grant execute on function public.create_event_with_venue(uuid,uuid,text,text,text,public.event_visibility,integer,text,text,timestamptz,timestamptz,timestamptz,timestamptz,integer,boolean,uuid) to authenticated;
