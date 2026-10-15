\set ON_ERROR_STOP on
-- Student chatrooms: room access by kind, sender identity, validation, idempotency, rate limit,
-- pagination, unread counts, moderation, reporting, unchanged event rooms, and the forum membership fix.
-- All fixtures roll back.
begin;

insert into auth.users(id,email,raw_user_meta_data) values
('10000000-0000-0000-0000-0000000000d1','chat-a@example.invalid','{"full_name":"Asha"}'),
('10000000-0000-0000-0000-0000000000d2','chat-b@example.invalid','{"full_name":"Bilal"}'),
('10000000-0000-0000-0000-0000000000d3','chat-partner@example.invalid','{"full_name":"Chen"}'),
('10000000-0000-0000-0000-0000000000d4','chat-unaffiliated@example.invalid','{}'),
('10000000-0000-0000-0000-0000000000d5','chat-admin@example.invalid','{"full_name":"Admin"}'),
('10000000-0000-0000-0000-0000000000d6','chat-organizer@example.invalid','{"full_name":"Org"}');
insert into public.colleges(id,slug,name) values
('20000000-0000-0000-0000-0000000000d1','chat-college','Chat College'),
('20000000-0000-0000-0000-0000000000d2','chat-partner-college','Chat Partner College');
insert into public.college_memberships(college_id,user_id,is_admin,status) values
('20000000-0000-0000-0000-0000000000d1','10000000-0000-0000-0000-0000000000d1',false,'active'),
('20000000-0000-0000-0000-0000000000d1','10000000-0000-0000-0000-0000000000d2',false,'active'),
('20000000-0000-0000-0000-0000000000d2','10000000-0000-0000-0000-0000000000d3',false,'active'),
('20000000-0000-0000-0000-0000000000d1','10000000-0000-0000-0000-0000000000d5',true,'active'),
('20000000-0000-0000-0000-0000000000d1','10000000-0000-0000-0000-0000000000d6',false,'active');
insert into public.organizations(id,college_id,slug,name) values('30000000-0000-0000-0000-0000000000d1','20000000-0000-0000-0000-0000000000d1','chat-org','Chat Org');
insert into public.memberships(organization_id,user_id,role,status) values('30000000-0000-0000-0000-0000000000d1','10000000-0000-0000-0000-0000000000d6','organizer','active');
update public.profiles set account_type='organizer' where id='10000000-0000-0000-0000-0000000000d6';
update public.organizations set head_user_id='10000000-0000-0000-0000-0000000000d6' where id='30000000-0000-0000-0000-0000000000d1';

create temporary table chat_state(key text primary key,value uuid);
grant all on chat_state to authenticated;
insert into chat_state select 'lounge', id from public.channels where kind='college' and college_id='20000000-0000-0000-0000-0000000000d1';
insert into chat_state select 'partner_lounge', id from public.channels where kind='college' and college_id='20000000-0000-0000-0000-0000000000d2';
insert into chat_state select 'commons', id from public.channels where kind='topic' and slug='commons';
-- Profiles get the student's college so the forum fix can be checked against a forged profile college.
update public.profiles set college_id='20000000-0000-0000-0000-0000000000d1' where id in ('10000000-0000-0000-0000-0000000000d1','10000000-0000-0000-0000-0000000000d2');

do $$ begin
 if (select count(*) from chat_state where value is not null)<>3 then raise exception 'rooms were not provisioned for new colleges and topics'; end if;
 if (select count(*) from public.channels where kind='topic')<>5 then raise exception 'topic rooms missing'; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);

-- An event room for the organizer's event (unchanged event semantics).
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000d6',true);
do $$ declare result jsonb; begin
 result:=public.create_event('40000000-0000-0000-0000-0000000000d1','30000000-0000-0000-0000-0000000000d1','Chat event','An event to check event rooms','Social','public',0,'INR',null,now()-interval '1 hour',now()+interval '1 day',now()+interval '2 days',now()+interval '2 days 2 hours',10,true);
 perform public.publish_event((result->>'event_id')::uuid);
 insert into chat_state values('edition',(result->>'edition_id')::uuid);
 insert into chat_state select 'event_room', id from public.channels where edition_id=(result->>'edition_id')::uuid;
end $$;

-- Student A: sees own lounge + topics, not the partner lounge or the event room (not registered).
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000d1',true);
do $$ declare result jsonb; replay jsonb; rooms integer; begin
 select count(*) into rooms from public.get_my_chat_rooms();
 if rooms<>6 then raise exception 'student A expected 6 rooms (lounge + 5 topics), got %', rooms; end if;
 if exists(select 1 from public.get_my_chat_rooms() where id=(select value from chat_state where key='partner_lounge')) then raise exception 'other college lounge visible'; end if;
 if exists(select 1 from public.channels where id=(select value from chat_state where key='event_room')) then raise exception 'unregistered student sees event room'; end if;

 result:=public.send_channel_message((select value from chat_state where key='lounge'),'  Hello lounge!  ','50000000-0000-0000-0000-0000000000d1');
 replay:=public.send_channel_message((select value from chat_state where key='lounge'),'  Hello lounge!  ','50000000-0000-0000-0000-0000000000d1');
 if (replay->>'idempotent_replay')::boolean is not true or replay->>'message_id'<>result->>'message_id' then raise exception 'retry duplicated message'; end if;
 if (select count(*) from public.messages where channel_id=(select value from chat_state where key='lounge'))<>1 then raise exception 'duplicate message row'; end if;
 if (select body from public.messages where id=(result->>'message_id')::uuid)<>'Hello lounge!' then raise exception 'message not trimmed'; end if;

 begin perform public.send_channel_message((select value from chat_state where key='lounge'),'   ',gen_random_uuid()); raise exception 'empty message accepted'; exception when sqlstate 'PGRST' then if sqlerrm not like '%MESSAGE_EMPTY%' then raise; end if; end;
 begin perform public.send_channel_message((select value from chat_state where key='lounge'),repeat('x',2001),gen_random_uuid()); raise exception 'long message accepted'; exception when sqlstate 'PGRST' then if sqlerrm not like '%MESSAGE_TOO_LONG%' then raise; end if; end;
 begin perform public.send_channel_message((select value from chat_state where key='partner_lounge'),'Sneaking in',gen_random_uuid()); raise exception 'posted to other college lounge'; exception when sqlstate 'PGRST' then if sqlerrm not like '%CHANNEL_UNAVAILABLE%' then raise; end if; end;
 begin perform public.get_channel_messages((select value from chat_state where key='partner_lounge')); raise exception 'read other college lounge'; exception when sqlstate 'PGRST' then null; end;
 begin insert into public.messages(channel_id,author_id,body) values((select value from chat_state where key='lounge'),'10000000-0000-0000-0000-0000000000d2','Forged sender'); raise exception 'direct insert allowed'; exception when insufficient_privilege then null; end;
 begin insert into public.channel_reads(user_id,channel_id) values('10000000-0000-0000-0000-0000000000d1',(select value from chat_state where key='lounge')); raise exception 'direct read-marker insert allowed'; exception when insufficient_privilege then null; end;

 perform public.send_channel_message((select value from chat_state where key='commons'),'Hi from Chat College',gen_random_uuid());
end $$;

-- Partner-college student shares topic rooms only; sees sender name + college; unread counts work.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000d3',true);
do $$ declare msg record; begin
 if exists(select 1 from public.get_my_chat_rooms() where id=(select value from chat_state where key='lounge')) then raise exception 'partner student sees Chat College lounge'; end if;
 if (select unread_count from public.get_my_chat_rooms() where id=(select value from chat_state where key='commons'))<>1 then raise exception 'unread count wrong'; end if;
 select * into msg from public.get_channel_messages((select value from chat_state where key='commons')) limit 1;
 if msg.author_name<>'Asha' or msg.author_college<>'Chat College' or msg.is_mine then raise exception 'sender identity wrong: % / % / %', msg.author_name, msg.author_college, msg.is_mine; end if;
 perform public.mark_channel_read((select value from chat_state where key='commons'));
 if (select unread_count from public.get_my_chat_rooms() where id=(select value from chat_state where key='commons'))<>0 then raise exception 'mark read failed'; end if;
 if (select count(*) from public.messages where channel_id=(select value from chat_state where key='lounge'))<>0 then raise exception 'RLS leaked lounge messages to partner student'; end if;
end $$;

-- Unaffiliated student sees no rooms and cannot post.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000d4',true);
do $$ begin
 if exists(select 1 from public.get_my_chat_rooms()) then raise exception 'unaffiliated student sees rooms'; end if;
 begin perform public.send_channel_message((select value from chat_state where key='commons'),'hello',gen_random_uuid()); raise exception 'unaffiliated posted'; exception when sqlstate 'PGRST' then null; end;
end $$;

-- Pagination, rate limit, and reporting by student B.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000d2',true);
do $$ declare cursor_seq bigint; i integer; reported jsonb; begin
 for i in 1..8 loop perform public.send_channel_message((select value from chat_state where key='lounge'),'Message '||i,gen_random_uuid()); end loop;
 begin perform public.send_channel_message((select value from chat_state where key='lounge'),'One too many',gen_random_uuid()); raise exception 'rate limit not enforced'; exception when sqlstate 'PGRST' then if sqlerrm not like '%RATE_LIMITED%' then raise; end if; end;
 -- 9 visible lounge messages: Asha's + 8. Newest page of 3, then the 6 older ones, then the 2 newer than the cursor.
 if (select count(*) from public.get_channel_messages((select value from chat_state where key='lounge'),null,null,3))<>3 then raise exception 'page size ignored'; end if;
 select min(seq) into cursor_seq from public.get_channel_messages((select value from chat_state where key='lounge'),null,null,3);
 if (select count(*) from public.get_channel_messages((select value from chat_state where key='lounge'),cursor_seq,null,50))<>6 then raise exception 'older page wrong'; end if;
 if (select string_agg(body, ',' order by seq) from public.get_channel_messages((select value from chat_state where key='lounge'),null,cursor_seq,50))<>'Message 7,Message 8' then raise exception 'gap fill wrong'; end if;
 if (select string_agg(body, ',' order by seq) from public.get_channel_messages((select value from chat_state where key='lounge'),null,null,50) where body like 'Message %')<>'Message 1,Message 2,Message 3,Message 4,Message 5,Message 6,Message 7,Message 8' then raise exception 'insertion order lost'; end if;
 reported:=public.submit_message_report((select id from public.messages where body='Hello lounge!'),'Testing a lounge report');
 if reported->>'status'<>'submitted' then raise exception 'lounge message report failed'; end if;
 insert into chat_state values('report',(reported->>'report_id')::uuid);
 begin perform public.moderate_message((select id from public.messages where body='Hello lounge!'),'hidden'); raise exception 'student moderated'; exception when sqlstate 'PGRST' then if sqlerrm not like '%FORBIDDEN%' then raise; end if; end;
end $$;

-- College admin moderates the lounge and can read the report; hidden messages disappear for students.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000d5',true);
do $$ begin
 if not exists(select 1 from public.reports where id=(select value from chat_state where key='report')) then raise exception 'college admin cannot read lounge report'; end if;
 perform public.moderate_message((select id from public.messages where body='Hello lounge!'),'hidden');
 begin perform public.moderate_message((select id from public.messages where body='Hi from Chat College'),'hidden'); raise exception 'college admin moderated a topic room'; exception when sqlstate 'PGRST' then null; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000d1',true);
do $$ begin
 if exists(select 1 from public.get_channel_messages((select value from chat_state where key='lounge')) where body='Hello lounge!') then raise exception 'hidden message still returned'; end if;
 -- Event rooms: registration grants access, legacy post_message still works.
 perform public.register_for_event((select value from chat_state where key='edition'),gen_random_uuid());
 if not exists(select 1 from public.get_my_chat_rooms() where id=(select value from chat_state where key='event_room') and kind='event' and title='Chat event') then raise exception 'event room missing after registration'; end if;
 if (public.post_message((select value from chat_state where key='event_room'),'Legacy client message')->>'persisted')<>'true' then raise exception 'legacy post_message broken'; end if;
 begin perform public.post_message((select value from chat_state where key='event_room'),'  '); raise exception 'legacy empty accepted'; exception when sqlstate 'PGRST' then null; end;
 perform public.create_discussion_thread('Chat College forum','Thread created by a member');
end $$;

-- Forum fix: forging the profile college does not open another college's forum.
reset role;
update public.profiles set college_id='20000000-0000-0000-0000-0000000000d1' where id='10000000-0000-0000-0000-0000000000d3';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000d3',true);
do $$ begin
 if exists(select 1 from public.discussion_threads where title='Chat College forum') then raise exception 'forged profile college reads other forum'; end if;
 begin perform public.reply_discussion_thread((select id from public.discussion_threads limit 1),'forged reply'); raise exception 'forged profile college replied'; exception when sqlstate 'PGRST' then null; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000d2',true);
do $$ begin
 if not exists(select 1 from public.discussion_threads where title='Chat College forum') then raise exception 'member cannot read own college forum'; end if;
end $$;

reset role;
select 'chatrooms integration passed' as result;
rollback;
