create or replace function public.request_account_deletion()
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); target_registration record;
begin
 if actor is null then raise sqlstate 'PGRST' using message='{"code":"AUTH_REQUIRED","message":"Sign in is required."}',detail='{"status":401}'; end if;
 for target_registration in select id from public.registrations where user_id=actor and status<>'cancelled' for update loop
   perform public.cancel_registration(target_registration.id);
 end loop;
 update public.memberships set status='revoked',updated_at=now() where user_id=actor;
 update public.college_memberships set status='revoked',updated_at=now() where user_id=actor;
 update public.device_tokens set is_active=false where user_id=actor;
 delete from public.follows where user_id=actor;
 delete from public.saved_events where user_id=actor;
 update public.profiles set status='deleted',deletion_requested_at=now(),updated_at=now() where id=actor;
 insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'account.deletion_request','profile',actor);
 return jsonb_build_object('user_id',actor,'status','deletion_requested','access_revoked',true,'signed_out_required',true);
end $$;
revoke all on function public.request_account_deletion() from public,anon;
grant execute on function public.request_account_deletion() to authenticated;
