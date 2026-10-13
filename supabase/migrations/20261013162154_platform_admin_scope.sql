-- Platform administrators govern Sidequest globally. College administrators
-- remain scoped to a single college and organizers remain organization-scoped.
create table public.platform_admins (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  granted_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.platform_admins enable row level security;
revoke all on public.platform_admins from public, anon, authenticated;
grant select on public.platform_admins to authenticated, service_role;
create policy platform_admins_read_self on public.platform_admins
  for select to authenticated
  using ((select auth.uid()) = user_id);

create function private.is_platform_admin(target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_user_id is not null and exists (
    select 1 from public.platform_admins pa where pa.user_id = target_user_id
  );
$$;
revoke all on function private.is_platform_admin(uuid) from public, anon;
grant execute on function private.is_platform_admin(uuid) to authenticated;

-- Existing clients can still discover active organizations. Only platform
-- administrators may also see inactive organizations in the global directory.
create policy organizations_platform_admin_read on public.organizations
  for select to authenticated
  using (private.is_platform_admin());

create or replace function public.create_organization(
  p_college_id uuid,
  p_name text,
  p_slug text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  platform_admin boolean;
  college_admin boolean;
  saved uuid;
begin
  platform_admin := private.is_platform_admin(actor);
  college_admin := private.is_college_admin(p_college_id, actor);
  if actor is null or (not platform_admin and not college_admin) then
    raise sqlstate 'PGRST' using
      message = '{"code":"FORBIDDEN","message":"Sidequest platform administrator access is required."}',
      detail = '{"status":403}';
  end if;

  insert into public.organizations(college_id, name, slug, description)
  values (p_college_id, trim(p_name), lower(trim(p_slug)), nullif(trim(p_description), ''))
  returning id into saved;

  -- A college administrator may also manage the organization they create.
  -- A global platform administrator does not silently become a college organizer.
  if college_admin and not platform_admin then
    insert into public.memberships(organization_id, user_id, role, status, invited_by)
    values (saved, actor, 'organizer', 'active', actor);
  end if;

  insert into public.audit_records(actor_id, action, entity_type, entity_id, detail)
  values (actor, 'organization.create', 'organization', saved,
    jsonb_build_object('college_id', p_college_id, 'platform_admin', platform_admin));
  return jsonb_build_object('organization_id', saved, 'persisted', true);
end;
$$;

revoke all on function public.create_organization(uuid, text, text, text) from public, anon;
grant execute on function public.create_organization(uuid, text, text, text) to authenticated;
