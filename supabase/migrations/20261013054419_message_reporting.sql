alter table public.reports
  add column reported_message_id uuid references public.messages(id) on delete restrict;

create unique index reports_reporter_message_unique_idx
  on public.reports(reporter_id,reported_message_id)
  where reported_message_id is not null;
create index reports_reported_message_idx
  on public.reports(reported_message_id)
  where reported_message_id is not null;

drop policy messages_read on public.messages;
create policy messages_read on public.messages for select to authenticated using (
  exists (
    select 1 from public.channels channel
    where channel.id=channel_id
      and (
        (status='visible' and private.can_access_edition(channel.edition_id))
        or private.can_manage_edition(channel.edition_id)
      )
  )
);

create function public.submit_message_report(p_message_id uuid,p_description text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target record; saved_id uuid; created boolean:=false;
begin
 select message.id,message.author_id,message.status,channel.edition_id
 into target
 from public.messages message
 join public.channels channel on channel.id=message.channel_id
 where message.id=p_message_id;
 if actor is null or target.id is null or not private.can_access_edition(target.edition_id,actor) then
   raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"This discussion message is unavailable."}',detail='{"status":403}';
 end if;
 select id into saved_id from public.reports where reporter_id=actor and reported_message_id=target.id;
 if saved_id is not null then
   return jsonb_build_object('report_id',saved_id,'status','submitted','persisted',true,'idempotent_replay',true);
 end if;
 if target.status<>'visible' then
   raise sqlstate 'PGRST' using message='{"code":"MESSAGE_UNAVAILABLE","message":"This discussion message is no longer visible."}',detail='{"status":409}';
 end if;
 if target.author_id=actor then
   raise sqlstate 'PGRST' using message='{"code":"INVALID_REPORT","message":"You cannot report your own message."}',detail='{"status":422}';
 end if;
 if length(trim(p_description))<5 then
   raise sqlstate 'PGRST' using message='{"code":"INVALID_REPORT","message":"Tell moderators why this message should be reviewed."}',detail='{"status":422}';
 end if;

 insert into public.reports(edition_id,reporter_id,category,description,priority,reported_message_id)
 values(target.edition_id,actor,'Discussion message',trim(p_description),'normal',target.id)
 on conflict(reporter_id,reported_message_id) where reported_message_id is not null do nothing
 returning id into saved_id;
 if saved_id is null then
   select id into saved_id from public.reports where reporter_id=actor and reported_message_id=target.id;
 else
   created:=true;
   insert into public.report_status_history(report_id,to_status,changed_by) values(saved_id,'submitted',actor);
 end if;
 return jsonb_build_object('report_id',saved_id,'status','submitted','persisted',true,'idempotent_replay',not created);
end $$;

revoke all on function public.submit_message_report(uuid,text) from public,anon;
grant execute on function public.submit_message_report(uuid,text) to authenticated;
