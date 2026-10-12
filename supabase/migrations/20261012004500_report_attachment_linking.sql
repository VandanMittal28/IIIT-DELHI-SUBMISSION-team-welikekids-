create unique index report_attachments_report_path_idx
  on public.report_attachments(report_id, storage_path);

create function public.add_report_attachment(p_report_id uuid, p_storage_path text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  actor uuid:=auth.uid();
  target public.reports;
  object_owner text;
  saved uuid;
  created boolean:=false;
  expected_prefix text;
begin
  select * into target from public.reports where id=p_report_id;
  if actor is null or target.id is null or target.reporter_id<>actor then
    raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Only the report author can add evidence."}',detail='{"status":403}';
  end if;

  expected_prefix:=actor::text||'/'||p_report_id::text||'/';
  if p_storage_path is null or position(expected_prefix in p_storage_path)<>1 then
    raise sqlstate 'PGRST' using message='{"code":"INVALID_MEDIA_PATH","message":"The attachment path does not belong to this report."}',detail='{"status":422}';
  end if;

  select o.owner_id into object_owner
  from storage.objects o
  where o.bucket_id='report-attachments' and o.name=p_storage_path;
  if object_owner is null or object_owner<>actor::text then
    raise sqlstate 'PGRST' using message='{"code":"ATTACHMENT_NOT_FOUND","message":"Upload the attachment before linking it."}',detail='{"status":422}';
  end if;

  insert into public.report_attachments(report_id,storage_path,uploaded_by)
  values(p_report_id,p_storage_path,actor)
  on conflict(report_id,storage_path) do nothing
  returning id into saved;
  if saved is null then
    select id into saved
    from public.report_attachments
    where report_id=p_report_id and storage_path=p_storage_path;
  else
    created:=true;
    insert into public.audit_records(actor_id,action,entity_type,entity_id,detail)
    values(actor,'report.attachment','report_attachment',saved,jsonb_build_object('report_id',p_report_id,'path',p_storage_path));
  end if;
  return jsonb_build_object('attachment_id',saved,'persisted',true,'created',created);
end $$;

revoke all on function public.add_report_attachment(uuid,text) from public,anon;
grant execute on function public.add_report_attachment(uuid,text) to authenticated;

create policy reporter_unlinked_attachment_delete on storage.objects for delete to authenticated
using (
  bucket_id='report-attachments'
  and owner_id=(select auth.uid()::text)
  and not exists (
    select 1 from public.report_attachments attachment
    where attachment.storage_path=storage.objects.name
  )
);
