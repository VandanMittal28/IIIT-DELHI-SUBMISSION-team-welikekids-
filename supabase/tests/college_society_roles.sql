\set ON_ERROR_STOP on
begin;

insert into auth.users(id,email) values
 ('10000000-0000-0000-0000-000000000101','college-admin@example.invalid'),
 ('10000000-0000-0000-0000-000000000102','society-organizer@example.invalid'),
 ('10000000-0000-0000-0000-000000000103','student@example.invalid'),
 ('10000000-0000-0000-0000-000000000104','other-college@example.invalid'),
 ('10000000-0000-0000-0000-000000000105','second-organizer@example.invalid');
insert into public.colleges(id,slug,name) values
 ('20000000-0000-0000-0000-000000000101','role-test-college','Role Test College'),
 ('20000000-0000-0000-0000-000000000102','role-other-college','Other College');
insert into public.college_memberships(college_id,user_id,is_admin,status) values
 ('20000000-0000-0000-0000-000000000101','10000000-0000-0000-0000-000000000101',true,'active'),
 ('20000000-0000-0000-0000-000000000101','10000000-0000-0000-0000-000000000102',false,'active'),
 ('20000000-0000-0000-0000-000000000101','10000000-0000-0000-0000-000000000103',false,'active'),
 ('20000000-0000-0000-0000-000000000102','10000000-0000-0000-0000-000000000104',false,'active'),
 ('20000000-0000-0000-0000-000000000101','10000000-0000-0000-0000-000000000105',false,'active');
update public.profiles set account_type='organizer',login_username='society-organizer'
where id='10000000-0000-0000-0000-000000000102';
update public.profiles set account_type='organizer',login_username='second-organizer'
where id='10000000-0000-0000-0000-000000000105';
update public.profiles set account_type='organizer',login_username='other-college'
where id='10000000-0000-0000-0000-000000000104';

select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000101',true);
select set_config('request.jwt.claim.role','authenticated',true);
set role authenticated;
select public.create_organization('20000000-0000-0000-0000-000000000101','Tech Society','tech-society',null);
reset role;
do $$ begin
 if exists(select 1 from public.memberships where user_id='10000000-0000-0000-0000-000000000101') then
   raise exception 'college admin inherited society membership';
 end if;
end $$;
-- Even a leftover organizer membership cannot make a college admin an event author.
insert into public.memberships(organization_id,user_id,role,status)
select id,'10000000-0000-0000-0000-000000000101','organizer','active'
from public.organizations where slug='tech-society';

create temporary table role_test(edition_id uuid);
grant select,insert on role_test to authenticated;
set role authenticated;
do $$ declare society uuid; result jsonb; begin
 select id into society from public.organizations where slug='tech-society';
 if (select count(*) from public.get_college_organizer_accounts('20000000-0000-0000-0000-000000000101'))<>2 then
   raise exception 'admin cannot find existing organizer IDs';
 end if;
 begin
   perform public.assign_society_head(society,'10000000-0000-0000-0000-000000000103');
   raise exception 'student was assigned as society head';
 exception when sqlstate 'PGRST' then null; end;
 begin
   perform public.assign_society_head(society,'10000000-0000-0000-0000-000000000104');
   raise exception 'organizer from another college was assigned as society head';
 exception when sqlstate 'PGRST' then null; end;
 begin
   perform public.create_event('40000000-0000-0000-0000-000000000101',society,'Admin event','College admin may not create events','Workshop','public',0,'INR',null,now(),now()+interval '1 day',now()+interval '2 days',now()+interval '3 days',10,true);
   raise exception 'college admin created an event';
 exception when sqlstate 'PGRST' then null; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000102',true);
do $$ declare society uuid; begin
 select id into society from public.organizations where slug='tech-society';
 begin
   perform public.assign_society_head(society,'10000000-0000-0000-0000-000000000102');
   raise exception 'organizer assigned self as society head';
 exception when sqlstate 'PGRST' then null; end;
 begin
   perform public.create_event('40000000-0000-0000-0000-000000000106',society,'Early event','Organizer lacks head assignment','Workshop','public',0,'INR',null,now(),now()+interval '1 day',now()+interval '2 days',now()+interval '3 days',10,true);
   raise exception 'organizer created an event before head assignment';
 exception when sqlstate 'PGRST' then null; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000101',true);
select public.assign_society_head((select id from public.organizations where slug='tech-society'),'10000000-0000-0000-0000-000000000102');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000102',true);
do $$ declare society uuid; result jsonb; begin
 select id into society from public.organizations where slug='tech-society';
 result:=public.create_event('40000000-0000-0000-0000-000000000102',society,'Society event','Created by the society organizer','Workshop','public',0,'INR',null,now(),now()+interval '1 day',now()+interval '2 days',now()+interval '3 days',10,true);
 insert into role_test values((result->>'edition_id')::uuid);
 if (select count(*) from public.get_event_staff_candidates((result->>'edition_id')::uuid))<>3 then
   raise exception 'college student candidate list is incorrect';
 end if;
 perform public.assign_event_staff((result->>'edition_id')::uuid,'10000000-0000-0000-0000-000000000103','event_volunteer');
 if not exists(select 1 from public.event_staff_assignments where edition_id=(result->>'edition_id')::uuid and user_id='10000000-0000-0000-0000-000000000103') then
   raise exception 'student volunteer assignment was not saved';
 end if;
 begin
   perform public.assign_event_staff((result->>'edition_id')::uuid,'10000000-0000-0000-0000-000000000104','event_volunteer');
   raise exception 'student from another college was assigned';
 exception when sqlstate 'PGRST' then null; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000101',true);
select public.assign_society_head((select id from public.organizations where slug='tech-society'),'10000000-0000-0000-0000-000000000105');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000102',true);
do $$ begin
 begin
   perform public.assign_event_staff((select edition_id from role_test),'10000000-0000-0000-0000-000000000105','event_volunteer');
   raise exception 'previous society head retained management access';
 exception when sqlstate 'PGRST' then null; end;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000105',true);
do $$ begin
 if (select count(*) from public.get_event_staff_candidates((select edition_id from role_test)))<>3 then
   raise exception 'new society head cannot manage event';
 end if;
end $$;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000103',true);
do $$ begin
 begin
   perform public.assign_event_staff((select edition_id from role_test),'10000000-0000-0000-0000-000000000102','event_volunteer');
   raise exception 'volunteer assigned additional staff';
 exception when sqlstate 'PGRST' then null; end;
end $$;
rollback;
