create type public.invitation_status as enum('pending','accepted','revoked','expired');
create table public.organization_role_invitations(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  email text not null check(email=lower(email)),
  role public.membership_role not null,
  token_hash text not null unique,
  status public.invitation_status not null default 'pending',
  invited_by uuid not null references public.profiles(id) on delete restrict,
  expires_at timestamptz not null,
  accepted_by uuid references public.profiles(id) on delete set null,
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);
create index organization_role_invitations_org_status_idx on public.organization_role_invitations(organization_id,status);
create index organization_role_invitations_email_status_idx on public.organization_role_invitations(email,status);
alter table public.organization_role_invitations enable row level security;
create policy organization_role_invitations_no_direct_access on public.organization_role_invitations for all to anon,authenticated using(false) with check(false);

create function public.create_role_invitation(p_organization_id uuid,p_email text,p_role public.membership_role)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); raw_token uuid:=gen_random_uuid(); saved uuid;
begin
  if actor is null or p_role not in ('member','event_volunteer','organizer') or not exists(
    select 1 from public.organizations o where o.id=p_organization_id and (private.is_college_admin(o.college_id,actor) or private.has_organization_role(o.id,array['organizer']::public.membership_role[],actor))
  ) then raise sqlstate 'PGRST' using message='{"code":"FORBIDDEN","message":"Organizer access and a valid invited role are required."}',detail='{"status":403}'; end if;
  update public.organization_role_invitations set status='revoked' where organization_id=p_organization_id and email=lower(trim(p_email)) and role=p_role and status='pending';
  insert into public.organization_role_invitations(organization_id,email,role,token_hash,invited_by,expires_at)
  values(p_organization_id,lower(trim(p_email)),p_role,encode(extensions.digest(raw_token::text,'sha256'),'hex'),actor,now()+interval '7 days') returning id into saved;
  insert into public.audit_records(actor_id,action,entity_type,entity_id,detail) values(actor,'role.invite','organization_role_invitation',saved,jsonb_build_object('organization_id',p_organization_id,'role',p_role));
  return jsonb_build_object('invitation_id',saved,'invitation_token',raw_token,'expires_at',now()+interval '7 days','persisted',true);
end $$;

create function public.accept_role_invitation(p_token uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); actor_email text; target public.organization_role_invitations;
begin
  if actor is null then raise sqlstate 'PGRST' using message='{"code":"AUTH_REQUIRED","message":"Sign in is required."}',detail='{"status":401}'; end if;
  select lower(email) into actor_email from auth.users where id=actor;
  select * into target from public.organization_role_invitations where token_hash=encode(extensions.digest(p_token::text,'sha256'),'hex') for update;
  if target.id is null or target.status<>'pending' or target.expires_at<=now() then raise sqlstate 'PGRST' using message='{"code":"INVITATION_UNAVAILABLE","message":"This invitation is invalid, expired, or already used."}',detail='{"status":409}'; end if;
  if actor_email is null or actor_email<>target.email then raise sqlstate 'PGRST' using message='{"code":"INVITATION_EMAIL_MISMATCH","message":"Sign in with the email address that was invited."}',detail='{"status":403}'; end if;
  insert into public.memberships(organization_id,user_id,role,status,invited_by) values(target.organization_id,actor,target.role,'active',target.invited_by)
  on conflict(organization_id,user_id,role) do update set status='active',invited_by=excluded.invited_by;
  update public.organization_role_invitations set status='accepted',accepted_by=actor,accepted_at=now() where id=target.id;
  insert into public.audit_records(actor_id,action,entity_type,entity_id) values(actor,'role.invite_accept','organization_role_invitation',target.id);
  return jsonb_build_object('organization_id',target.organization_id,'role',target.role,'persisted',true);
end $$;

revoke all on function public.create_role_invitation(uuid,text,public.membership_role) from public,anon;
revoke all on function public.accept_role_invitation(uuid) from public,anon;
grant execute on function public.create_role_invitation(uuid,text,public.membership_role) to authenticated;
grant execute on function public.accept_role_invitation(uuid) to authenticated;
