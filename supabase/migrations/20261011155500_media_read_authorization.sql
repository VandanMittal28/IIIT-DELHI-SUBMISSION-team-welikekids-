-- Replace the original broad authenticated media read rule with object-level authorization.
drop policy if exists "authenticated_media_read" on storage.objects;

create policy event_media_published_read on storage.objects for select to anon
using (
  bucket_id='event-media'
  and exists (
    select 1 from public.events e
    where e.college_id::text=(storage.foldername(name))[1]
      and e.id::text=(storage.foldername(name))[2]
      and e.status='published'
  )
);

create policy event_media_authenticated_read on storage.objects for select to authenticated
using (
  bucket_id='event-media'
  and exists (
    select 1 from public.events e
    where e.college_id::text=(storage.foldername(name))[1]
      and e.id::text=(storage.foldername(name))[2]
      and (e.status='published' or private.can_manage_event(e.id))
  )
);

create policy campus_media_admin_read on storage.objects for select to authenticated
using (
  bucket_id='campus-media'
  and private.is_college_admin(((storage.foldername(name))[1])::uuid)
);

create policy report_attachment_scoped_read on storage.objects for select to authenticated
using (
  bucket_id='report-attachments'
  and (
    owner_id=(select auth.uid()::text)
    or exists (
      select 1
      from public.report_attachments attachment
      join public.reports report on report.id=attachment.report_id
      where attachment.storage_path=name
        and ((select auth.uid())=report.reporter_id or private.can_manage_edition(report.edition_id))
    )
  )
);
