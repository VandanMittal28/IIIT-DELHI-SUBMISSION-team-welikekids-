alter table public.notification_delivery_jobs
  add column locked_at timestamptz,
  add column terminal_failure boolean not null default false;

update public.notification_delivery_jobs
set status='failed',terminal_failure=true,locked_at=null,last_error=coalesce(last_error,'Retry limit reached')
where attempts>=8 and status<>'delivered';

create index notification_delivery_processing_lease_idx
  on public.notification_delivery_jobs(locked_at)
  where status='processing';

drop function public.claim_notification_jobs(integer);

create function public.claim_notification_jobs(p_limit integer default 25)
returns table(job_id uuid,device_token text,device_environment text,notification_title text,notification_body text,notification_payload jsonb,attempt_number integer)
language plpgsql security definer set search_path='' as $$
begin
 update public.notification_delivery_jobs job
 set status='failed',terminal_failure=true,locked_at=null,last_error='Device token is inactive'
 from public.device_tokens device
 where job.device_token_id=device.id
   and not device.is_active
   and not job.terminal_failure
   and job.status in ('pending','failed','processing');

 return query
 with candidates as (
   select job.id
   from public.notification_delivery_jobs job
   join public.device_tokens device on device.id=job.device_token_id and device.is_active
   where not job.terminal_failure
     and job.attempts<8
     and (
       (job.status in ('pending','failed') and job.next_attempt_at<=clock_timestamp())
       or (job.status='processing' and (job.locked_at is null or job.locked_at<=clock_timestamp()-interval '5 minutes'))
     )
   order by job.next_attempt_at,job.created_at
   for update of job skip locked
   limit greatest(1,least(coalesce(p_limit,25),100))
 ), claimed as (
   update public.notification_delivery_jobs job
   set status='processing',attempts=job.attempts+1,locked_at=clock_timestamp(),next_attempt_at=clock_timestamp()+interval '5 minutes'
   from candidates candidate
   where job.id=candidate.id
   returning job.*
 )
 select claimed.id,device.token,device.environment,notification.title,notification.body,notification.payload,claimed.attempts
 from claimed
 join public.device_tokens device on device.id=claimed.device_token_id
 join public.notifications notification on notification.id=claimed.notification_id;
end $$;

drop function public.complete_notification_job(uuid,boolean,text);

create function public.complete_notification_job(
  p_job_id uuid,
  p_attempt_number integer,
  p_delivered boolean,
  p_terminal boolean default false,
  p_deactivate_device boolean default false,
  p_error text default null
)
returns jsonb language plpgsql security definer set search_path='' as $$
declare affected_device uuid;
begin
 update public.notification_delivery_jobs
 set
   status=case when p_delivered then 'delivered'::public.notification_status else 'failed'::public.notification_status end,
   delivered_at=case when p_delivered then clock_timestamp() else null end,
   last_error=case when p_delivered then null else left(coalesce(p_error,'Unknown APNs error'),1000) end,
   terminal_failure=case when p_delivered then false else p_terminal or attempts>=8 end,
   locked_at=null,
   next_attempt_at=case
     when p_delivered or p_terminal or attempts>=8 then next_attempt_at
     else clock_timestamp()+(interval '30 seconds'*power(2,least(attempts,7)))
   end
 where id=p_job_id and status='processing' and attempts=p_attempt_number
 returning device_token_id into affected_device;

 if affected_device is null then
   return jsonb_build_object('persisted',false,'stale_attempt',true);
 end if;
 if not p_delivered and p_terminal and p_deactivate_device then
   update public.device_tokens set is_active=false where id=affected_device;
 end if;
 return jsonb_build_object('persisted',true,'stale_attempt',false);
end $$;

revoke all on function public.claim_notification_jobs(integer) from public,anon,authenticated;
revoke all on function public.complete_notification_job(uuid,integer,boolean,boolean,boolean,text) from public,anon,authenticated;
grant execute on function public.claim_notification_jobs(integer) to service_role;
grant execute on function public.complete_notification_job(uuid,integer,boolean,boolean,boolean,text) to service_role;
