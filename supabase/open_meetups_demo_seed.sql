-- Development-only Open Meetups demo for the IIIT Delhi scenario.
-- Run AFTER supabase/seed.sql in the authorized development project. Safe to re-run. Never run against production.
-- Registrations are not seeded: students create them through the app's "I'm Going" button.
-- Only Open Meetups tables are written. Venue navigation stays under set_venue_navigation (college administrators).

do $$
#variable_conflict use_variable
declare
  college_id uuid := 'bc3417c0-170e-4663-b235-86efc40cebb2';
  admin_id uuid := '6d6ba29a-5977-4d07-bed3-41818325d67d';
  host_id uuid := 'e2e7ea47-1428-45d0-8c8c-2d9a32186b82';
  venue_hall uuid := '55555555-5555-4555-8555-555555555552';
  venue_seminar uuid := '55555555-5555-4555-8555-555555555553';
  venue_sac uuid := '55555555-5555-4555-8555-555555555554';
  day_one timestamptz := date_trunc('day', now()) + interval '1 day';
  day_two timestamptz := date_trunc('day', now()) + interval '2 days';
  day_three timestamptz := date_trunc('day', now()) + interval '3 days';
begin
  if not exists (select 1 from public.college_memberships m where m.college_id = college_id and m.user_id = host_id and m.status = 'active') then
    raise exception 'Run supabase/seed.sql before this file.';
  end if;

  insert into public.meetup_hosts (user_id, college_id, display_name, headline, verified_by)
  values (host_id, college_id, 'Aarav', 'Final-year CSE · Student mentor', admin_id)
  on conflict (user_id) do update set display_name = excluded.display_name, headline = excluded.headline, revoked_at = null, updated_at = now();

  insert into public.open_meetups (id, college_id, host_id, venue_id, title, description, location_note, icebreaker, audience, capacity, starts_at, ends_at, status, created_by, client_request_id, published_at) values
    ('a0000000-0000-4000-8000-000000000001', college_id, host_id, venue_sac, 'Canteen Chai Meetup', 'Grab a cup of chai and meet a few new faces. Come alone — that is the point.', 'Look for the lime Sidequest card on the table', 'What''s been the best part of your week?', 'selected_colleges', 12, day_one + interval '10 hours 30 minutes', day_one + interval '11 hours 30 minutes', 'published', host_id, 'a1000000-0000-4000-8000-000000000001', now()),
    ('a0000000-0000-4000-8000-000000000002', college_id, host_id, venue_hall, 'Lunch With Strangers', 'Share a table with students you have never met. Bring your lunch or grab one on the way.', null, 'What''s one thing about college you wish someone had told you earlier?', 'selected_colleges', 8, day_one + interval '7 hours', day_one + interval '8 hours', 'published', host_id, 'a1000000-0000-4000-8000-000000000002', now()),
    ('a0000000-0000-4000-8000-000000000003', college_id, host_id, venue_hall, 'Meet Students From Other Colleges', 'An open, relaxed hangout for students from every participating college.', null, 'What''s something new you''d like to try this semester?', 'all_colleges', 30, day_two + interval '11 hours', day_two + interval '12 hours 30 minutes', 'published', host_id, 'a1000000-0000-4000-8000-000000000003', now()),
    ('a0000000-0000-4000-8000-000000000004', college_id, host_id, venue_seminar, 'Just Talk — No Agenda', 'No topic, no activity, no pressure. Just good conversation.', null, 'What''s a random thing you''re really passionate about?', 'selected_colleges', 10, day_two + interval '13 hours', day_two + interval '14 hours', 'published', host_id, 'a1000000-0000-4000-8000-000000000004', now()),
    ('a0000000-0000-4000-8000-000000000005', college_id, host_id, venue_sac, 'Make New Connections', 'A friendly mixer for anyone who wants to widen their circle on campus.', null, 'If you could add one thing to campus, what would it be?', 'selected_colleges', 20, day_three + interval '11 hours', day_three + interval '12 hours', 'published', host_id, 'a1000000-0000-4000-8000-000000000005', now())
  on conflict (id) do update set title = excluded.title, description = excluded.description, location_note = excluded.location_note, icebreaker = excluded.icebreaker,
    venue_id = excluded.venue_id, audience = excluded.audience, starts_at = excluded.starts_at, ends_at = excluded.ends_at, updated_at = now();

  insert into public.open_meetup_colleges (meetup_id, college_id)
  select id, college_id from public.open_meetups
  where id in ('a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000005')
  on conflict do nothing;
end $$;
