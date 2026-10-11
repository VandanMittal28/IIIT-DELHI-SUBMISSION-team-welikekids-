\set ON_ERROR_STOP on
begin;

insert into auth.users(id,email) values
('10000000-0000-0000-0000-000000000001','admin@example.invalid'),
('10000000-0000-0000-0000-000000000002','organizer@example.invalid'),
('10000000-0000-0000-0000-000000000003','student@example.invalid'),
('10000000-0000-0000-0000-000000000004','volunteer@example.invalid');
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
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
do $$ declare result jsonb; begin
 result:=public.register_for_event((select value from test_state where key='edition'),'40000000-0000-0000-0000-000000000002');
 if result->>'status'<>'registered' or result->>'pass_token' is null then raise exception 'registration/pass failed'; end if;
 insert into test_state values('pass',(result->>'pass_token')::uuid),('registration',(result->>'registration_id')::uuid);
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select public.assign_event_staff((select value from test_state where key='edition'),'10000000-0000-0000-0000-000000000004','event_volunteer');
select public.update_edition_capacity((select value from test_state where key='edition'),1,true,true);

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
do $$ declare first jsonb; replay jsonb; begin
 first:=public.record_attendance((select value from test_state where key='pass'),'enter','40000000-0000-0000-0000-000000000003');
 replay:=public.record_attendance((select value from test_state where key='pass'),'enter','40000000-0000-0000-0000-000000000003');
 if (first->>'estimated_inside')::integer<>1 or (replay->>'idempotent_replay')::boolean<>true then raise exception 'scan idempotency failed'; end if;
 perform public.record_attendance((select value from test_state where key='pass'),'exit','40000000-0000-0000-0000-000000000004');
 perform public.record_attendance((select value from test_state where key='pass'),'reenter','40000000-0000-0000-0000-000000000005');
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000003',true);
do $$ declare report_result jsonb; review_result jsonb; begin
 report_result:=public.submit_report((select value from test_state where key='edition'),'Safety','Local integration report','normal');
 insert into test_state values('report',(report_result->>'report_id')::uuid);
 review_result:=public.submit_review((select value from test_state where key='edition'),5,'Verified local attendance review');
 if (review_result->>'persisted')::boolean<>true then raise exception 'review failed'; end if;
end $$;

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000004',true);
select public.transition_report((select value from test_state where key='report'),'acknowledged',null,'seen');
select public.transition_report((select value from test_state where key='report'),'in_progress',null,'working');
select public.transition_report((select value from test_state where key='report'),'resolved',null,'done');

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
do $$ declare campus uuid; start_landmark uuid; finish_landmark uuid; route_version uuid; start_node uuid; finish_node uuid; edge uuid; plan jsonb; begin
 campus:=(public.create_campus('20000000-0000-0000-0000-000000000001','Test Campus',28.545,77.273)->>'campus_id')::uuid;
 start_landmark:=(public.create_landmark(campus,'Gate','outdoor_geographic',28.545,77.273,null,null,null,90,'Face east',null)->>'landmark_id')::uuid;
 finish_landmark:=(public.create_landmark(campus,'Hall','outdoor_geographic',28.546,77.274,null,null,null,90,'Face east',null)->>'landmark_id')::uuid;
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
 raise notice 'operational integration passed';
end $$;

rollback;
