create or replace function private.can_manage_event(target_event_id uuid,target_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path='' as $$
 select target_user_id is not null and exists(
   select 1 from public.events event where event.id=target_event_id and (
     private.is_college_admin(event.college_id,target_user_id)
     or private.has_organization_role(event.organization_id,array['organizer']::public.membership_role[],target_user_id)
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
     private.is_college_admin(event.college_id,target_user_id)
     or private.has_organization_role(event.organization_id,array['organizer']::public.membership_role[],target_user_id)
     or exists(
       select 1 from public.event_cohosts cohost
       where cohost.event_id=event.id
         and private.has_organization_role(cohost.organization_id,array['organizer']::public.membership_role[],target_user_id)
     )
     or exists(
       select 1 from public.event_staff_assignments assignment
       where assignment.edition_id=edition.id and assignment.user_id=target_user_id
     )
   )
 );
$$;

create function public.get_event_staff_candidates(p_edition_id uuid)
returns table(user_id uuid,full_name text,role public.membership_role,organization_name text)
language plpgsql stable security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null or not private.can_manage_edition(p_edition_id,actor) then
   raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Event manager access is required."}',detail='{"status":403}';
 end if;
 return query
 select membership.user_id,coalesce(nullif(trim(profile.full_name),''),'Unnamed member'),membership.role,string_agg(distinct organization.name,', ' order by organization.name)
 from public.event_editions edition
 join public.events event on event.id=edition.event_id
 join public.organizations organization on organization.id=event.organization_id
   or exists(select 1 from public.event_cohosts cohost where cohost.event_id=event.id and cohost.organization_id=organization.id)
 join public.memberships membership on membership.organization_id=organization.id
 join public.profiles profile on profile.id=membership.user_id
 where edition.id=p_edition_id and membership.status='active' and profile.status='active'
   and membership.role in ('event_volunteer','organizer')
 group by membership.user_id,profile.full_name,membership.role
 order by coalesce(nullif(trim(profile.full_name),''),'Unnamed member'),membership.role;
end $$;

create or replace function public.assign_event_staff(p_edition_id uuid,p_user_id uuid,p_role public.membership_role)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); saved uuid;
begin
 if actor is null or not private.can_manage_edition(p_edition_id,actor) or p_role not in ('event_volunteer','organizer') then
   raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer access and a valid staff role are required."}',detail='{"status":403}';
 end if;
 if not exists(
   select 1 from public.event_editions edition
   join public.events event on event.id=edition.event_id
   join public.memberships membership on membership.user_id=p_user_id and membership.role=p_role and membership.status='active'
   join public.profiles profile on profile.id=membership.user_id and profile.status='active'
   where edition.id=p_edition_id and (
     membership.organization_id=event.organization_id
     or exists(select 1 from public.event_cohosts cohost where cohost.event_id=event.id and cohost.organization_id=membership.organization_id)
   )
 ) then
   raise sqlstate 'PGRST' using message='{"code":"INVALID_STAFF_CANDIDATE","message":"Choose an active organizer or volunteer from a host organization."}',detail='{"status":422}';
 end if;
 insert into public.event_staff_assignments(edition_id,user_id,role,assigned_by)
 values(p_edition_id,p_user_id,p_role,actor)
 on conflict(edition_id,user_id,role) do nothing returning user_id into saved;
 if saved is null then
   return jsonb_build_object('edition_id',p_edition_id,'user_id',p_user_id,'role',p_role,'persisted',true,'idempotent_replay',true);
 end if;
 insert into public.audit_records(actor_id,action,entity_type,entity_id,detail)
 values(actor,'staff.assign','event_edition',p_edition_id,jsonb_build_object('user_id',p_user_id,'role',p_role));
 return jsonb_build_object('edition_id',p_edition_id,'user_id',p_user_id,'role',p_role,'persisted',true,'idempotent_replay',false);
end $$;

revoke all on function private.can_manage_event(uuid,uuid),private.can_manage_edition(uuid,uuid) from public;
revoke all on function public.get_event_staff_candidates(uuid),public.assign_event_staff(uuid,uuid,public.membership_role) from public,anon;
grant execute on function private.can_manage_event(uuid,uuid),private.can_manage_edition(uuid,uuid) to authenticated;
grant execute on function public.get_event_staff_candidates(uuid),public.assign_event_staff(uuid,uuid,public.membership_role) to authenticated;
