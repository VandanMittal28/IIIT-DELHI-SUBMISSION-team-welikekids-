create function public.publish_floor(p_floor_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target record;
begin
 select f.*,c.college_id into target from public.floors f join public.buildings b on b.id=f.building_id join public.campuses c on c.id=b.campus_id where f.id=p_floor_id for update of f;
 if actor is null or target.id is null or not private.is_college_admin(target.college_id,actor) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"College administrator access is required."}',detail='{"status":403}'; end if;
 if target.floor_plan_path is null or target.meters_per_pixel is null or target.origin_latitude is null or target.origin_longitude is null then raise sqlstate 'PGRST' using message='{"code":"FLOOR_TRANSFORM_INCOMPLETE","message":"A floor plan, scale, and geographic origin are required before publishing."}',detail='{"status":422}'; end if;
 update public.floors set is_published=true where id=p_floor_id;
 insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'floor.publish','floor',p_floor_id);
 return jsonb_build_object('floor_id',p_floor_id,'is_published',true,'persisted',true);
end $$;
revoke all on function public.publish_floor(uuid) from public,anon;
grant execute on function public.publish_floor(uuid) to authenticated;
