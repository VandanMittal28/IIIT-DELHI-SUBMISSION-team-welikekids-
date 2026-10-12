\set ON_ERROR_STOP on
begin;

insert into auth.users(id,email) values
('10000000-0000-0000-0000-000000000001','admin@example.invalid'),
('10000000-0000-0000-0000-000000000002','organizer@example.invalid'),
('10000000-0000-0000-0000-000000000003','student@example.invalid'),
('10000000-0000-0000-0000-000000000004','volunteer@example.invalid'),
('10000000-0000-0000-0000-000000000005','outsider@example.invalid');
insert into public.colleges(id,slug,name) values('20000000-0000-0000-0000-000000000001','test-college','Test College');
insert into public.college_memberships(college_id,user_id,is_admin,status) values('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',true,'active');
insert into public.organizations(id,college_id,slug,name) values('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','test-org','Test Org');
insert into public.memberships(organization_id,user_id,role,status) values('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','organizer','active');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claim.role','authenticated',true);
create temporary table test_state(key text primary key,value uuid);
do $$ declare result jsonb; begin
 result:=public.create_event('40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Integration event','A real local integration workflow','Workshop','public',0,'INR',null,now()-interval '1 hour',now()+interval '1 hour',now()+interval '2 hours',now()+interval '4 hours',1,true);
 insert into test_state values('event',(result->>'event_id')::uuid),('edition',(result->>'edition_id')::uuid);
 perform public.publish_event((result->>'event_id')::uuid);
 if (select count(*) from public.channels where edition_id=(result->>'edition_id')::uuid)<>1 then raise exception 'edition channel missing'; end if;
 perform public.update_event_details((result->>'event_id')::uuid,'Integration event updated','A real local integration workflow','Workshop','Students',2500);
 perform public.set_event_cover_image((result->>'event_id')::uuid,'20000000-0000-0000-0000-000000000001/'||(result->>'event_id')||'/cover.webp');
 perform public.create_event_edition((result->>'event_id')::uuid,'Next edition',now()+interval '5 days',now()+interval '6 days',now()+interval '7 days',now()+interval '8 days',10,true);
 result:=public.create_role_invitation('30000000-0000-0000-0000-000000000001','volunteer@example.invalid','event_volunteer');
 insert into test_state values('invitation',(result->>'invitation_token')::uuid);
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
do $$ declare result jsonb; begin
 result:=public.register_for_event((select value from test_state where key='edition'),'40000000-0000-0000-0000-000000000002');
 if result->>'status'<>'registered' or result->>'pass_token' is null then raise exception 'registration/pass failed'; end if;
 insert into test_state values('pass',(result->>'pass_token')::uuid),('registration',(result->>'registration_id')::uuid);
 begin perform public.assign_context_role('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','organizer'); raise exception 'student granted staff role'; exception when sqlstate 'PGRST' then null; end;
 begin perform public.create_campus('20000000-0000-0000-0000-000000000001','Forbidden Campus',28.5,77.2); raise exception 'student authored campus'; exception when sqlstate 'PGRST' then null; end;
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select public.accept_role_invitation((select value from test_state where key='invitation'));
do $$ begin if not exists(select 1 from public.memberships where organization_id='30000000-0000-0000-0000-000000000001' and user_id='10000000-0000-0000-0000-000000000004' and role='event_volunteer' and status='active') then raise exception 'invitation acceptance failed'; end if; end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select public.assign_event_staff((select value from test_state where key='edition'),'10000000-0000-0000-0000-000000000004','event_volunteer');
select public.update_edition_capacity((select value from test_state where key='edition'),1,true,true);
do $$ begin if (select count(*) from public.get_registration_roster((select value from test_state where key='edition')))<>1 then raise exception 'roster incorrect'; end if; end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
do $$ declare first jsonb; replay jsonb; begin
 first:=public.record_attendance((select value from test_state where key='pass'),'enter','40000000-0000-0000-0000-000000000003');
 replay:=public.record_attendance((select value from test_state where key='pass'),'enter','40000000-0000-0000-0000-000000000003');
 if (first->>'estimated_inside')::integer<>1 or (replay->>'idempotent_replay')::boolean<>true then raise exception 'scan idempotency failed'; end if;
 begin perform public.record_attendance((select value from test_state where key='pass'),'enter','40000000-0000-0000-0000-000000000009'); raise exception 'duplicate entry accepted'; exception when sqlstate 'PGRST' then null; end;
 perform public.record_attendance((select value from test_state where key='pass'),'exit','40000000-0000-0000-0000-000000000004');
 perform public.record_attendance((select value from test_state where key='pass'),'reenter','40000000-0000-0000-0000-000000000005');
 perform public.correct_occupancy((select value from test_state where key='edition'),1,'Manual gate count reconciliation');
 perform public.correct_occupancy((select value from test_state where key='edition'),-1,'Reversal of test correction');
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
do $$ declare report_result jsonb; review_result jsonb; begin
 report_result:=public.submit_report((select value from test_state where key='edition'),'Safety','Local integration report','normal');
 insert into test_state values('report',(report_result->>'report_id')::uuid);
 review_result:=public.submit_review((select value from test_state where key='edition'),5,'Verified local attendance review');
 if (review_result->>'persisted')::boolean<>true then raise exception 'review failed'; end if;
 perform public.register_device_token('integration-device-token','sandbox');
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select public.transition_report((select value from test_state where key='report'),'acknowledged',null,'seen');
select public.transition_report((select value from test_state where key='report'),'assigned','10000000-0000-0000-0000-000000000004','assigned');
select public.transition_report((select value from test_state where key='report'),'in_progress',null,'working');
select public.transition_report((select value from test_state where key='report'),'resolved',null,'done');

reset role;
insert into storage.objects(bucket_id,name,owner_id) values
('event-media','20000000-0000-0000-0000-000000000001/'||(select value from test_state where key='event')::text||'/cover.webp','10000000-0000-0000-0000-000000000002'),
('report-attachments','10000000-0000-0000-0000-000000000003/'||(select value from test_state where key='report')::text||'/evidence.webp','10000000-0000-0000-0000-000000000003');
grant select on storage.objects to anon,authenticated;
grant usage on schema storage to anon,authenticated;
grant select on test_state to authenticated;

set role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
select public.add_report_attachment(
  (select value from test_state where key='report'),
  '10000000-0000-0000-0000-000000000003/'||(select value from test_state where key='report')::text||'/evidence.webp'
);
select public.add_report_attachment(
  (select value from test_state where key='report'),
  '10000000-0000-0000-0000-000000000003/'||(select value from test_state where key='report')::text||'/evidence.webp'
);
reset role;
do $$ begin
 if (select count(*) from public.report_attachments where report_id=(select value from test_state where key='report'))<>1 then raise exception 'duplicate attachment link created'; end if;
 if (select count(*) from public.audit_records where action='report.attachment' and detail->>'report_id'=(select value from test_state where key='report')::text)<>1 then raise exception 'duplicate attachment audit created'; end if;
end $$;
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000005',true);
do $$ begin
 if exists(select 1 from storage.objects where bucket_id='report-attachments') then raise exception 'unrelated user read report evidence'; end if;
 begin perform public.add_report_attachment((select value from test_state where key='report'),'10000000-0000-0000-0000-000000000003/'||(select value from test_state where key='report')::text||'/evidence.webp'); raise exception 'outsider linked report evidence'; exception when sqlstate 'PGRST' then null; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
do $$ begin
 if (select count(*) from storage.objects where bucket_id='report-attachments')<>1 then raise exception 'reporter could not read own evidence'; end if;
end $$;
reset role;
set role anon;
select set_config('request.jwt.claim.role','anon',true);
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 if (select count(*) from storage.objects where bucket_id='event-media')<>1 then raise exception 'published event image unavailable'; end if;
 if exists(select 1 from storage.objects where bucket_id='report-attachments') then raise exception 'anonymous report evidence read'; end if;
end $$;
reset role;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claim.role','authenticated',true);
do $$ declare campus uuid; start_landmark uuid; finish_landmark uuid; route_version uuid; start_node uuid; finish_node uuid; edge uuid; venue uuid; session_id uuid; plan jsonb; begin
 campus:=(public.create_campus('20000000-0000-0000-0000-000000000001','Test Campus',28.545,77.273)->>'campus_id')::uuid;
 start_landmark:=(public.create_landmark(campus,'Gate','outdoor_geographic',28.545,77.273,null,null,null,90,'Face east',null)->>'landmark_id')::uuid;
 finish_landmark:=(public.create_landmark(campus,'Hall','outdoor_geographic',28.546,77.274,null,null,null,90,'Face east',null)->>'landmark_id')::uuid;
 venue:=(public.create_venue(campus,'Test Hall','hall',null,null,'Step-free entrance')->>'venue_id')::uuid;
 perform public.set_venue_navigation(venue,finish_landmark,start_landmark);
 session_id:=(public.create_event_session((select value from test_state where key='edition'),venue,'Main session',now()+interval '2 hours',now()+interval '3 hours')->>'session_id')::uuid;
 perform public.change_session_venue(session_id,venue,'Navigation contract test');
 if (select destination_landmark_id from public.published_event_feed where id=(select value from test_state where key='event'))<>finish_landmark then raise exception 'published venue navigation missing'; end if;
 route_version:=(public.create_route_draft(campus)->>'route_version_id')::uuid;
 start_node:=(public.add_route_node(route_version,'landmark','outdoor_geographic',start_landmark,28.545,77.273,null,null,null,true)->>'node_id')::uuid;
 finish_node:=(public.add_route_node(route_version,'landmark','outdoor_geographic',finish_landmark,28.546,77.274,null,null,null,true)->>'node_id')::uuid;
 edge:=(public.add_route_edge(route_version,start_node,finish_node,'walkway',150,'[]','Walk toward Hall',true,true)->>'edge_id')::uuid;
 perform public.publish_route_version(route_version,'Local graph test',false);
 plan:=public.calculate_route(start_landmark,finish_landmark,true);
 if (plan->>'total_distance_meters')::numeric<>150 or jsonb_array_length(plan->'edges')<>1 then raise exception 'route calculation failed'; end if;
 perform public.add_route_closure(edge,'Local test closure',now(),now()+interval '1 hour');
 begin perform public.calculate_route(start_landmark,finish_landmark,true); raise exception 'closure did not block route'; exception when sqlstate 'PGRST' then null; end;
end $$;

do $$ begin
 if (select estimated_inside from public.edition_occupancy where edition_id=(select value from test_state where key='edition'))<>1 then raise exception 'occupancy incorrect'; end if;
 if (select status::text from public.reports where id=(select value from test_state where key='report'))<>'resolved' then raise exception 'report workflow incomplete'; end if;
 if (select sample_size from public.event_review_summary where event_id=(select value from test_state where key='event'))<>1 then raise exception 'review analytics incorrect'; end if;
end $$;

set role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
do $$ begin
 begin perform public.claim_notification_jobs(1); raise exception 'client claimed notification jobs'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set role service_role;
select set_config('request.jwt.claim.role','service_role',true);
create temporary table claimed_notification as select * from public.claim_notification_jobs(1);
do $$ begin
 if (select count(*) from claimed_notification)<>1 or (select attempt_number from claimed_notification)<>1 then raise exception 'notification claim failed'; end if;
 if (select device_environment from claimed_notification)<>'sandbox' then raise exception 'notification environment missing'; end if;
end $$;
reset role;
update public.notification_delivery_jobs
set locked_at=clock_timestamp()-interval '10 minutes',next_attempt_at=clock_timestamp()-interval '10 minutes'
where id=(select job_id from claimed_notification);
set role service_role;
select set_config('request.jwt.claim.role','service_role',true);
create temporary table reclaimed_notification as select * from public.claim_notification_jobs(1);
do $$ begin
 if (select job_id from reclaimed_notification)<>(select job_id from claimed_notification) or (select attempt_number from reclaimed_notification)<>2 then raise exception 'expired notification lease was not reclaimed'; end if;
 if (public.complete_notification_job((select job_id from claimed_notification),1,true,false,false,null)->>'stale_attempt')::boolean<>true then raise exception 'stale worker completed reclaimed job'; end if;
 if (public.complete_notification_job((select job_id from reclaimed_notification),2,false,true,true,'410 Unregistered')->>'persisted')::boolean<>true then raise exception 'terminal notification completion failed'; end if;
end $$;
reset role;
do $$ begin
 if exists(select 1 from public.device_tokens where token='integration-device-token' and is_active) then raise exception 'invalid notification token remained active'; end if;
end $$;
update public.device_tokens set is_active=true where token='integration-device-token';
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
select public.update_profile_preferences('Student',null,'{}'::text[],'{"announcements":true,"venue_changes":true,"reminders":false,"reports":true}'::jsonb);
do $$ begin
 begin perform public.update_profile_preferences('Student',null,'{}'::text[],'{"reminders":"yes"}'::jsonb); raise exception 'invalid notification preferences accepted'; exception when sqlstate 'PGRST' then null; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000005',true);
insert into public.saved_events(user_id,event_id) values('10000000-0000-0000-0000-000000000005',(select value from test_state where key='event'));
reset role;
set role service_role;
select set_config('request.jwt.claim.role','service_role',true);
create temporary table reminder_runs(result jsonb);
insert into reminder_runs values(public.enqueue_due_event_reminders(clock_timestamp()));
insert into reminder_runs values(public.enqueue_due_event_reminders(clock_timestamp()));
reset role;
do $$ begin
 if not exists(select 1 from public.notification_delivery_jobs where id=(select job_id from claimed_notification) and status='failed' and terminal_failure and locked_at is null) then raise exception 'terminal notification state incorrect'; end if;
 if (select count(*) from public.notifications where kind='venue_change')<>1 then raise exception 'venue change notification kind incorrect'; end if;
 if (select count(*) from public.notification_reminders where reminder_kind='event_starting')<>1 then raise exception 'event-start reminder was not idempotent'; end if;
 if (select count(*) from public.notification_reminders where reminder_kind='registration_closing')<>1 then raise exception 'registration deadline reminder missing'; end if;
 if (select sum((result->>'enqueued')::integer) from reminder_runs)<>2 then raise exception 'event reminder enqueue result incorrect'; end if;
 if (select count(*) from public.notifications where kind='reminder')<>2 then raise exception 'event reminder inbox entry missing'; end if;
 if exists(select 1 from public.notification_delivery_jobs job join public.notifications notification on notification.id=job.notification_id where notification.kind='reminder') then raise exception 'disabled reminder push was queued'; end if;
 raise notice 'operational integration passed';
end $$;

rollback;
