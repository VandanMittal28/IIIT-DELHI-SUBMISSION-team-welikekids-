create policy route_versions_admin_read on public.route_versions for select to authenticated using (
 exists(select 1 from public.campuses c where c.id=campus_id and private.is_college_admin(c.college_id))
);
create policy route_nodes_admin_read on public.route_nodes for select to authenticated using (
 exists(select 1 from public.route_versions rv join public.campuses c on c.id=rv.campus_id where rv.id=route_version_id and private.is_college_admin(c.college_id))
);
create policy route_edges_admin_read on public.route_edges for select to authenticated using (
 exists(select 1 from public.route_versions rv join public.campuses c on c.id=rv.campus_id where rv.id=route_version_id and private.is_college_admin(c.college_id))
);
