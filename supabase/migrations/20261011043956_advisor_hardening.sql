-- Index every foreign-key lookup that is not already covered by the leading
-- columns of an existing index. These support deletes, joins, and RLS checks.
create index college_memberships_invited_by_idx
  on public.college_memberships (invited_by);

create index event_sessions_venue_id_idx
  on public.event_sessions (venue_id);

create index event_staff_assignments_assigned_by_idx
  on public.event_staff_assignments (assigned_by);

create index event_staff_assignments_user_id_idx
  on public.event_staff_assignments (user_id);

create index events_college_id_idx
  on public.events (college_id);

create index events_organization_id_idx
  on public.events (organization_id);

create index memberships_invited_by_idx
  on public.memberships (invited_by);

create index profiles_college_id_idx
  on public.profiles (college_id);

-- Authenticated reads previously used two permissive SELECT policies. Combine
-- them so Postgres evaluates one policy with the intended OR semantics.
drop policy published_events_read on public.events;
drop policy staff_events_read on public.events;

create policy published_events_read
  on public.events
  for select
  to anon
  using (status = 'published');

create policy authenticated_events_read
  on public.events
  for select
  to authenticated
  using (
    status = 'published'
    or private.has_organization_role(
      organization_id,
      array['organizer', 'event_volunteer']::public.membership_role[]
    )
  );
