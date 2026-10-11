alter table public.profiles
  add column interests text[] not null default '{}',
  add column notification_preferences jsonb not null default '{"announcements":true,"venue_changes":true,"reminders":true,"reports":true}'::jsonb
    check (jsonb_typeof(notification_preferences)='object'),
  add column deletion_requested_at timestamptz;

create function private.ensure_edition_channel()
returns trigger language plpgsql security definer set search_path='' as $$
begin insert into public.channels(edition_id) values(new.id) on conflict(edition_id) do nothing; return new; end $$;
create trigger ensure_edition_channel after insert on public.event_editions for each row execute function private.ensure_edition_channel();
insert into public.channels(edition_id) select id from public.event_editions on conflict(edition_id) do nothing;

create view public.my_community_channels with (security_invoker=true) as
select c.id,c.edition_id,c.is_locked,e.id event_id,e.title,o.id organization_id,o.name organization_name,ee.starts_at
from public.channels c join public.event_editions ee on ee.id=c.edition_id join public.events e on e.id=ee.event_id join public.organizations o on o.id=e.organization_id;
grant select on public.my_community_channels to authenticated;

create function public.update_profile_preferences(p_full_name text,p_college_id uuid,p_interests text[],p_notification_preferences jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null then raise sqlstate 'PGRST' using message='{"code":"AUTH_REQUIRED","message":"Sign in is required."}',detail='{"status":401}'; end if;
 if p_college_id is not null and not exists(select 1 from public.colleges where id=p_college_id) then raise sqlstate 'PGRST' using message='{"code":"INVALID_COLLEGE","message":"Choose an available college."}',detail='{"status":422}'; end if;
 update public.profiles set full_name=nullif(trim(p_full_name),''),college_id=p_college_id,interests=coalesce(p_interests,'{}'),notification_preferences=coalesce(p_notification_preferences,'{}'),updated_at=now() where id=actor;
 return jsonb_build_object('user_id',actor,'persisted',true);
end $$;

create function public.toggle_organization_follow(p_organization_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); following boolean;
begin
 if actor is null then raise sqlstate 'PGRST' using message='{"code":"AUTH_REQUIRED","message":"Sign in is required."}',detail='{"status":401}'; end if;
 if exists(select 1 from public.follows where user_id=actor and organization_id=p_organization_id) then delete from public.follows where user_id=actor and organization_id=p_organization_id; following:=false;
 else insert into public.follows(user_id,organization_id) values(actor,p_organization_id); following:=true; end if;
 return jsonb_build_object('organization_id',p_organization_id,'following',following,'persisted',true);
end $$;

create function public.request_account_deletion()
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();
begin
 if actor is null then raise sqlstate 'PGRST' using message='{"code":"AUTH_REQUIRED","message":"Sign in is required."}',detail='{"status":401}'; end if;
 update public.profiles set status='deleted',deletion_requested_at=now(),updated_at=now() where id=actor;
 update public.device_tokens set is_active=false where user_id=actor;
 insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'account.deletion_request','profile',actor);
 return jsonb_build_object('user_id',actor,'status','deletion_requested','signed_out_required',true);
end $$;

revoke all on function public.update_profile_preferences(text,uuid,text[],jsonb) from public,anon;
revoke all on function public.toggle_organization_follow(uuid) from public,anon;
revoke all on function public.request_account_deletion() from public,anon;
grant execute on function public.update_profile_preferences(text,uuid,text[],jsonb) to authenticated;
grant execute on function public.toggle_organization_follow(uuid) to authenticated;
grant execute on function public.request_account_deletion() to authenticated;
