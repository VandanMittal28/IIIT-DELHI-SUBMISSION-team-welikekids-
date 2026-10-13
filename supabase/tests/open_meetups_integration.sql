\set ON_ERROR_STOP on
-- Open Meetups authorization, eligibility, duplicate and capacity checks.
-- Run after the full migration chain on a disposable database; all fixtures roll back.
begin;

insert into auth.users(id,email) values
('10000000-0000-0000-0000-0000000000a1','admin@example.invalid'),
('10000000-0000-0000-0000-0000000000a2','host@example.invalid'),
('10000000-0000-0000-0000-0000000000a3','student1@example.invalid'),
('10000000-0000-0000-0000-0000000000a4','student2@example.invalid'),
('10000000-0000-0000-0000-0000000000a5','student3@example.invalid'),
('10000000-0000-0000-0000-0000000000a6','outsider@example.invalid'),
('10000000-0000-0000-0000-0000000000a7','unaffiliated@example.invalid');
insert into public.colleges(id,slug,name) values
('20000000-0000-0000-0000-0000000000a1','meetup-college','Meetup College'),
('20000000-0000-0000-0000-0000000000a2','partner-college','Partner College');
insert into public.college_memberships(college_id,user_id,is_admin,status) values
('20000000-0000-0000-0000-0000000000a1','10000000-0000-0000-0000-0000000000a1',true,'active'),
('20000000-0000-0000-0000-0000000000a1','10000000-0000-0000-0000-0000000000a2',false,'active'),
('20000000-0000-0000-0000-0000000000a1','10000000-0000-0000-0000-0000000000a3',false,'active'),
('20000000-0000-0000-0000-0000000000a1','10000000-0000-0000-0000-0000000000a4',false,'active'),
('20000000-0000-0000-0000-0000000000a1','10000000-0000-0000-0000-0000000000a5',false,'active'),
('20000000-0000-0000-0000-0000000000a2','10000000-0000-0000-0000-0000000000a6',false,'active');
insert into public.campuses(id,college_id,name,latitude,longitude) values
('21000000-0000-0000-0000-0000000000a1','20000000-0000-0000-0000-0000000000a1','Meetup Campus',28.5,77.2),
('21000000-0000-0000-0000-0000000000a2','20000000-0000-0000-0000-0000000000a2','Partner Campus',28.6,77.3);
insert into public.venues(id,campus_id,name,kind) values
('22000000-0000-0000-0000-0000000000a1','21000000-0000-0000-0000-0000000000a1','Canteen','building'),
('22000000-0000-0000-0000-0000000000a2','21000000-0000-0000-0000-0000000000a2','Partner Hall','hall');
create temporary table meetup_state(key text primary key,value uuid);
grant all on meetup_state to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);

-- Students cannot recognise hosts or create meetups.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a3',true);
do $$ begin
 begin perform public.set_meetup_host('10000000-0000-0000-0000-0000000000a3','20000000-0000-0000-0000-0000000000a1','Self Promoted'); raise exception 'student recognised self as host'; exception when sqlstate 'PGRST' then null; end;
 begin perform public.create_open_meetup(gen_random_uuid(),'10000000-0000-0000-0000-0000000000a3','22000000-0000-0000-0000-0000000000a1','Chai','Unrecognised host meetup',now()+interval '1 day',now()+interval '1 day 1 hour',5); raise exception 'unrecognised student created meetup'; exception when sqlstate 'PGRST' then null; end;
end $$;

-- A college administrator recognises an active member as a host.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a1',true);
do $$ begin
 perform public.set_meetup_host('10000000-0000-0000-0000-0000000000a2','20000000-0000-0000-0000-0000000000a1','Aarav','Final-year CSE');
 begin perform public.set_meetup_host('10000000-0000-0000-0000-0000000000a6','20000000-0000-0000-0000-0000000000a1','Outsider'); raise exception 'non-member recognised as host'; exception when sqlstate 'PGRST' then null; end;
end $$;

-- The recognised host creates a single-college meetup (capacity 2) and an all-colleges meetup.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a2',true);
do $$ declare result jsonb; replay jsonb; begin
 result:=public.create_open_meetup('40000000-0000-0000-0000-0000000000a1','10000000-0000-0000-0000-0000000000a2','22000000-0000-0000-0000-0000000000a1','Canteen Chai Meetup','Grab chai and meet someone new.',now()+interval '1 day',now()+interval '1 day 1 hour',2);
 replay:=public.create_open_meetup('40000000-0000-0000-0000-0000000000a1','10000000-0000-0000-0000-0000000000a2','22000000-0000-0000-0000-0000000000a1','Canteen Chai Meetup','Grab chai and meet someone new.',now()+interval '1 day',now()+interval '1 day 1 hour',2);
 if result->>'status'<>'published' or replay->>'meetup_id'<>result->>'meetup_id' or (replay->>'idempotent_replay')::boolean is not true then raise exception 'meetup creation not idempotent'; end if;
 insert into meetup_state values('single',(result->>'meetup_id')::uuid);
 result:=public.create_open_meetup('40000000-0000-0000-0000-0000000000a2','10000000-0000-0000-0000-0000000000a2','22000000-0000-0000-0000-0000000000a1','Meet Students From Other Colleges','Everyone welcome, no agenda.',now()+interval '2 days',now()+interval '2 days 2 hours',5,'all_colleges');
 insert into meetup_state values('open',(result->>'meetup_id')::uuid);
 if (select icebreaker from public.open_meetups where id=(result->>'meetup_id')::uuid) is null then raise exception 'default icebreaker missing'; end if;
 begin perform public.create_open_meetup(gen_random_uuid(),'10000000-0000-0000-0000-0000000000a2','22000000-0000-0000-0000-0000000000a2','Wrong venue','Venue on another campus',now()+interval '1 day',now()+interval '1 day 1 hour',5); raise exception 'foreign venue accepted'; exception when sqlstate 'PGRST' then null; end;
end $$;

-- Join, duplicate prevention, and direct-write denial.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a3',true);
do $$ declare result jsonb; meetup uuid:=(select value from meetup_state where key='single'); begin
 result:=public.join_open_meetup(meetup);
 if result->>'status'<>'going' or (result->>'going_count')::int<>1 then raise exception 'join failed'; end if;
 result:=public.join_open_meetup(meetup);
 if (result->>'idempotent_replay')::boolean is not true or (result->>'going_count')::int<>1 then raise exception 'duplicate join counted'; end if;
 if (select count(*) from public.open_meetup_registrations where meetup_id=meetup)<>1 then raise exception 'duplicate registration row'; end if;
 if not exists(select 1 from public.open_meetup_feed where id=meetup and my_status='going' and host_verified and participating_colleges=array['Meetup College']) then raise exception 'feed projection incorrect'; end if;
 begin insert into public.open_meetup_registrations(meetup_id,user_id,status) values(meetup,'10000000-0000-0000-0000-0000000000a4','going'); raise exception 'direct registration insert allowed'; exception when insufficient_privilege then null; end;
 begin update public.open_meetups set going_count=0 where id=meetup; raise exception 'direct meetup update allowed'; exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a4',true);
do $$ begin
 perform public.join_open_meetup((select value from meetup_state where key='single'));
 if (select count(*) from public.open_meetup_registrations)<>1 then raise exception 'student can read other registrations'; end if;
end $$;

-- Capacity is enforced.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a5',true);
do $$ begin
 begin perform public.join_open_meetup((select value from meetup_state where key='single')); raise exception 'capacity exceeded'; exception when sqlstate 'PGRST' then if sqlerrm not like '%MEETUP_FULL%' then raise; end if; end;
end $$;

-- College eligibility: partner student sees and joins only the all-colleges meetup.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a6',true);
do $$ begin
 if exists(select 1 from public.open_meetup_feed where id=(select value from meetup_state where key='single')) then raise exception 'ineligible student sees single-college meetup'; end if;
 begin perform public.join_open_meetup((select value from meetup_state where key='single')); raise exception 'ineligible student joined'; exception when sqlstate 'PGRST' then null; end;
 perform public.join_open_meetup((select value from meetup_state where key='open'));
end $$;

-- A student with no administrator-granted college membership cannot join an all-colleges meetup.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a7',true);
do $$ begin
 begin perform public.join_open_meetup((select value from meetup_state where key='open')); raise exception 'unaffiliated student joined'; exception when sqlstate 'PGRST' then null; end;
end $$;

-- Cancelling frees a spot for the next student.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a3',true);
do $$ declare result jsonb; begin
 result:=public.leave_open_meetup((select value from meetup_state where key='single'));
 if result->>'status'<>'cancelled' or (result->>'going_count')::int<>1 then raise exception 'leave failed'; end if;
 result:=public.leave_open_meetup((select value from meetup_state where key='single'));
 if (result->>'idempotent_replay')::boolean is not true then raise exception 'leave not idempotent'; end if;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a5',true);
select public.join_open_meetup((select value from meetup_state where key='single'));

-- Students cannot cancel someone else's meetup; revoking recognition removes the badge and hosting rights.
do $$ begin
 begin perform public.set_open_meetup_status((select value from meetup_state where key='single'),'cancelled'); raise exception 'student cancelled meetup'; exception when sqlstate 'PGRST' then null; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a1',true);
select public.revoke_meetup_host('10000000-0000-0000-0000-0000000000a2');
do $$ begin
 if (select host_verified from public.open_meetup_feed where id=(select value from meetup_state where key='single')) then raise exception 'revoked host still verified'; end if;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a2',true);
do $$ begin
 begin perform public.create_open_meetup(gen_random_uuid(),'10000000-0000-0000-0000-0000000000a2','22000000-0000-0000-0000-0000000000a1','Revoked','Revoked hosts cannot create',now()+interval '1 day',now()+interval '1 day 1 hour',5); raise exception 'revoked host created meetup'; exception when sqlstate 'PGRST' then null; end;
end $$;

-- College administrator cancellation releases every spot.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a1',true);
select public.set_open_meetup_status((select value from meetup_state where key='single'),'cancelled');

-- Cancelled meetups reject joins; leaving and re-joining restores the count exactly once.
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a4',true);
do $$ declare result jsonb; open_meetup uuid:=(select value from meetup_state where key='open'); begin
 begin perform public.join_open_meetup((select value from meetup_state where key='single')); raise exception 'joined cancelled meetup'; exception when sqlstate 'PGRST' then if sqlerrm not like '%MEETUP_UNAVAILABLE%' then raise; end if; end;
 perform public.join_open_meetup(open_meetup);
 perform public.leave_open_meetup(open_meetup);
 result:=public.join_open_meetup(open_meetup);
 if (result->>'going_count')::int<>2 or (select count(*) from public.open_meetup_registrations where meetup_id=open_meetup)<>1 then raise exception 'rejoin miscounted'; end if;
 result:=public.leave_open_meetup(open_meetup);
 if (result->>'going_count')::int<>1 then raise exception 'second leave miscounted'; end if;
end $$;

-- Ended meetups reject joins.
reset role;
update public.open_meetups set starts_at=now()-interval '2 hours',ends_at=now()-interval '1 hour' where id=(select value from meetup_state where key='open');
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-0000000000a5',true);
do $$ begin
 begin perform public.join_open_meetup((select value from meetup_state where key='open')); raise exception 'joined ended meetup'; exception when sqlstate 'PGRST' then if sqlerrm not like '%MEETUP_ENDED%' then raise; end if; end;
end $$;
reset role;
do $$ begin
 if (select going_count from public.open_meetups where id=(select value from meetup_state where key='single'))<>0
   or exists(select 1 from public.open_meetup_registrations where meetup_id=(select value from meetup_state where key='single') and status='going') then raise exception 'cancellation kept spots'; end if;
 -- Account deletion releases the spot on the remaining meetup.
 update public.profiles set status='deleted' where id='10000000-0000-0000-0000-0000000000a6';
 if (select going_count from public.open_meetups where id=(select value from meetup_state where key='open'))<>0 then raise exception 'deleted account kept spot'; end if;
end $$;

select 'open meetups integration passed' as result;
rollback;
