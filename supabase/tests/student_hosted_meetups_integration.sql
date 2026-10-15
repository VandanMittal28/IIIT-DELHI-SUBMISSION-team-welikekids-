\set ON_ERROR_STOP on
-- Student-hosted Open Meetups: authentication, ownership, college membership, validation,
-- idempotency, hosting limit, cancellation, and no implicit recognition. All fixtures roll back.
begin;

insert into auth.users(id,email) values
('10000000-0000-0000-0000-0000000000c1','host-student@example.invalid'),
('10000000-0000-0000-0000-0000000000c2','joiner1@example.invalid'),
('10000000-0000-0000-0000-0000000000c3','joiner2@example.invalid'),
('10000000-0000-0000-0000-0000000000c4','joiner3@example.invalid'),
('10000000-0000-0000-0000-0000000000c5','partner-student@example.invalid'),
('10000000-0000-0000-0000-0000000000c6','unaffiliated@example.invalid');
insert into public.colleges(id,slug,name) values
('20000000-0000-0000-0000-0000000000c1','host-college','Host College'),
('20000000-0000-0000-0000-0000000000c2','partner-college-c','Partner College C');
insert into public.college_memberships(college_id,user_id,is_admin,status) values
('20000000-0000-0000-0000-0000000000c1','10000000-0000-0000-0000-0000000000c1',false,'active'),
('20000000-0000-0000-0000-0000000000c1','10000000-0000-0000-0000-0000000000c2',false,'active'),
('20000000-0000-0000-0000-0000000000c1','10000000-0000-0000-0000-0000000000c3',false,'active'),
('20000000-0000-0000-0000-0000000000c1','10000000-0000-0000-0000-0000000000c4',false,'active'),
('20000000-0000-0000-0000-0000000000c2','10000000-0000-0000-0000-0000000000c5',false,'active');
insert into public.campuses(id,college_id,name,latitude,longitude) values
('21000000-0000-0000-0000-0000000000c1','20000000-0000-0000-0000-0000000000c1','Host Campus',28.5,77.2),
('21000000-0000-0000-0000-0000000000c2','20000000-0000-0000-0000-0000000000c2','Partner Campus C',28.6,77.3);
insert into public.venues(id,campus_id,name,kind) values
('22000000-0000-0000-0000-0000000000c1','21000000-0000-0000-0000-0000000000c1','Host Canteen','building'),
('22000000-0000-0000-0000-0000000000c2','21000000-0000-0000-0000-0000000000c2','Partner Lawn','outdoor');
create temporary table hosted_state(key text primary key,value uuid);
grant all on hosted_state to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);

-- Unauthenticated callers are rejected.
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform public.host_open_meetup(gen_random_uuid(),'20000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c1','Chai','A casual chai meetup',now()+interval '1 day',now()+interval '1 day 1 hour',5,'Host'); raise exception 'anonymous host accepted'; exception when sqlstate 'PGRST' then if sqlerrm not like '%AUTH_REQUIRED%' then raise; end if; end;
end $$;

-- An ordinary student hosts at their own college; duplicate submission replays the same meetup.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000c1',true);
do $$ declare result jsonb; replay jsonb; begin
 result:=public.host_open_meetup('40000000-0000-0000-0000-0000000000c1','20000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c1','Post-class hangout','Come say hi after class, no agenda.',now()+interval '1 day',now()+interval '1 day 1 hour',2,'Riya','selected_colleges',array['20000000-0000-0000-0000-0000000000c2']::uuid[],null,'By the steps');
 replay:=public.host_open_meetup('40000000-0000-0000-0000-0000000000c1','20000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c1','Post-class hangout','Come say hi after class, no agenda.',now()+interval '1 day',now()+interval '1 day 1 hour',2,'Riya','selected_colleges',array['20000000-0000-0000-0000-0000000000c2']::uuid[],null,'By the steps');
 if result->>'status'<>'published' or replay->>'meetup_id'<>result->>'meetup_id' or (replay->>'idempotent_replay')::boolean is not true then raise exception 'hosting not idempotent'; end if;
 if (select count(*) from public.open_meetups where created_by='10000000-0000-0000-0000-0000000000c1')<>1 then raise exception 'duplicate meetup row'; end if;
 insert into hosted_state values('meetup',(result->>'meetup_id')::uuid);
 if not exists(select 1 from public.open_meetup_feed where id=(result->>'meetup_id')::uuid and is_host and not host_verified and host_name='Riya' and participating_colleges=array['Host College','Partner College C'] and icebreaker is not null) then raise exception 'host feed projection incorrect'; end if;
 if exists(select 1 from public.meetup_hosts where user_id='10000000-0000-0000-0000-0000000000c1') then raise exception 'hosting granted recognition'; end if;
 -- Validation and scope.
 begin perform public.host_open_meetup(gen_random_uuid(),'20000000-0000-0000-0000-0000000000c2','22000000-0000-0000-0000-0000000000c2','Other college','Hosting at a college I do not belong to',now()+interval '1 day',now()+interval '1 day 1 hour',5,'Riya'); raise exception 'non-member hosted'; exception when sqlstate 'PGRST' then if sqlerrm not like '%NOT_COLLEGE_MEMBER%' then raise; end if; end;
 begin perform public.host_open_meetup(gen_random_uuid(),'20000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c2','Wrong venue','Venue on another campus entirely',now()+interval '1 day',now()+interval '1 day 1 hour',5,'Riya'); raise exception 'foreign venue accepted'; exception when sqlstate 'PGRST' then if sqlerrm not like '%INVALID_VENUE%' then raise; end if; end;
 begin perform public.host_open_meetup(gen_random_uuid(),'20000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c1','Tiny','Capacity of one is not a meetup',now()+interval '1 day',now()+interval '1 day 1 hour',1,'Riya'); raise exception 'capacity 1 accepted'; exception when sqlstate 'PGRST' then if sqlerrm not like '%INVALID_CAPACITY%' then raise; end if; end;
 begin perform public.host_open_meetup(gen_random_uuid(),'20000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c1','Huge','Capacity above the limit',now()+interval '1 day',now()+interval '1 day 1 hour',501,'Riya'); raise exception 'capacity 501 accepted'; exception when sqlstate 'PGRST' then if sqlerrm not like '%INVALID_CAPACITY%' then raise; end if; end;
 begin perform public.host_open_meetup(gen_random_uuid(),'20000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c1','Past','Starts in the past',now()-interval '1 hour',now()+interval '1 hour',5,'Riya'); raise exception 'past start accepted'; exception when sqlstate 'PGRST' then if sqlerrm not like '%INVALID_MEETUP_SCHEDULE%' then raise; end if; end;
 begin perform public.host_open_meetup(gen_random_uuid(),'20000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c1','  ','Blank title',now()+interval '1 day',now()+interval '1 day 1 hour',5,'Riya'); raise exception 'blank title accepted'; exception when sqlstate 'PGRST' then if sqlerrm not like '%INVALID_MEETUP_DETAILS%' then raise; end if; end;
 -- Students cannot recognise themselves or use the recognised-host creation path.
 begin perform public.set_meetup_host('10000000-0000-0000-0000-0000000000c1','20000000-0000-0000-0000-0000000000c1','Riya'); raise exception 'student self-recognised'; exception when sqlstate 'PGRST' then null; end;
 begin perform public.create_open_meetup(gen_random_uuid(),'10000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c1','Bypass','Recognised path bypass attempt',now()+interval '1 day',now()+interval '1 day 1 hour',5); raise exception 'recognised path bypassed'; exception when sqlstate 'PGRST' then null; end;
end $$;

-- A student with no college membership cannot host.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000c6',true);
do $$ begin
 begin perform public.host_open_meetup(gen_random_uuid(),'20000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c1','Sneaky','No college membership here',now()+interval '1 day',now()+interval '1 day 1 hour',5,'Anon'); raise exception 'unaffiliated hosted'; exception when sqlstate 'PGRST' then if sqlerrm not like '%NOT_COLLEGE_MEMBER%' then raise; end if; end;
end $$;

-- Existing registration rules still apply to student-hosted meetups.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000c2',true);
do $$ begin
 perform public.join_open_meetup((select value from hosted_state where key='meetup'));
 if exists(select 1 from public.open_meetup_feed where is_host) then raise exception 'non-host flagged as host'; end if;
 begin perform public.set_open_meetup_status((select value from hosted_state where key='meetup'),'cancelled'); raise exception 'other student cancelled meetup'; exception when sqlstate 'PGRST' then if sqlerrm not like '%FORBIDDEN%' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000c5',true);
do $$ declare result jsonb; begin
 result:=public.join_open_meetup((select value from hosted_state where key='meetup'));
 if (result->>'going_count')::int<>2 then raise exception 'partner college student could not join'; end if;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000c3',true);
do $$ begin
 begin perform public.join_open_meetup((select value from hosted_state where key='meetup')); raise exception 'capacity exceeded'; exception when sqlstate 'PGRST' then if sqlerrm not like '%MEETUP_FULL%' then raise; end if; end;
end $$;

-- The host cancels their own meetup; every spot is released and the host still sees it.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000c1',true);
do $$ declare result jsonb; begin
 result:=public.set_open_meetup_status((select value from hosted_state where key='meetup'),'cancelled');
 if result->>'status'<>'cancelled' then raise exception 'host cancel failed'; end if;
 if not exists(select 1 from public.open_meetup_feed where id=(select value from hosted_state where key='meetup') and status='cancelled' and going_count=0 and is_host) then raise exception 'cancelled meetup not visible to host'; end if;
 if exists(select 1 from public.open_meetup_registrations where meetup_id=(select value from hosted_state where key='meetup') and status='going') then raise exception 'cancel kept spots'; end if;
 -- Hosting limit: cancelled meetups do not count; a fourth upcoming meetup is refused.
 perform public.host_open_meetup(gen_random_uuid(),'20000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c1','Campus walk one','A casual campus walk together',now()+interval '2 days',now()+interval '2 days 1 hour',10,'Riya','all_colleges');
 perform public.host_open_meetup(gen_random_uuid(),'20000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c1','Campus walk two','A casual campus walk together',now()+interval '3 days',now()+interval '3 days 1 hour',10,'Riya');
 perform public.host_open_meetup(gen_random_uuid(),'20000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c1','Campus walk three','A casual campus walk together',now()+interval '4 days',now()+interval '4 days 1 hour',10,'Riya');
 begin perform public.host_open_meetup(gen_random_uuid(),'20000000-0000-0000-0000-0000000000c1','22000000-0000-0000-0000-0000000000c1','Campus walk four','A casual campus walk together',now()+interval '5 days',now()+interval '5 days 1 hour',10,'Riya'); raise exception 'hosting limit bypassed'; exception when sqlstate 'PGRST' then if sqlerrm not like '%HOSTING_LIMIT%' then raise; end if; end;
end $$;

-- The all-colleges meetup is visible to a partner-college student.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000c5',true);
do $$ begin
 if not exists(select 1 from public.open_meetup_feed where title='Campus walk one' and is_eligible) then raise exception 'all-colleges meetup hidden'; end if;
 if exists(select 1 from public.open_meetup_feed where title='Campus walk two') then raise exception 'single-college meetup leaked'; end if;
end $$;

-- Deleting the host account cancels their upcoming meetups.
reset role;
update public.profiles set status='deleted' where id='10000000-0000-0000-0000-0000000000c1';
do $$ begin
 if exists(select 1 from public.open_meetups where host_id='10000000-0000-0000-0000-0000000000c1' and status<>'cancelled') then raise exception 'deleted host meetups still active'; end if;
end $$;

select 'student hosted meetups integration passed' as result;
rollback;
