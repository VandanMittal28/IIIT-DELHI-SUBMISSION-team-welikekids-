create table public.notification_reminders (
  user_id uuid not null references public.profiles(id) on delete cascade,
  edition_id uuid not null references public.event_editions(id) on delete cascade,
  reminder_kind text not null check (reminder_kind in ('registration_closing','event_starting')),
  notification_id uuid unique references public.notifications(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id,edition_id,reminder_kind)
);

create index notification_reminders_edition_idx on public.notification_reminders(edition_id);
alter table public.notification_reminders enable row level security;
create policy notification_reminders_no_client_access on public.notification_reminders
  for all to anon,authenticated using(false) with check(false);
revoke all on table public.notification_reminders from public,anon,authenticated;

create or replace function private.enqueue_notification(
  target_user_id uuid,
  target_edition_id uuid,
  notification_kind text,
  notification_title text,
  notification_body text,
  notification_payload jsonb default '{}'::jsonb
)
returns uuid language plpgsql security definer set search_path='' as $$
declare created_id uuid; preference_key text; preference jsonb; push_enabled boolean:=true;
begin
  insert into public.notifications(user_id,edition_id,kind,title,body,payload)
  values(target_user_id,target_edition_id,notification_kind,notification_title,notification_body,notification_payload)
  returning id into created_id;

  preference_key:=case notification_kind
    when 'announcement' then 'announcements'
    when 'venue_change' then 'venue_changes'
    when 'reminder' then 'reminders'
    when 'report_status' then 'reports'
    else null
  end;
  if preference_key is not null then
    select notification_preferences->preference_key into preference
    from public.profiles where id=target_user_id;
    if jsonb_typeof(preference)='boolean' then push_enabled:=(preference#>>'{}')::boolean; end if;
  end if;

  if push_enabled then
    insert into public.notification_delivery_jobs(notification_id,device_token_id)
    select created_id,device.id from public.device_tokens device
    where device.user_id=target_user_id and device.is_active
    on conflict do nothing;
  end if;
  return created_id;
end $$;
revoke all on function private.enqueue_notification(uuid,uuid,text,text,text,jsonb) from public;

create or replace function public.publish_announcement(p_edition_id uuid,p_title text,p_body text,p_kind text default 'official')
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); created_id uuid; attendee record; notification_kind text;
begin
  if actor is null or not private.can_manage_edition(p_edition_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Event staff access is required."}',detail='{"status":403}'; end if;
  insert into public.announcements(edition_id,title,body,kind,created_by) values(p_edition_id,trim(p_title),trim(p_body),p_kind,actor) returning id into created_id;
  notification_kind:=case when p_kind in ('venue_change','closure') then 'venue_change' else 'announcement' end;
  for attendee in select user_id from public.registrations where edition_id=p_edition_id and status in ('registered','waitlisted') loop
    perform private.enqueue_notification(attendee.user_id,p_edition_id,notification_kind,p_title,p_body,jsonb_build_object('announcement_id',created_id));
  end loop;
  insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'announcement.publish','announcement',created_id);
  return jsonb_build_object('announcement_id',created_id,'persisted',true);
end $$;

create or replace function public.update_profile_preferences(p_full_name text,p_college_id uuid,p_interests text[],p_notification_preferences jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); normalized_preferences jsonb;
begin
 if actor is null then raise sqlstate 'PGRST' using message='{"code":"AUTH_REQUIRED","message":"Sign in is required."}',detail='{"status":401}'; end if;
 if p_college_id is not null and not exists(select 1 from public.colleges where id=p_college_id) then raise sqlstate 'PGRST' using message='{"code":"INVALID_COLLEGE","message":"Choose an available college."}',detail='{"status":422}'; end if;
 normalized_preferences:=coalesce(p_notification_preferences,'{}'::jsonb);
 if jsonb_typeof(normalized_preferences)<>'object' or exists(
   select 1 from jsonb_each(normalized_preferences) preference
   where preference.key not in ('announcements','venue_changes','reminders','reports') or jsonb_typeof(preference.value)<>'boolean'
 ) then raise sqlstate 'PGRST' using message='{"code":"INVALID_NOTIFICATION_PREFERENCES","message":"Notification preferences must use supported boolean values."}',detail='{"status":422}'; end if;
 normalized_preferences:='{"announcements":true,"venue_changes":true,"reminders":true,"reports":true}'::jsonb||normalized_preferences;
 update public.profiles set full_name=nullif(trim(p_full_name),''),college_id=p_college_id,interests=coalesce(p_interests,'{}'),notification_preferences=normalized_preferences,updated_at=now() where id=actor;
 return jsonb_build_object('user_id',actor,'persisted',true);
end $$;

create function public.enqueue_due_event_reminders(p_now timestamptz default clock_timestamp())
returns jsonb language plpgsql security definer set search_path='' as $$
declare candidate record; inserted boolean; created_notification uuid; enqueued integer:=0;
begin
  for candidate in
    select registration.user_id,edition.id edition_id,'event_starting' reminder_kind,event.id event_id,
      'Event starts soon' title,event.title||' starts within 24 hours. Check My Journey for the current time and venue.' body
    from public.registrations registration
    join public.event_editions edition on edition.id=registration.edition_id
    join public.events event on event.id=edition.event_id
    where registration.status='registered' and event.status='published' and edition.starts_at>p_now and edition.starts_at<=p_now+interval '24 hours'
    union all
    select saved.user_id,edition.id,'registration_closing',event.id,
      'Registration closes soon',event.title||' registration closes within 24 hours. Open Sidequest for the current deadline.'
    from public.saved_events saved
    join public.events event on event.id=saved.event_id
    join public.event_editions edition on edition.event_id=event.id
    where event.status='published' and edition.registration_closes_at>p_now and edition.registration_closes_at<=p_now+interval '24 hours'
      and not exists(select 1 from public.registrations registration where registration.edition_id=edition.id and registration.user_id=saved.user_id and registration.status in ('registered','waitlisted'))
  loop
    inserted:=false;
    insert into public.notification_reminders(user_id,edition_id,reminder_kind)
    values(candidate.user_id,candidate.edition_id,candidate.reminder_kind)
    on conflict do nothing returning true into inserted;
    if inserted then
      created_notification:=private.enqueue_notification(candidate.user_id,candidate.edition_id,'reminder',candidate.title,candidate.body,jsonb_build_object('event_id',candidate.event_id,'edition_id',candidate.edition_id,'reminder_kind',candidate.reminder_kind));
      update public.notification_reminders set notification_id=created_notification
      where user_id=candidate.user_id and edition_id=candidate.edition_id and reminder_kind=candidate.reminder_kind;
      enqueued:=enqueued+1;
    end if;
  end loop;
  return jsonb_build_object('enqueued',enqueued,'evaluated_at',p_now);
end $$;

revoke all on function public.enqueue_due_event_reminders(timestamptz) from public,anon,authenticated;
grant execute on function public.enqueue_due_event_reminders(timestamptz) to service_role;
