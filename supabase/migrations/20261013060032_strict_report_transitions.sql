create or replace function public.transition_report(p_report_id uuid,p_status public.report_status,p_assignee_id uuid default null,p_note text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target public.reports;
begin
 select * into target from public.reports where id=p_report_id for update;
 if actor is null or target.id is null or not private.can_manage_edition(target.edition_id,actor) then
   raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Assigned event staff access is required."}',detail='{"status":403}';
 end if;
 if target.status=p_status then
   return jsonb_build_object('report_id',p_report_id,'status',p_status,'persisted',true,'idempotent_replay',true);
 end if;
 if (target.status='submitted' and p_status<>'acknowledged')
   or (target.status='acknowledged' and p_status<>'assigned')
   or (target.status='assigned' and p_status<>'in_progress')
   or (target.status='in_progress' and p_status<>'resolved')
   or target.status='resolved' then
   raise sqlstate 'PGRST' using message='{"code":"INVALID_REPORT_TRANSITION","message":"Use submitted, acknowledged, assigned, in progress, and resolved in order."}',detail='{"status":409}';
 end if;
 if p_status='assigned' and (
   p_assignee_id is null or not exists(
     select 1 from public.event_staff_assignments assignment
     join public.profiles profile on profile.id=assignment.user_id
     where assignment.edition_id=target.edition_id and assignment.user_id=p_assignee_id and profile.status='active'
   )
 ) then
   raise sqlstate 'PGRST' using message='{"code":"INVALID_ASSIGNEE","message":"Choose active staff assigned to this event edition."}',detail='{"status":422}';
 end if;

 update public.reports set status=p_status,updated_at=now(),resolved_at=case when p_status='resolved' then now() else resolved_at end where id=p_report_id;
 if p_status='assigned' then
   insert into public.report_assignments(report_id,assignee_id,assigned_by)
   values(p_report_id,p_assignee_id,actor) on conflict do nothing;
 end if;
 insert into public.report_status_history(report_id,from_status,to_status,changed_by,note)
 values(p_report_id,target.status,p_status,actor,nullif(trim(p_note),''));
 perform private.enqueue_notification(target.reporter_id,target.edition_id,'report_status','Report updated','Your report is now '||replace(p_status::text,'_',' ')||'.',jsonb_build_object('report_id',p_report_id));
 return jsonb_build_object('report_id',p_report_id,'status',p_status,'persisted',true,'idempotent_replay',false);
end $$;

revoke all on function public.transition_report(uuid,public.report_status,uuid,text) from public,anon;
grant execute on function public.transition_report(uuid,public.report_status,uuid,text) to authenticated;
