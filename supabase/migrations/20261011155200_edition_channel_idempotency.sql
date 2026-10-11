create or replace function public.create_event_edition(
  p_event_id uuid, p_label text, p_registration_opens_at timestamptz,
  p_registration_closes_at timestamptz, p_starts_at timestamptz,
  p_ends_at timestamptz, p_capacity integer, p_waitlist_enabled boolean default true
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); saved uuid;
begin
  if actor is null or not private.can_manage_event(p_event_id,actor) then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer access is required."}',detail='{"status":403}';
  end if;
  insert into public.event_editions(event_id,label,registration_opens_at,registration_closes_at,starts_at,ends_at,capacity,waitlist_enabled)
  values(p_event_id,trim(p_label),p_registration_opens_at,p_registration_closes_at,p_starts_at,p_ends_at,p_capacity,p_waitlist_enabled)
  returning id into saved;
  insert into public.channels(edition_id) values(saved) on conflict(edition_id) do nothing;
  insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'edition.create','event_edition',saved);
  return jsonb_build_object('edition_id',saved,'persisted',true);
end $$;
revoke all on function public.create_event_edition(uuid,text,timestamptz,timestamptz,timestamptz,timestamptz,integer,boolean) from public,anon;
grant execute on function public.create_event_edition(uuid,text,timestamptz,timestamptz,timestamptz,timestamptz,integer,boolean) to authenticated;
