-- Resolve the actionable findings raised by the hosted database advisors after
-- the operational platform migration. Transactional mutation functions remain
-- security definer by design; calculate_route is read-only and does not need it.

create index announcements_created_by_idx on public.announcements (created_by);
create index messages_moderated_by_idx on public.messages (moderated_by);
create index occupancy_corrections_corrected_by_idx on public.occupancy_corrections (corrected_by);
create index route_closures_created_by_idx on public.route_closures (created_by);
create index route_versions_validated_by_idx on public.route_versions (validated_by);

alter function public.calculate_route(uuid, uuid, boolean) security invoker;

-- These two queues are deliberately server-only. Explicit deny policies make
-- that intent machine-readable while grants continue to exclude client roles.
create policy "audit_records_no_client_access"
on public.audit_records
for select
to authenticated
using (false);

create policy "notification_delivery_jobs_no_client_access"
on public.notification_delivery_jobs
for select
to authenticated
using (false);

-- Keep anonymous floor-plan discovery independent of private helper execution.
drop policy if exists "floors_read" on public.floors;

create policy "floors_published_anon_read"
on public.floors
for select
to anon
using (is_published);

create policy "floors_authenticated_read"
on public.floors
for select
to authenticated
using (
  is_published
  or exists (
    select 1
    from public.buildings b
    join public.campuses c on c.id = b.campus_id
    where b.id = floors.building_id
      and private.is_college_admin(c.college_id)
  )
);
