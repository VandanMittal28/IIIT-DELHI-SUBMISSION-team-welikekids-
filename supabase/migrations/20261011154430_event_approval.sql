create function public.approve_event(p_event_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target public.events;
begin
 select * into target from public.events where id=p_event_id for update;
 if actor is null or target.id is null or not private.is_college_admin(target.college_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}'; end if;
 if target.status<>'pending_approval' then raise sqlstate 'PGRST' using message='{"code":"INVALID_EVENT_STATE","message":"Only events pending approval can be approved."}',detail='{"status":409}'; end if;
 update public.events set status='published',published_at=now(),updated_at=now() where id=p_event_id;
 insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'event.approve','event',p_event_id);
 return jsonb_build_object('event_id',p_event_id,'status','published','persisted',true);
end $$;
revoke all on function public.approve_event(uuid) from public,anon;
grant execute on function public.approve_event(uuid) to authenticated;
