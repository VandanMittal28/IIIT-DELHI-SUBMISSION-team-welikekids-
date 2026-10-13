-- College creation is a Sidequest platform operation. College admins may
-- continue managing only colleges for which they already have membership.
create or replace function public.create_college(
  p_name text,
  p_slug text,
  p_timezone text default 'Asia/Kolkata'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  saved uuid;
  normalized_name text := trim(coalesce(p_name, ''));
  normalized_slug text := lower(trim(coalesce(p_slug, '')));
  normalized_timezone text := trim(coalesce(p_timezone, 'Asia/Kolkata'));
begin
  if actor is null or not private.is_platform_admin(actor) then
    raise sqlstate 'PGRST' using
      message = '{"code":"FORBIDDEN","message":"Sidequest platform administrator access is required."}',
      detail = '{"status":403}';
  end if;

  if length(normalized_name) not between 2 and 160
     or normalized_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
     or not exists (select 1 from pg_catalog.pg_timezone_names where name = normalized_timezone) then
    raise sqlstate 'PGRST' using
      message = '{"code":"INVALID_INPUT","message":"Enter a college name, a lowercase hyphenated ID, and a valid timezone."}',
      detail = '{"status":422}';
  end if;

  insert into public.colleges(name, slug, timezone)
  values (normalized_name, normalized_slug, normalized_timezone)
  returning id into saved;

  insert into public.audit_records(actor_id, action, entity_type, entity_id, detail)
  values (actor, 'college.create', 'college', saved,
    jsonb_build_object('name', normalized_name, 'slug', normalized_slug));

  return jsonb_build_object('college_id', saved, 'persisted', true);
end;
$$;

revoke all on function public.create_college(text, text, text) from public, anon;
grant execute on function public.create_college(text, text, text) to authenticated;
