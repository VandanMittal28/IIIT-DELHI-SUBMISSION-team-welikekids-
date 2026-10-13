-- Development-only IIIT Delhi demo scenario.
-- This file is intentionally deterministic and safe to re-run. Never run it against production.

do $$
#variable_conflict use_variable
declare
  college_id uuid := 'bc3417c0-170e-4663-b235-86efc40cebb2';
  admin_id uuid := '6d6ba29a-5977-4d07-bed3-41818325d67d';
  organizer_id uuid := 'e2e7ea47-1428-45d0-8c8c-2d9a32186b82';
  student_id uuid := '5cfe23f8-c041-4d8b-855c-b2935b9a39d9';
  org_id uuid := '11111111-1111-4111-8111-111111111111';
  campus_id uuid := '22222222-2222-4222-8222-222222222222';
  building_id uuid := '33333333-3333-4333-8333-333333333333';
  floor_id uuid := '44444444-4444-4444-8444-444444444444';
  venue_a uuid := '55555555-5555-4555-8555-555555555551';
  venue_b uuid := '55555555-5555-4555-8555-555555555552';
  venue_c uuid := '55555555-5555-4555-8555-555555555553';
  venue_d uuid := '55555555-5555-4555-8555-555555555554';
  event_a uuid := '66666666-6666-4666-8666-666666666661';
  event_b uuid := '66666666-6666-4666-8666-666666666662';
  event_c uuid := '66666666-6666-4666-8666-666666666663';
  edition_a uuid := '77777777-7777-4777-8777-777777777771';
  edition_b uuid := '77777777-7777-4777-8777-777777777772';
  edition_c uuid := '77777777-7777-4777-8777-777777777773';
  session_a uuid := '88888888-8888-4888-8888-888888888881';
  session_b uuid := '88888888-8888-4888-8888-888888888882';
  session_c uuid := '88888888-8888-4888-8888-888888888883';
  landmark_gate uuid := '99999999-9999-4999-8999-999999999991';
  landmark_hall uuid := '99999999-9999-4999-8999-999999999992';
  landmark_lab uuid := '99999999-9999-4999-8999-999999999993';
  route_id uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
  node_gate uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1';
  node_hall uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2';
  node_lab uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3';
  channel_a uuid := 'cccccccc-cccc-4ccc-8ccc-ccccccccccc1';
  channel_b uuid := 'cccccccc-cccc-4ccc-8ccc-ccccccccccc2';
  channel_c uuid := 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3';
  registration_a uuid := 'dddddddd-dddd-4ddd-8ddd-ddddddddddd1';
  registration_b uuid := 'dddddddd-dddd-4ddd-8ddd-ddddddddddd2';
  registration_c uuid := 'dddddddd-dddd-4ddd-8ddd-ddddddddddd3';
  pass_a uuid := 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee1';
  pass_b uuid := 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee2';
  pass_c uuid := 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee3';
  report_id uuid := 'ffffffff-ffff-4fff-8fff-fffffffffff1';
  now_at timestamptz := now();
  day_one timestamptz := date_trunc('day', now_at) + interval '1 day';
  day_two timestamptz := date_trunc('day', now_at) + interval '2 days';
begin
  if not exists (select 1 from auth.users where id in (admin_id, organizer_id, student_id) having count(*) = 3) then
    raise exception 'Create the three demo Auth users before running this seed.';
  end if;

  insert into public.profiles(id,college_id,full_name,status) values
    (admin_id,college_id,'IIIT Delhi Admin','active'),
    (organizer_id,college_id,'Aarav · Events Team','active'),
    (student_id,college_id,'Demo Student','active')
  on conflict(id) do update set college_id=excluded.college_id,full_name=excluded.full_name,status='active',updated_at=now_at;

  insert into public.college_memberships(college_id,user_id,is_admin,status,invited_by) values
    (college_id,admin_id,true,'active',admin_id),
    (college_id,organizer_id,false,'active',admin_id),
    (college_id,student_id,false,'active',admin_id)
  on conflict on constraint college_memberships_college_id_user_id_key do update set is_admin=excluded.is_admin,status='active',invited_by=excluded.invited_by,updated_at=now_at;

  insert into public.organizations(id,college_id,slug,name,description,is_active) values
    (org_id,college_id,'iiit-delhi-events','IIIT Delhi Events','Official IIIT Delhi student events and volunteer operations.',true)
  on conflict(id) do update set name=excluded.name,description=excluded.description,is_active=true,updated_at=now_at;
  insert into public.memberships(organization_id,user_id,role,status,invited_by) values
    (org_id,admin_id,'organizer','active',admin_id),
    (org_id,organizer_id,'organizer','active',admin_id),
    (org_id,organizer_id,'event_volunteer','active',admin_id),
    (org_id,student_id,'member','active',admin_id)
  on conflict(organization_id,user_id,role) do update set status='active',invited_by=excluded.invited_by,updated_at=now_at;

  insert into public.campuses(id,college_id,name,latitude,longitude) values
    (campus_id,college_id,'IIIT Delhi Campus',28.5457,77.2732)
  on conflict(id) do update set name=excluded.name,latitude=excluded.latitude,longitude=excluded.longitude;
  insert into public.buildings(id,campus_id,name,latitude,longitude,orientation_degrees) values
    (building_id,campus_id,'Academic Block',28.5459,77.2734,0)
  on conflict(id) do update set name=excluded.name;
  insert into public.floors(id,building_id,name,level,is_published) values
    (floor_id,building_id,'Ground Floor',0,true)
  on conflict(id) do update set name=excluded.name,is_published=true;
  insert into public.venues(id,campus_id,name,kind,latitude,longitude,accessibility_notes) values
    (venue_a,campus_id,'Main Gate','outdoor',28.5457,77.2732,'Step-free entry'),
    (venue_b,campus_id,'Innovation Hall','hall',28.5459,77.2734,'Lift access from the main entrance'),
    (venue_c,campus_id,'Seminar Room 1','hall',28.5460,77.2735,'Ground-floor accessible room'),
    (venue_d,campus_id,'Student Activity Centre','building',28.5455,77.2730,'Accessible entrance on the east side')
  on conflict(id) do update set name=excluded.name,kind=excluded.kind,latitude=excluded.latitude,longitude=excluded.longitude,accessibility_notes=excluded.accessibility_notes;

  insert into public.landmarks(id,campus_id,venue_id,name,coordinate_kind,latitude,longitude,facing_degrees,facing_instruction) values
    (landmark_gate,campus_id,venue_a,'IIIT Delhi Main Gate','outdoor_geographic',28.5457,77.2732,90,'Face east toward the Academic Block.'),
    (landmark_hall,campus_id,venue_b,'Innovation Hall entrance','outdoor_geographic',28.5459,77.2734,180,'Face south toward the main corridor.'),
    (landmark_lab,campus_id,venue_c,'Seminar Room 1 door','outdoor_geographic',28.5460,77.2735,180,'Face south toward the room door.')
  on conflict(id) do update set name=excluded.name,is_active=true;

  insert into public.route_versions(id,campus_id,version,status,physical_validation_complete,validation_notes,validated_by,validated_at,published_at) values
    (route_id,campus_id,1,'published',false,'Development demo route. Confirm distances and AR alignment on campus before production.',admin_id,now_at,now_at)
  on conflict(id) do update set status='published',physical_validation_complete=false,validation_notes=excluded.validation_notes,validated_by=admin_id,validated_at=now_at,published_at=now_at;
  insert into public.route_nodes(id,route_version_id,landmark_id,coordinate_kind,latitude,longitude,node_kind,is_accessible) values
    (node_gate,route_id,landmark_gate,'outdoor_geographic',28.5457,77.2732,'entrance',true),
    (node_hall,route_id,landmark_hall,'outdoor_geographic',28.5459,77.2734,'hall',true),
    (node_lab,route_id,landmark_lab,'outdoor_geographic',28.5460,77.2735,'hall',true)
  on conflict(id) do update set landmark_id=excluded.landmark_id,latitude=excluded.latitude,longitude=excluded.longitude;
  insert into public.route_edges(id,route_version_id,from_node_id,to_node_id,kind,distance_meters,geometry,instruction,is_accessible,is_bidirectional) values
    ('abababab-abab-4aba-8aba-ababababab01',route_id,node_gate,node_hall,'walkway',32,'[{"latitude":28.5457,"longitude":77.2732},{"latitude":28.5459,"longitude":77.2734}]','Walk east from the Main Gate to Innovation Hall.',true,true),
    ('abababab-abab-4aba-8aba-ababababab02',route_id,node_hall,node_lab,'corridor',18,'[{"latitude":28.5459,"longitude":77.2734},{"latitude":28.5460,"longitude":77.2735}]','Continue along the Academic Block corridor to Seminar Room 1.',true,true)
  on conflict(id) do update set distance_meters=excluded.distance_meters,geometry=excluded.geometry,instruction=excluded.instruction;

  insert into public.events(id,college_id,organization_id,title,description,category,visibility,price_minor,currency,eligibility,status,created_by,client_request_id,published_at) values
    (event_a,college_id,org_id,'IIIT Delhi Welcome Workshop','Meet student clubs, learn how campus events work, and find your first community.','Orientation','college_only',0,'INR','IIIT Delhi students','published',organizer_id,'12121212-1212-4121-8121-121212121211',now_at),
    (event_b,college_id,org_id,'Build Night: AI & Design','A practical evening workshop with student builders, mentors and a hands-on prototype challenge.','Workshop','college_only',0,'INR','IIIT Delhi students','published',organizer_id,'12121212-1212-4121-8121-121212121212',now_at),
    (event_c,college_id,org_id,'Campus Open Mic','Music, poetry and performances from the IIIT Delhi community.','Community','college_only',0,'INR','IIIT Delhi students and staff','published',organizer_id,'12121212-1212-4121-8121-121212121213',now_at)
  on conflict(id) do update set title=excluded.title,description=excluded.description,category=excluded.category,status='published',published_at=coalesce(public.events.published_at,excluded.published_at),updated_at=now_at;

  insert into public.event_editions(id,event_id,label,registration_opens_at,registration_closes_at,starts_at,ends_at,capacity,waitlist_enabled,reentry_allowed) values
    (edition_a,event_a,'April 2026 edition',now_at - interval '2 days',day_one - interval '2 hours',day_one + interval '10 hours',day_one + interval '12 hours',120,true,true),
    (edition_b,event_b,'April 2026 edition',now_at - interval '2 days',day_two - interval '2 hours',day_two + interval '6 hours',day_two + interval '9 hours',80,true,true),
    (edition_c,event_c,'April 2026 edition',now_at - interval '2 days',day_two - interval '3 hours',day_two + interval '12 hours',day_two + interval '14 hours',200,true,false)
  on conflict(id) do update set label=excluded.label,starts_at=excluded.starts_at,ends_at=excluded.ends_at,capacity=excluded.capacity,waitlist_enabled=true,reentry_allowed=excluded.reentry_allowed;
  insert into public.event_sessions(id,edition_id,venue_id,title,starts_at,ends_at) values
    (session_a,edition_a,venue_b,'Welcome and club fair',day_one + interval '10 hours',day_one + interval '12 hours'),
    (session_b,edition_b,venue_c,'Prototype studio',day_two + interval '6 hours',day_two + interval '9 hours'),
    (session_c,edition_c,venue_d,'Open mic stage',day_two + interval '12 hours',day_two + interval '14 hours')
  on conflict(id) do update set venue_id=excluded.venue_id,title=excluded.title,starts_at=excluded.starts_at,ends_at=excluded.ends_at;
  insert into public.event_staff_assignments(id,edition_id,user_id,role,assigned_by) values
    ('abababab-abab-4aba-8aba-ababababab11',edition_a,organizer_id,'event_volunteer',admin_id),
    ('abababab-abab-4aba-8aba-ababababab12',edition_b,organizer_id,'event_volunteer',admin_id),
    ('abababab-abab-4aba-8aba-ababababab13',edition_c,organizer_id,'event_volunteer',admin_id)
  on conflict(edition_id,user_id,role) do update set assigned_by=excluded.assigned_by;

  insert into public.channels(id,edition_id) values (channel_a,edition_a),(channel_b,edition_b),(channel_c,edition_c)
  on conflict(edition_id) do update set is_locked=false;
  insert into public.announcements(id,edition_id,title,body,kind,created_by) values
    ('abababab-abab-4aba-8aba-ababababab21',edition_a,'Welcome to IIIT Delhi','Bring your student ID and arrive 15 minutes early at the Main Gate.','official',admin_id),
    ('abababab-abab-4aba-8aba-ababababab22',edition_b,'Workshop venue','Build Night takes place in Seminar Room 1, Academic Block.','venue_change',admin_id),
    ('abababab-abab-4aba-8aba-ababababab23',edition_c,'Open mic sign-ups','Walk-in performers can register with the stage volunteer.','official',admin_id)
  on conflict(id) do update set title=excluded.title,body=excluded.body,kind=excluded.kind;
  insert into public.messages(id,channel_id,author_id,body,status)
  select 'abababab-abab-4aba-8aba-ababababab31'::uuid,id,student_id,'Looking forward to meeting the clubs!','visible'::public.message_status from public.channels where edition_id=edition_a
  union all select 'abababab-abab-4aba-8aba-ababababab32'::uuid,id,organizer_id,'Bring a laptop if you want to join the prototype challenge.','visible'::public.message_status from public.channels where edition_id=edition_b
  union all select 'abababab-abab-4aba-8aba-ababababab33'::uuid,id,student_id,'Can I perform a short acoustic set?','visible'::public.message_status from public.channels where edition_id=edition_c
  on conflict(id) do update set body=excluded.body,status='visible'::public.message_status;

  insert into public.registrations(id,edition_id,user_id,status,client_request_id,registered_at) values
    (registration_a,edition_a,student_id,'registered','13131313-1313-4131-8131-131313131311',now_at),
    (registration_b,edition_b,student_id,'registered','13131313-1313-4131-8131-131313131312',now_at),
    (registration_c,edition_c,student_id,'registered','13131313-1313-4131-8131-131313131313',now_at)
  on conflict(id) do update set status='registered',registered_at=coalesce(public.registrations.registered_at,excluded.registered_at),cancelled_at=null;
  insert into public.passes(id,registration_id,token,status) values
    (pass_a,registration_a,'14141414-1414-4141-8141-141414141411','active'),
    (pass_b,registration_b,'14141414-1414-4141-8141-141414141412','active'),
    (pass_c,registration_c,'14141414-1414-4141-8141-141414141413','active')
  on conflict(id) do update set status='active',revoked_at=null;
  insert into public.attendance_transitions(id,edition_id,registration_id,pass_id,action,scanned_by,client_request_id,recorded_at) values
    ('abababab-abab-4aba-8aba-ababababab41',edition_a,registration_a,pass_a,'enter',organizer_id,'15151515-1515-4151-8151-151515151511',now_at - interval '15 minutes')
  on conflict(id) do nothing;
  insert into public.reports(id,edition_id,reporter_id,category,description,priority,status) values
    (report_id,edition_a,student_id,'Accessibility','The route from the Main Gate should keep the lift entrance clearly marked.', 'normal','submitted')
  on conflict(id) do update set description=excluded.description,status='submitted',updated_at=now_at;
  insert into public.reviews(id,event_id,edition_id,user_id,rating,body) values
    ('abababab-abab-4aba-8aba-ababababab51',event_a,edition_a,student_id,5,'Friendly volunteers and a clear introduction to campus life.')
  on conflict(event_id,user_id) do update set rating=excluded.rating,body=excluded.body,updated_at=now_at;
  insert into public.follows(user_id,organization_id) values (student_id,org_id) on conflict do nothing;
  insert into public.notifications(id,user_id,edition_id,kind,title,body,payload) values
    ('abababab-abab-4aba-8aba-ababababab61',student_id,edition_a,'announcement','Welcome to IIIT Delhi','Your Welcome Workshop pass is active.','{"demo":true}'),
    ('abababab-abab-4aba-8aba-ababababab62',student_id,edition_b,'venue_change','Venue updated','Build Night is in Seminar Room 1.','{"demo":true}')
  on conflict(id) do update set title=excluded.title,body=excluded.body;
end $$;
