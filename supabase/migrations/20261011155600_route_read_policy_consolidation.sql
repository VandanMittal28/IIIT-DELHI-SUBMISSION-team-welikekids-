-- Keep one permissive SELECT policy per role/action so route reads do not evaluate overlapping policies.
drop policy if exists route_versions_read on public.route_versions;
drop policy if exists route_versions_admin_read on public.route_versions;
drop policy if exists route_nodes_read on public.route_nodes;
drop policy if exists route_nodes_admin_read on public.route_nodes;
drop policy if exists route_edges_read on public.route_edges;
drop policy if exists route_edges_admin_read on public.route_edges;

create policy route_versions_anon_read on public.route_versions for select to anon
using (status='published');
create policy route_versions_authenticated_read on public.route_versions for select to authenticated
using (
  status='published'
  or exists(select 1 from public.campuses c where c.id=campus_id and private.is_college_admin(c.college_id))
);

create policy route_nodes_anon_read on public.route_nodes for select to anon
using (exists(select 1 from public.route_versions rv where rv.id=route_version_id and rv.status='published'));
create policy route_nodes_authenticated_read on public.route_nodes for select to authenticated
using (exists(
  select 1 from public.route_versions rv
  join public.campuses c on c.id=rv.campus_id
  where rv.id=route_version_id and (rv.status='published' or private.is_college_admin(c.college_id))
));

create policy route_edges_anon_read on public.route_edges for select to anon
using (exists(select 1 from public.route_versions rv where rv.id=route_version_id and rv.status='published'));
create policy route_edges_authenticated_read on public.route_edges for select to authenticated
using (exists(
  select 1 from public.route_versions rv
  join public.campuses c on c.id=rv.campus_id
  where rv.id=route_version_id and (rv.status='published' or private.is_college_admin(c.college_id))
));
