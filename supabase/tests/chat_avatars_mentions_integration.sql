\set ON_ERROR_STOP on
-- Chat profile pictures and @mentions: avatar storage access, sender pictures in history, mention validation,
-- persistence, notifications, candidate search scoping, and that the Community entry's event room is the same
-- room the chat list opens. All fixtures roll back.
begin;

insert into auth.users(id,email,raw_user_meta_data) values
('10000000-0000-0000-0000-0000000000e1','mention-a@example.invalid','{"full_name":"Asha Rao"}'),
('10000000-0000-0000-0000-0000000000e2','mention-b@example.invalid','{"full_name":"Bilal Khan"}'),
('10000000-0000-0000-0000-0000000000e3','mention-partner@example.invalid','{"full_name":"Chen Li"}'),
('10000000-0000-0000-0000-0000000000e4','mention-outsider@example.invalid','{"full_name":"Dev Outsider"}'),
('10000000-0000-0000-0000-0000000000e5','mention-e@example.invalid','{"full_name":"Esha Rao"}'),
('10000000-0000-0000-0000-0000000000e6','mention-organizer@example.invalid','{"full_name":"Org Person"}');
insert into public.colleges(id,slug,name) values
('20000000-0000-0000-0000-0000000000e1','mention-college','Mention College'),
('20000000-0000-0000-0000-0000000000e2','mention-partner-college','Mention Partner College');
insert into public.college_memberships(college_id,user_id,is_admin,status) values
('20000000-0000-0000-0000-0000000000e1','10000000-0000-0000-0000-0000000000e1',false,'active'),
('20000000-0000-0000-0000-0000000000e1','10000000-0000-0000-0000-0000000000e2',false,'active'),
('20000000-0000-0000-0000-0000000000e2','10000000-0000-0000-0000-0000000000e3',false,'active'),
('20000000-0000-0000-0000-0000000000e1','10000000-0000-0000-0000-0000000000e5',false,'active'),
('20000000-0000-0000-0000-0000000000e1','10000000-0000-0000-0000-0000000000e6',false,'active');
insert into public.organizations(id,college_id,slug,name) values('30000000-0000-0000-0000-0000000000e1','20000000-0000-0000-0000-0000000000e1','mention-org','Mention Org');
insert into public.memberships(organization_id,user_id,role,status) values('30000000-0000-0000-0000-0000000000e1','10000000-0000-0000-0000-0000000000e6','organizer','active');
update public.profiles set account_type='organizer' where id='10000000-0000-0000-0000-0000000000e6';
update public.organizations set head_user_id='10000000-0000-0000-0000-0000000000e6' where id='30000000-0000-0000-0000-0000000000e1';
-- A login username is a credential: mention search must never match it.
update public.profiles set login_username='zz-secret-login' where id='10000000-0000-0000-0000-0000000000e1';

-- Uploaded pictures (Storage sets owner_id from the uploader's token).
insert into storage.objects(bucket_id,name,owner_id) values
('profile-avatars','10000000-0000-0000-0000-0000000000e1/aaaaaaaa-0000-0000-0000-000000000001.jpg','10000000-0000-0000-0000-0000000000e1'),
('profile-avatars','10000000-0000-0000-0000-0000000000e4/aaaaaaaa-0000-0000-0000-000000000004.jpg','10000000-0000-0000-0000-0000000000e4');
grant select, insert, delete on storage.objects to authenticated;
grant usage on schema storage to authenticated;

create temporary table mention_state(key text primary key,value uuid);
grant all on mention_state to authenticated;
insert into mention_state select 'lounge', id from public.channels where kind='college' and college_id='20000000-0000-0000-0000-0000000000e1';
insert into mention_state select 'commons', id from public.channels where kind='topic' and slug='commons';

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);

-- Event room for the organizer's event.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000e6',true);
do $$ declare result jsonb; begin
 result:=public.create_event('40000000-0000-0000-0000-0000000000e1','30000000-0000-0000-0000-0000000000e1','Mention event','An event to check mention scope','Social','public',0,'INR',null,now()-interval '1 hour',now()+interval '1 day',now()+interval '2 days',now()+interval '2 days 2 hours',10,true);
 perform public.publish_event((result->>'event_id')::uuid);
 insert into mention_state values('edition',(result->>'edition_id')::uuid);
 insert into mention_state select 'event_room', id from public.channels where edition_id=(result->>'edition_id')::uuid;
end $$;

-- Student A: profile picture rules.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000e1',true);
do $$ declare result jsonb; begin
 begin update public.profiles set avatar_path='10000000-0000-0000-0000-0000000000e1/x.jpg' where id='10000000-0000-0000-0000-0000000000e1'; raise exception 'direct avatar_path update allowed'; exception when insufficient_privilege then null; end;
 begin perform public.set_profile_avatar('10000000-0000-0000-0000-0000000000e4/aaaaaaaa-0000-0000-0000-000000000004.jpg'); raise exception 'used another student''s picture'; exception when sqlstate 'PGRST' then if sqlerrm not like '%INVALID_AVATAR%' then raise; end if; end;
 begin perform public.set_profile_avatar('10000000-0000-0000-0000-0000000000e1/bbbbbbbb-0000-0000-0000-000000000009.jpg'); raise exception 'missing upload accepted'; exception when sqlstate 'PGRST' then if sqlerrm not like '%INVALID_AVATAR%' then raise; end if; end;
 begin insert into storage.objects(bucket_id,name,owner_id) values('profile-avatars','10000000-0000-0000-0000-0000000000e2/cccccccc-0000-0000-0000-000000000001.jpg','10000000-0000-0000-0000-0000000000e1'); raise exception 'uploaded into another student''s folder'; exception when insufficient_privilege then null; end;
 result:=public.set_profile_avatar('10000000-0000-0000-0000-0000000000e1/aaaaaaaa-0000-0000-0000-000000000001.jpg');
 if result->>'previous_path' is not null then raise exception 'unexpected previous avatar'; end if;
 if not exists(select 1 from storage.objects where name like '10000000-0000-0000-0000-0000000000e1/%') then raise exception 'owner cannot read own picture'; end if;
end $$;

-- Student D (no confirmed college) also uploads and sets a picture, then is used to check outsiders.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000e4',true);
do $$ begin
 perform public.set_profile_avatar('10000000-0000-0000-0000-0000000000e4/aaaaaaaa-0000-0000-0000-000000000004.jpg');
 if exists(select 1 from storage.objects where name like '10000000-0000-0000-0000-0000000000e1/%') then raise exception 'student sharing no room read a picture'; end if;
end $$;

-- Student A: mentions in the lounge.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000e1',true);
do $$ declare result jsonb; replay jsonb; msg record; begin
 result:=public.send_channel_message((select value from mention_state where key='lounge'),'Hey @Bilal Khan and @Esha Rao, lunch?','60000000-0000-0000-0000-0000000000e1',
   array['10000000-0000-0000-0000-0000000000e2','10000000-0000-0000-0000-0000000000e5','10000000-0000-0000-0000-0000000000e2']::uuid[]);
 replay:=public.send_channel_message((select value from mention_state where key='lounge'),'Hey @Bilal Khan and @Esha Rao, lunch?','60000000-0000-0000-0000-0000000000e1',
   array['10000000-0000-0000-0000-0000000000e2','10000000-0000-0000-0000-0000000000e5']::uuid[]);
 if (replay->>'idempotent_replay')::boolean is not true then raise exception 'retry not idempotent'; end if;
 select * into msg from public.get_channel_messages((select value from mention_state where key='lounge')) where id=(result->>'message_id')::uuid;
 if jsonb_array_length(msg.mentions)<>2 then raise exception 'expected 2 mentions, got %', msg.mentions; end if;
 if msg.mentions->0->>'display_name'<>'Bilal Khan' or msg.mentions->1->>'display_name'<>'Esha Rao' then raise exception 'mentions out of order: %', msg.mentions; end if;
 if msg.mentions->0->>'user_id'<>'10000000-0000-0000-0000-0000000000e2' then raise exception 'mention identity lost'; end if;
 if msg.author_avatar_path<>'10000000-0000-0000-0000-0000000000e1/aaaaaaaa-0000-0000-0000-000000000001.jpg' then raise exception 'sender picture missing: %', msg.author_avatar_path; end if;

 -- A mention whose @Name was edited out of the text is dropped rather than stored.
 result:=public.send_channel_message((select value from mention_state where key='lounge'),'Never mind, see you all later',gen_random_uuid(),array['10000000-0000-0000-0000-0000000000e2']::uuid[]);
 if jsonb_array_length((select mentions from public.get_channel_messages((select value from mention_state where key='lounge')) where id=(result->>'message_id')::uuid))<>0 then raise exception 'stale mention stored'; end if;
 -- Self-mentions are ignored.
 perform public.send_channel_message((select value from mention_state where key='lounge'),'Note to @Asha Rao: me',gen_random_uuid(),array['10000000-0000-0000-0000-0000000000e1']::uuid[]);

 -- Partner-college student cannot see the lounge, unknown ids, outsiders, and >10 mentions are rejected.
 begin perform public.send_channel_message((select value from mention_state where key='lounge'),'Hi @Chen Li',gen_random_uuid(),array['10000000-0000-0000-0000-0000000000e3']::uuid[]); raise exception 'mentioned someone outside the room'; exception when sqlstate 'PGRST' then if sqlerrm not like '%MENTION_UNAVAILABLE%' then raise; end if; end;
 begin perform public.send_channel_message((select value from mention_state where key='lounge'),'Hi @Ghost',gen_random_uuid(),array[gen_random_uuid()]); raise exception 'unknown id accepted'; exception when sqlstate 'PGRST' then if sqlerrm not like '%MENTION_UNAVAILABLE%' then raise; end if; end;
 begin perform public.send_channel_message((select value from mention_state where key='lounge'),'Hi @Dev Outsider',gen_random_uuid(),array['10000000-0000-0000-0000-0000000000e4']::uuid[]); raise exception 'outsider mentioned'; exception when sqlstate 'PGRST' then if sqlerrm not like '%MENTION_UNAVAILABLE%' then raise; end if; end;
 begin perform public.send_channel_message((select value from mention_state where key='lounge'),'Hi all',gen_random_uuid(),array(select gen_random_uuid() from generate_series(1,11))); raise exception 'too many mentions accepted'; exception when sqlstate 'PGRST' then if sqlerrm not like '%TOO_MANY_MENTIONS%' then raise; end if; end;
 if (select count(*) from public.messages where body like 'Hi %')<>0 then raise exception 'rejected message persisted'; end if;

 -- Mentions are only readable through the room-checked RPC.
 begin perform 1 from public.message_mentions; raise exception 'direct mention read allowed'; exception when insufficient_privilege then null; end;
 begin insert into public.message_mentions(message_id,mentioned_user_id,display_name,body_position) values((result->>'message_id')::uuid,'10000000-0000-0000-0000-0000000000e3','Chen Li',1); raise exception 'direct mention insert allowed'; exception when insufficient_privilege then null; end;

 -- Candidate search: room members by name only, never the caller, never credentials, no wildcard dumps.
 if exists(select 1 from public.search_chat_mention_candidates((select value from mention_state where key='lounge'),'zz-secret')) then raise exception 'login username searchable'; end if;
 if exists(select 1 from public.search_chat_mention_candidates((select value from mention_state where key='lounge'),'Chen')) then raise exception 'partner student offered in lounge'; end if;
 if exists(select 1 from public.search_chat_mention_candidates((select value from mention_state where key='lounge'),'Asha')) then raise exception 'caller offered to self'; end if;
 if exists(select 1 from public.search_chat_mention_candidates((select value from mention_state where key='lounge'),'%')) then raise exception 'wildcard matched everyone'; end if;
 if (select string_agg(display_name, ',' order by display_name) from public.search_chat_mention_candidates((select value from mention_state where key='lounge'),'rao'))<>'Esha Rao' then raise exception 'name search wrong'; end if;
 if not exists(select 1 from public.search_chat_mention_candidates((select value from mention_state where key='lounge'),'bil') where display_name='Bilal Khan' and college_name='Mention College') then raise exception 'lounge member not offered'; end if;
 if not exists(select 1 from public.search_chat_mention_candidates((select value from mention_state where key='commons'),'chen')) then raise exception 'partner student not offered in topic room'; end if;
 -- Empty query in an open topic room lists recent senders only (nobody has posted there yet).
 if exists(select 1 from public.search_chat_mention_candidates((select value from mention_state where key='commons'),'')) then raise exception 'empty query listed the whole directory'; end if;
end $$;

-- Student B: sees A's picture (shared lounge), gets one mention notification, finds A as a recent sender.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000e2',true);
do $$ begin
 if not exists(select 1 from storage.objects where name='10000000-0000-0000-0000-0000000000e1/aaaaaaaa-0000-0000-0000-000000000001.jpg') then raise exception 'room member cannot read sender picture'; end if;
 if exists(select 1 from storage.objects where name like '10000000-0000-0000-0000-0000000000e4/%') then raise exception 'picture of student sharing no room readable'; end if;
 if (select count(*) from public.notifications where kind='mention')<>1 then raise exception 'expected exactly one mention notification, got %', (select count(*) from public.notifications where kind='mention'); end if;
 if (select title from public.notifications where kind='mention')<>'Asha Rao mentioned you in Mention College Lounge' then raise exception 'notification title wrong: %', (select title from public.notifications where kind='mention'); end if;
 if not exists(select 1 from public.search_chat_mention_candidates((select value from mention_state where key='lounge'),'') where display_name='Asha Rao' and recently_active and avatar_path is not null) then raise exception 'recent sender missing from empty query'; end if;
end $$;

-- Partner student: shares only topic rooms. Can read A's picture once A has a shared room; cannot search the lounge.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000e3',true);
do $$ begin
 begin perform public.search_chat_mention_candidates((select value from mention_state where key='lounge'),'a'); raise exception 'searched a room without access'; exception when sqlstate 'PGRST' then if sqlerrm not like '%CHANNEL_UNAVAILABLE%' then raise; end if; end;
 if not exists(select 1 from storage.objects where name like '10000000-0000-0000-0000-0000000000e1/%') then raise exception 'topic-room peer cannot read picture'; end if;
 if exists(select 1 from public.notifications where kind='mention') then raise exception 'mention notification leaked to another student'; end if;
end $$;

-- Event rooms: registrants are mentionable; the Community entry's event room is the same room the chat list opens.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000e2',true);
do $$ begin
 perform public.register_for_event((select value from mention_state where key='edition'),gen_random_uuid());
 if (select id from public.my_community_channels where edition_id=(select value from mention_state where key='edition'))
    is distinct from (select id from public.get_my_chat_rooms() where kind='event' and title='Mention event') then raise exception 'community and chat list point at different rooms'; end if;
 -- Legacy path (old Community screen) and new path land in one conversation.
 perform public.post_message((select value from mention_state where key='event_room'),'Sent from the legacy path');
 perform public.send_channel_message((select value from mention_state where key='event_room'),'Sent from chat with @Org Person',gen_random_uuid(),array['10000000-0000-0000-0000-0000000000e6']::uuid[]);
 if (select string_agg(body, '|' order by seq) from public.get_channel_messages((select value from mention_state where key='event_room')))<>'Sent from the legacy path|Sent from chat with @Org Person' then raise exception 'event room history split'; end if;
 if not exists(select 1 from public.search_chat_mention_candidates((select value from mention_state where key='event_room'),'org')) then raise exception 'event staff not mentionable'; end if;
 if exists(select 1 from public.search_chat_mention_candidates((select value from mention_state where key='event_room'),'esha')) then raise exception 'unregistered student offered in event room'; end if;
end $$;

reset role;
select 'chat avatars and mentions integration passed' as result;
rollback;
