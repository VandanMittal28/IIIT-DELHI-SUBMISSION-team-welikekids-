-- College membership identifies a student. Society membership grants event authoring.
alter table public.profiles
  add column account_type text not null default 'student' check (account_type in ('student','organizer')),
  add column login_username text unique;

update public.profiles profile
set account_type='organizer'
where exists (
  select 1 from public.memberships membership
  join public.organizations society on society.id=membership.organization_id
  where membership.user_id=profile.id and membership.role='organizer' and membership.status='active'
    and not private.is_college_admin(society.college_id,profile.id)
    and not private.is_platform_admin(profile.id)
);

update public.profiles profile
set login_username=lower(split_part(account.email,'@',1))
from auth.users account
where account.id=profile.id and lower(account.email) like '%@sidequest.local';

alter table public.organizations
  add column head_user_id uuid references public.profiles(id) on delete set null;

update public.organizations society
set head_user_id=(
  select membership.user_id from public.memberships membership
  join public.profiles profile on profile.id=membership.user_id
  join public.college_memberships college_member
    on college_member.college_id=society.college_id and college_member.user_id=profile.id
  where membership.organization_id=society.id and membership.role='organizer' and membership.status='active'
    and profile.account_type='organizer' and profile.status='active'
    and college_member.status='active' and not college_member.is_admin
    and not private.is_platform_admin(profile.id)
  order by membership.created_at,membership.id limit 1
);

create or replace function private.has_organization_role(
  target_organization_id uuid,
  allowed_roles public.membership_role[],
  target_user_id uuid default auth.uid()
)
returns boolean language sql stable security definer set search_path = '' as $$
  select target_user_id is not null
    and exists (select 1 from public.profiles p where p.id=target_user_id and p.status='active')
    and not private.is_platform_admin(target_user_id)
    and exists (
      select 1 from public.memberships m
      join public.organizations o on o.id=m.organization_id
      join public.profiles p on p.id=m.user_id
      where m.organization_id=target_organization_id and m.user_id=target_user_id
        and m.role=any(allowed_roles) and m.status='active'
        and (m.role<>'organizer' or (p.account_type='organizer' and o.head_user_id=target_user_id))
        and not private.is_college_admin(o.college_id,target_user_id)
    );
$$;

create or replace function private.can_manage_event(target_event_id uuid,target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path='' as $$
 select target_user_id is not null and exists(
   select 1 from public.events event where event.id=target_event_id and (
     private.has_organization_role(event.organization_id,array['organizer']::public.membership_role[],target_user_id)
     or exists(
       select 1 from public.event_cohosts cohost
       where cohost.event_id=event.id
         and private.has_organization_role(cohost.organization_id,array['organizer']::public.membership_role[],target_user_id)
     )
   )
 );
$$;

create or replace function private.can_manage_edition(target_edition_id uuid,target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path='' as $$
 select target_user_id is not null and exists(
   select 1 from public.event_editions edition
   join public.events event on event.id=edition.event_id
   where edition.id=target_edition_id and (
     private.can_manage_event(event.id,target_user_id)
     or exists(
       select 1 from public.event_staff_assignments assignment
       where assignment.edition_id=edition.id and assignment.user_id=target_user_id
     )
   )
 );
$$;

-- A new society does not turn its creator into its organizer.
create or replace function public.create_organization(
  p_college_id uuid,p_name text,p_slug text,p_description text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare actor uuid := auth.uid(); saved uuid;
begin
  if actor is null or not (private.is_platform_admin(actor) or private.is_college_admin(p_college_id,actor)) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}';
  end if;
  insert into public.organizations(college_id,name,slug,description)
  values(p_college_id,trim(p_name),lower(trim(p_slug)),nullif(trim(p_description),'')) returning id into saved;
  insert into public.audit_records(actor_id,action,entity_type,entity_id,detail)
  values(actor,'organization.create','organization',saved,jsonb_build_object('college_id',p_college_id));
  return jsonb_build_object('organization_id',saved,'persisted',true);
end;
$$;

-- Organizers may assign any active student of their event's college.
create or replace function public.get_event_staff_candidates(p_edition_id uuid)
returns table(user_id uuid,full_name text,role public.membership_role,organization_name text)
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null or not exists(
   select 1 from public.event_editions edition
   where edition.id=p_edition_id and private.can_manage_event(edition.event_id,actor)
 ) then
   raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Society organizer access is required."}',detail='{"status":403}';
 end if;
 return query
 select p.id,coalesce(nullif(trim(p.full_name),''),'Unnamed student'),
        'event_volunteer'::public.membership_role,c.name
 from public.event_editions edition
 join public.events event on event.id=edition.event_id
 join public.colleges c on c.id=event.college_id
 join public.college_memberships cm on cm.college_id=event.college_id and cm.status='active' and not cm.is_admin
 join public.profiles p on p.id=cm.user_id and p.status='active'
 where edition.id=p_edition_id
 order by coalesce(nullif(trim(p.full_name),''),'Unnamed student'),p.id;
end $$;

create function public.get_college_organizer_accounts(p_college_id uuid)
returns table(user_id uuid,full_name text,login_username text)
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null or not (private.is_platform_admin(actor) or private.is_college_admin(p_college_id,actor)) then
   raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}';
 end if;
 return query
 select profile.id,coalesce(nullif(trim(profile.full_name),''),'Unnamed organizer'),profile.login_username
 from public.college_memberships college_member
 join public.profiles profile on profile.id=college_member.user_id
 where college_member.college_id=p_college_id and college_member.status='active' and not college_member.is_admin
   and profile.status='active' and profile.account_type='organizer'
 order by profile.full_name,profile.id;
end $$;

create function public.assign_society_head(p_organization_id uuid,p_user_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); society public.organizations; existing_head uuid;
begin
 select * into society from public.organizations where id=p_organization_id for update;
 if actor is null or society.id is null or not (private.is_platform_admin(actor) or private.is_college_admin(society.college_id,actor)) then
   raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}';
 end if;
 if not society.is_active or not exists(
   select 1 from public.profiles profile
   join public.college_memberships college_member on college_member.user_id=profile.id
   where profile.id=p_user_id and profile.status='active' and profile.account_type='organizer'
     and college_member.college_id=society.college_id and college_member.status='active' and not college_member.is_admin
     and not private.is_platform_admin(profile.id)
 ) then
   raise sqlstate 'PGRST' using message='{"code":"INVALID_HEAD","message":"Choose an active organizer account from this college."}',detail='{"status":422}';
 end if;
 if society.head_user_id=p_user_id and exists(
   select 1 from public.memberships membership
   where membership.organization_id=society.id and membership.user_id=p_user_id
     and membership.role='organizer' and membership.status='active'
 ) then
   return jsonb_build_object('organization_id',society.id,'head_user_id',p_user_id,'persisted',true,'idempotent_replay',true);
 end if;
 existing_head:=case when society.head_user_id=p_user_id then null else society.head_user_id end;
 update public.organizations set head_user_id=p_user_id,updated_at=now() where id=society.id;
 insert into public.memberships(organization_id,user_id,role,status,invited_by)
 values(society.id,p_user_id,'organizer','active',actor)
 on conflict(organization_id,user_id,role) do update set status='active',invited_by=actor,updated_at=now();
 if existing_head is not null then
   update public.memberships set status='revoked',updated_at=now()
   where organization_id=society.id and user_id=existing_head and role='organizer';
 end if;
 insert into public.audit_records(actor_id,action,entity_type,entity_id,detail)
 values(actor,'society.head.assign','organization',society.id,
   jsonb_build_object('head_user_id',p_user_id,'previous_head_user_id',existing_head));
 return jsonb_build_object('organization_id',society.id,'head_user_id',p_user_id,'persisted',true,'idempotent_replay',false);
end $$;

revoke all on function public.get_college_organizer_accounts(uuid),public.assign_society_head(uuid,uuid) from public,anon;
grant execute on function public.get_college_organizer_accounts(uuid),public.assign_society_head(uuid,uuid) to authenticated;

create or replace function public.assign_event_staff(p_edition_id uuid,p_user_id uuid,p_role public.membership_role)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); saved uuid;
begin
 if actor is null or p_role <> 'event_volunteer' or not exists(
   select 1 from public.event_editions edition
   where edition.id=p_edition_id and private.can_manage_event(edition.event_id,actor)
 ) then
   raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Society organizer access is required."}',detail='{"status":403}';
 end if;
 if not exists(
   select 1 from public.event_editions edition
   join public.events event on event.id=edition.event_id
   join public.college_memberships cm on cm.college_id=event.college_id and cm.user_id=p_user_id
   join public.profiles p on p.id=cm.user_id
   where edition.id=p_edition_id and cm.status='active' and not cm.is_admin and p.status='active'
 ) then
   raise sqlstate 'PGRST' using message='{"code":"INVALID_STAFF_CANDIDATE","message":"Choose an active student from this event’s college."}',detail='{"status":422}';
 end if;
 insert into public.event_staff_assignments(edition_id,user_id,role,assigned_by)
 values(p_edition_id,p_user_id,'event_volunteer',actor)
 on conflict(edition_id,user_id,role) do nothing returning user_id into saved;
 if saved is null then
   return jsonb_build_object('edition_id',p_edition_id,'user_id',p_user_id,'role','event_volunteer','persisted',true,'idempotent_replay',true);
 end if;
 insert into public.audit_records(actor_id,action,entity_type,entity_id,detail)
 values(actor,'staff.assign','event_edition',p_edition_id,jsonb_build_object('user_id',p_user_id,'role','event_volunteer'));
 return jsonb_build_object('edition_id',p_edition_id,'user_id',p_user_id,'role','event_volunteer','persisted',true,'idempotent_replay',false);
end $$;
