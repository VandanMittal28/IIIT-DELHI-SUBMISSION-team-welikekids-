create function public.claim_notification_jobs(p_limit integer default 25)
returns table(job_id uuid,device_token text,notification_title text,notification_body text,notification_payload jsonb,attempt_number integer)
language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'service role required'; end if;
 return query
 with candidates as (
   select j.id from public.notification_delivery_jobs j
   where j.status in ('pending','failed') and j.next_attempt_at<=now() and j.attempts<8
   order by j.next_attempt_at,j.created_at for update skip locked limit greatest(1,least(p_limit,100))
 ), claimed as (
   update public.notification_delivery_jobs j set status='processing',attempts=j.attempts+1
   from candidates c where j.id=c.id returning j.*
 )
 select c.id,d.token,n.title,n.body,n.payload,c.attempts
 from claimed c join public.device_tokens d on d.id=c.device_token_id and d.is_active
 join public.notifications n on n.id=c.notification_id;
end $$;

create function public.complete_notification_job(p_job_id uuid,p_delivered boolean,p_error text default null)
returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' then raise exception 'service role required'; end if;
 update public.notification_delivery_jobs set
   status=case when p_delivered then 'delivered'::public.notification_status else 'failed'::public.notification_status end,
   delivered_at=case when p_delivered then now() else null end,
   last_error=case when p_delivered then null else left(coalesce(p_error,'Unknown APNs error'),1000) end,
   next_attempt_at=case when p_delivered then next_attempt_at else now()+(interval '30 seconds'*power(2,least(attempts,7))) end
 where id=p_job_id and status='processing';
end $$;

revoke all on function public.claim_notification_jobs(integer) from public,anon,authenticated;
revoke all on function public.complete_notification_job(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.claim_notification_jobs(integer) to service_role;
grant execute on function public.complete_notification_job(uuid,boolean,text) to service_role;
