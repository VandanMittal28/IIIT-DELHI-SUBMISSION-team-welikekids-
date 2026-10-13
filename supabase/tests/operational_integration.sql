\set ON_ERROR_STOP on
begin;

insert into auth.users(id,email) values
('10000000-0000-0000-0000-000000000001','admin@example.invalid'),
('10000000-0000-0000-0000-000000000002','organizer@example.invalid'),
('10000000-0000-0000-0000-000000000003','student@example.invalid'),
('10000000-0000-0000-0000-000000000004','volunteer@example.invalid'),
('10000000-0000-0000-0000-000000000005','outsider@example.invalid'),
('10000000-0000-0000-0000-000000000006','cohost@example.invalid');
insert into public.colleges(id,slug,name) values
('20000000-0000-0000-0000-000000000001','test-college','Test College'),
('20000000-0000-0000-0000-000000000002','other-college','Other College');
insert into public.college_memberships(college_id,user_id,is_admin,status) values('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',true,'active');
insert into public.organizations(id,college_id,slug,name) values
('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','test-org','Test Org'),
('30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000001','cohost-org','Cohost Org');
insert into public.memberships(organization_id,user_id,role,status) values
('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002','organizer','active'),
('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000006','organizer','active');
insert into public.campuses(id,college_id,name,latitude,longitude) values('21000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','Other Campus',28.6,77.3);
insert into public.venues(id,campus_id,name,kind) values('22000000-0000-0000-0000-000000000002','21000000-0000-0000-0000-000000000002','Other Hall','hall');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claim.role','authenticated',true);
create temporary table test_state(key text primary key,value uuid);
do $$ declare result jsonb; begin
 result:=public.create_event('40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','Integration event','A real local integration workflow','Workshop','public',0,'INR',null,now()-interval '1 hour',now()+interval '1 hour',now()+interval '2 hours',now()+interval '4 hours',1,true);
 insert into test_state values('event',(result->>'event_id')::uuid),('edition',(result->>'edition_id')::uuid);
 perform public.publish_event((result->>'event_id')::uuid);
 if (select count(*) from public.channels where edition_id=(result->>'edition_id')::uuid)<>1 then raise exception 'edition channel missing'; end if;
 result:=public.post_message((select id from public.channels where edition_id=(select value from test_state where key='edition')),'Organizer-authored discussion message');
 insert into test_state values('message',(result->>'message_id')::uuid);
 perform public.update_event_details((select value from test_state where key='event'),'Integration event updated','A real local integration workflow','Workshop','Students',2500);
 perform public.set_event_cover_image((select value from test_state where key='event'),'20000000-0000-0000-0000-000000000001/'||(select value from test_state where key='event')::text||'/cover.webp');
 perform public.create_event_edition((select value from test_state where key='event'),'Next edition',now()+interval '5 days',now()+interval '6 days',now()+interval '7 days',now()+interval '8 days',10,true);
 perform public.add_event_cohost((select value from test_state where key='event'),'30000000-0000-0000-0000-000000000002');
 result:=public.create_role_invitation('30000000-0000-0000-0000-000000000001','volunteer@example.invalid','event_volunteer');
 insert into test_state values('invitation',(result->>'invitation_token')::uuid);
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000006',true);
do $$ begin
 if (select count(*) from public.get_event_staff_candidates((select value from test_state where key='edition')))<>2 then raise exception 'cohost organizer management access failed'; end if;
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
do $$ declare result jsonb; own_message jsonb; begin
 result:=public.register_for_event((select value from test_state where key='edition'),'40000000-0000-0000-0000-000000000002');
 if result->>'status'<>'registered' or result->>'pass_token' is null then raise exception 'registration/pass failed'; end if;
 insert into test_state values('pass',(result->>'pass_token')::uuid),('registration',(result->>'registration_id')::uuid);
 begin perform public.assign_context_role('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000003','organizer'); raise exception 'student granted staff role'; exception when sqlstate 'PGRST' then null; end;
 begin perform public.create_campus('20000000-0000-0000-0000-000000000001','Forbidden Campus',28.5,77.2); raise exception 'student authored campus'; exception when sqlstate 'PGRST' then null; end;
 begin perform public.get_assignable_event_staff((select value from test_state where key='edition')); raise exception 'student read assignable staff'; exception when sqlstate 'PGRST' then null; end;
 own_message:=public.post_message((select id from public.channels where edition_id=(select value from test_state where key='edition')),'Student-authored discussion message');
 begin perform public.submit_message_report((own_message->>'message_id')::uuid,'Self report should be denied'); raise exception 'student reported own message'; exception when sqlstate 'PGRST' then null; end;
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select public.accept_role_invitation((select value from test_state where key='invitation'));
do $$ begin if not exists(select 1 from public.memberships where organization_id='30000000-0000-0000-0000-000000000001' and user_id='10000000-0000-0000-0000-000000000004' and role='event_volunteer' and status='active') then raise exception 'invitation acceptance failed'; end if; end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
do $$ declare assigned jsonb; replay jsonb; begin
 if (select count(*) from public.get_event_staff_candidates((select value from test_state where key='edition')))<>3 then raise exception 'staff candidate directory incorrect'; end if;
 begin perform public.assign_event_staff((select value from test_state where key='edition'),'10000000-0000-0000-0000-000000000005','event_volunteer'); raise exception 'non-member assigned as staff'; exception when sqlstate 'PGRST' then null; end;
 assigned:=public.assign_event_staff((select value from test_state where key='edition'),'10000000-0000-0000-0000-000000000004','event_volunteer');
 replay:=public.assign_event_staff((select value from test_state where key='edition'),'10000000-0000-0000-0000-000000000004','event_volunteer');
 if (assigned->>'idempotent_replay')::boolean or not (replay->>'idempotent_replay')::boolean then raise exception 'staff assignment idempotency failed'; end if;
 if (select count(*) from public.audit_records where action='staff.assign' and entity_id=(select value from test_state where key='edition'))<>1 then raise exception 'staff assignment audit duplicated'; end if;
end $$;
select public.update_edition_capacity((select value from test_state where key='edition'),1,true,true);
do $$ begin
 if (select count(*) from public.get_registration_roster((select value from test_state where key='edition')))<>1 then raise exception 'roster incorrect'; end if;
 if (select count(*) from public.get_assignable_event_staff((select value from test_state where key='edition')))<>1 then raise exception 'assignable staff directory incorrect'; end if;
end $$;
do $$ declare first jsonb; replay jsonb; request_id uuid:='40000000-0000-0000-0000-000000000011'; begin
 first:=public.publish_announcement((select value from test_state where key='edition'),'Integration update','Stored announcement body','official',request_id);
 replay:=public.publish_announcement((select value from test_state where key='edition'),'Integration update','Stored announcement body','official',request_id);
 if (first->>'idempotent_replay')::boolean or not (replay->>'idempotent_replay')::boolean or first->>'announcement_id'<>replay->>'announcement_id' then raise exception 'announcement idempotency failed'; end if;
 if (select count(*) from public.notifications where title='Integration update')<>1 then raise exception 'announcement notification duplicated'; end if;
end $$;

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
do $$ declare report_result jsonb; review_result jsonb; message_report jsonb; message_report_replay jsonb; begin
 report_result:=public.submit_report((select value from test_state where key='edition'),'Safety','Local integration report','normal');
 insert into test_state values('report',(report_result->>'report_id')::uuid);
 message_report:=public.submit_message_report((select value from test_state where key='message'),'This message needs moderator review');
 message_report_replay:=public.submit_message_report((select value from test_state where key='message'),'This message needs moderator review');
 if (message_report->>'idempotent_replay')::boolean or not (message_report_replay->>'idempotent_replay')::boolean or message_report->>'report_id'<>message_report_replay->>'report_id' then raise exception 'message report idempotency failed'; end if;
 insert into test_state values('message_report',(message_report->>'report_id')::uuid);
 review_result:=public.submit_review((select value from test_state where key='edition'),5,'Verified local attendance review');
 if (review_result->>'persisted')::boolean<>true then raise exception 'review failed'; end if;
 perform public.register_device_token('integration-device-token','sandbox');
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
do $$ declare first jsonb; replay jsonb; begin
 first:=public.transition_report((select value from test_state where key='report'),'acknowledged',null,'seen');
 replay:=public.transition_report((select value from test_state where key='report'),'acknowledged',null,'seen');
 if (first->>'idempotent_replay')::boolean or not (replay->>'idempotent_replay')::boolean then raise exception 'report transition idempotency failed'; end if;
 begin perform public.transition_report((select value from test_state where key='report'),'in_progress',null,'skipped assignment'); raise exception 'report assignment state skipped'; exception when sqlstate 'PGRST' then null; end;
 begin perform public.transition_report((select value from test_state where key='report'),'assigned',null,'missing assignee'); raise exception 'null report assignee accepted'; exception when sqlstate 'PGRST' then null; end;
 begin perform public.transition_report((select value from test_state where key='report'),'assigned','10000000-0000-0000-0000-000000000006','unassigned candidate'); raise exception 'unassigned report candidate accepted'; exception when sqlstate 'PGRST' then null; end;
 perform public.transition_report((select value from test_state where key='report'),'assigned','10000000-0000-0000-0000-000000000004','assigned');
 perform public.transition_report((select value from test_state where key='report'),'in_progress',null,'working');
 perform public.transition_report((select value from test_state where key='report'),'resolved',null,'done');
end $$;
select public.moderate_message((select value from test_state where key='message'),'hidden');
do $$ begin
 begin perform public.submit_message_report((select value from test_state where key='message'),'Hidden message should be unavailable'); raise exception 'new hidden message report accepted'; exception when sqlstate 'PGRST' then null; end;
end $$;

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
 if exists(select 1 from public.my_attendance_history) or exists(select 1 from public.my_submitted_reviews) then raise exception 'outsider read student profile history'; end if;
 begin perform public.add_report_attachment((select value from test_state where key='report'),'10000000-0000-0000-0000-000000000003/'||(select value from test_state where key='report')::text||'/evidence.webp'); raise exception 'outsider linked report evidence'; exception when sqlstate 'PGRST' then null; end;
 begin perform public.submit_message_report((select value from test_state where key='message'),'Outsider should be denied'); raise exception 'outsider reported inaccessible message'; exception when sqlstate 'PGRST' then null; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
do $$ begin
 if (select count(*) from storage.objects where bucket_id='report-attachments')<>1 then raise exception 'reporter could not read own evidence'; end if;
 if (select count(*) from public.my_attendance_history)<>3 then raise exception 'student attendance history incorrect'; end if;
 if (select count(*) from public.my_submitted_reviews)<>1 then raise exception 'student review history incorrect'; end if;
 if exists(select 1 from public.messages where id=(select value from test_state where key='message')) then raise exception 'student read hidden message'; end if;
 if not (public.submit_message_report((select value from test_state where key='message'),'Retry after moderation')->>'idempotent_replay')::boolean then raise exception 'hidden message report retry was not idempotent'; end if;
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
do $$ declare campus uuid; start_landmark uuid; finish_landmark uuid; route_version uuid; start_node uuid; finish_node uuid; edge uuid; venue uuid; session_id uuid; plan jsonb; closure_result jsonb; closure_replay jsonb; reopen_result jsonb; reopen_replay jsonb; venue_result jsonb; venue_replay jsonb; closure_request uuid:='40000000-0000-0000-0000-000000000010'; venue_request uuid:='40000000-0000-0000-0000-000000000012'; begin
 campus:=(public.create_campus('20000000-0000-0000-0000-000000000001','Test Campus',28.545,77.273)->>'campus_id')::uuid;
 start_landmark:=(public.create_landmark(campus,'Gate','outdoor_geographic',28.545,77.273,null,null,null,90,'Face east',null)->>'landmark_id')::uuid;
 finish_landmark:=(public.create_landmark(campus,'Hall','outdoor_geographic',28.546,77.274,null,null,null,90,'Face east',null)->>'landmark_id')::uuid;
 perform public.update_landmark(finish_landmark,'Main Hall',28.546,77.274,null,null,null,95,'Face the main doors');
 if not exists(select 1 from public.landmarks where id=finish_landmark and name='Main Hall' and facing_degrees=95) then raise exception 'landmark editing failed'; end if;
 venue:=(public.create_venue(campus,'Test Hall','hall',null,null,'Step-free entrance')->>'venue_id')::uuid;
 perform public.set_venue_navigation(venue,finish_landmark,start_landmark);
 session_id:=(public.create_event_session((select value from test_state where key='edition'),venue,'Main session',now()+interval '2 hours',now()+interval '3 hours')->>'session_id')::uuid;
 perform public.update_event_session(session_id,'Opening session',venue,now()+interval '2 hours 5 minutes',now()+interval '3 hours 5 minutes');
 if not exists(select 1 from public.event_sessions where id=session_id and title='Opening session') then raise exception 'session editing failed'; end if;
 begin perform public.change_session_venue(session_id,'22000000-0000-0000-0000-000000000002','Cross-college venue must fail','40000000-0000-0000-0000-000000000013'); raise exception 'cross-college venue accepted'; exception when sqlstate 'PGRST' then null; end;
 venue_result:=public.change_session_venue(session_id,venue,'Navigation contract test',venue_request);
 venue_replay:=public.change_session_venue(session_id,venue,'Navigation contract test',venue_request);
 if (venue_result->>'idempotent_replay')::boolean or not (venue_replay->>'idempotent_replay')::boolean then raise exception 'venue change idempotency failed'; end if;
 if (select destination_landmark_id from public.published_event_feed where id=(select value from test_state where key='event'))<>finish_landmark then raise exception 'published venue navigation missing'; end if;
 route_version:=(public.create_route_draft(campus)->>'route_version_id')::uuid;
 start_node:=(public.add_route_node(route_version,'landmark','outdoor_geographic',start_landmark,28.545,77.273,null,null,null,true)->>'node_id')::uuid;
 finish_node:=(public.add_route_node(route_version,'landmark','outdoor_geographic',finish_landmark,28.546,77.274,null,null,null,true)->>'node_id')::uuid;
 edge:=(public.add_route_edge(route_version,start_node,finish_node,'walkway',150,'[]','Walk toward Hall',true,true)->>'edge_id')::uuid;
 perform set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
 begin perform public.update_route_edge(edge,'walkway',160,'[]','Follow the main walkway',true,true); raise exception 'student edited route edge'; exception when sqlstate 'PGRST' then null; end;
 perform set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
 perform public.update_route_edge(edge,'walkway',160,'[]','Follow the main walkway',true,true);
 perform public.publish_route_version(route_version,'Local graph test',false);
 plan:=public.calculate_route(start_landmark,finish_landmark,true);
 if (plan->>'total_distance_meters')::numeric<>160 or jsonb_array_length(plan->'edges')<>1 then raise exception 'route calculation failed'; end if;
 closure_result:=public.add_route_closure(edge,'Local test closure',now()-interval '1 minute',now()+interval '4 hours',closure_request);
 closure_replay:=public.add_route_closure(edge,'Local test closure',now()-interval '1 minute',now()+interval '4 hours',closure_request);
 if (closure_result->>'notified_attendees')::integer<>1 or (closure_replay->>'idempotent_replay')::boolean<>true or closure_result->>'closure_id'<>closure_replay->>'closure_id' then raise exception 'closure notification/idempotency failed'; end if;
 begin perform public.calculate_route(start_landmark,finish_landmark,true); raise exception 'closure did not block route'; exception when sqlstate 'PGRST' then null; end;
 perform set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
 begin perform public.end_route_closure((closure_result->>'closure_id')::uuid); raise exception 'student reopened route'; exception when sqlstate 'PGRST' then null; end;
 perform set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
 reopen_result:=public.end_route_closure((closure_result->>'closure_id')::uuid);
 reopen_replay:=public.end_route_closure((closure_result->>'closure_id')::uuid);
 if (reopen_result->>'notified_attendees')::integer<>1 or (reopen_replay->>'idempotent_replay')::boolean<>true then raise exception 'route reopening notification/idempotency failed'; end if;
 plan:=public.calculate_route(start_landmark,finish_landmark,true);
 if jsonb_array_length(plan->'edges')<>1 then raise exception 'reopened route unavailable'; end if;
 update public.profiles set status='suspended' where id='10000000-0000-0000-0000-000000000001';
 begin perform public.update_landmark(finish_landmark,'Suspended edit',28.546,77.274,null,null,null,95,'Face the main doors'); raise exception 'suspended administrator retained write access'; exception when sqlstate 'PGRST' then null; end;
 update public.profiles set status='active' where id='10000000-0000-0000-0000-000000000001';
end $$;

do $$ begin
 if (select estimated_inside from public.edition_occupancy where edition_id=(select value from test_state where key='edition'))<>1 then raise exception 'occupancy incorrect'; end if;
 if (select status::text from public.reports where id=(select value from test_state where key='report'))<>'resolved' then raise exception 'report workflow incomplete'; end if;
 if (select count(*) from public.report_status_history where report_id=(select value from test_state where key='report'))<>5 then raise exception 'report history duplicated or incomplete'; end if;
 if (select count(*) from public.notifications where title='Report updated')<>4 then raise exception 'report transition notification count incorrect'; end if;
 if (select count(*) from public.reports where reporter_id='10000000-0000-0000-0000-000000000003' and reported_message_id=(select value from test_state where key='message'))<>1 then raise exception 'message report linkage incorrect'; end if;
 if (select status::text from public.messages where id=(select value from test_state where key='message'))<>'hidden' then raise exception 'message moderation failed'; end if;
 if (select sample_size from public.event_review_summary where event_id=(select value from test_state where key='event'))<>1 then raise exception 'review analytics incorrect'; end if;
 if (select sample_size from public.edition_review_summary where edition_id=(select value from test_state where key='edition'))<>1 then raise exception 'edition review analytics incorrect'; end if;
 if (select count(*) from public.published_event_session_schedule where edition_id=(select value from test_state where key='edition'))<>1 then raise exception 'published session schedule incorrect'; end if;
 if (select count(*) from public.notifications where title='Campus route changed')<>1 then raise exception 'closure notification missing or duplicated'; end if;
 if (select count(*) from public.notifications where title='Campus route reopened')<>1 then raise exception 'reopening notification missing or duplicated'; end if;
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
 if (select count(*) from public.notifications where kind='venue_change' and title='Venue changed')<>1 then raise exception 'venue change notification kind incorrect'; end if;
 if (select count(*) from public.notification_reminders where reminder_kind='event_starting')<>1 then raise exception 'event-start reminder was not idempotent'; end if;
 if (select count(*) from public.notification_reminders where reminder_kind='registration_closing')<>1 then raise exception 'registration deadline reminder missing'; end if;
 if (select sum((result->>'enqueued')::integer) from reminder_runs)<>2 then raise exception 'event reminder enqueue result incorrect'; end if;
 if (select count(*) from public.notifications where kind='reminder')<>2 then raise exception 'event reminder inbox entry missing'; end if;
 if exists(select 1 from public.notification_delivery_jobs job join public.notifications notification on notification.id=job.notification_id where notification.kind='reminder') then raise exception 'disabled reminder push was queued'; end if;
 raise notice 'operational integration passed';
end $$;

reset role;
update public.profiles set status='suspended' where id='10000000-0000-0000-0000-000000000003';
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
do $$ begin
 if exists(select 1 from public.channels where edition_id=(select value from test_state where key='edition')) then raise exception 'suspended account retained edition access'; end if;
end $$;
reset role;
update public.profiles set status='active' where id='10000000-0000-0000-0000-000000000003';
set role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000005',true);
do $$ declare result jsonb; begin
 result:=public.register_for_event((select value from test_state where key='edition'),'40000000-0000-0000-0000-000000000013');
 if result->>'status'<>'waitlisted' then raise exception 'event cancellation fixture was not waitlisted'; end if;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
do $$ declare first jsonb; replay jsonb; begin
 first:=public.cancel_event((select value from test_state where key='event'),'Integration cancellation');
 replay:=public.cancel_event((select value from test_state where key='event'),'Integration cancellation');
 if (first->>'idempotent_replay')::boolean or not (replay->>'idempotent_replay')::boolean then raise exception 'event cancellation idempotency failed'; end if;
 if (first->>'cancelled_registrations')::integer<>2 then raise exception 'event registrations were not all cancelled'; end if;
 if not exists(select 1 from public.events where id=(select value from test_state where key='event') and status='cancelled' and cancelled_at is not null) then raise exception 'event cancellation state incomplete'; end if;
 if exists(
   select 1 from public.registrations registration
   join public.event_editions edition on edition.id=registration.edition_id
   where edition.event_id=(select value from test_state where key='event')
     and (registration.status<>'cancelled' or registration.cancelled_at is null)
 ) then raise exception 'event cancellation left an enrolment active'; end if;
 if exists(
   select 1 from public.waitlist_entries waitlist
   join public.event_editions edition on edition.id=waitlist.edition_id
   where edition.event_id=(select value from test_state where key='event') and waitlist.status='waiting'
 ) then raise exception 'event cancellation left a waitlist entry active'; end if;
 if exists(
   select 1 from public.passes pass
   join public.registrations registration on registration.id=pass.registration_id
   join public.event_editions edition on edition.id=registration.edition_id
   where edition.event_id=(select value from test_state where key='event') and pass.status='active'
 ) then raise exception 'event cancellation left an attendee pass active'; end if;
 perform set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
 if (select count(*) from public.notifications where title='Event cancelled')<>1 then raise exception 'confirmed attendee cancellation notification missing or duplicated'; end if;
 perform set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000005',true);
 if (select count(*) from public.notifications where title='Event cancelled')<>1 then raise exception 'waitlisted attendee cancellation notification missing or duplicated'; end if;
 perform set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
 begin
   perform public.register_for_event((select value from test_state where key='edition'),'40000000-0000-0000-0000-000000000014');
   raise exception 'registration after event cancellation was accepted';
 exception when sqlstate 'PGRST' then null;
 end;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.audit_records where action='event.cancel' and entity_id=(select value from test_state where key='event'))<>1 then raise exception 'cancellation audit duplicated'; end if;
end $$;

rollback;
