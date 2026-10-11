-- Minimal local-only Supabase surface for running migrations with PostgreSQL 17.
-- This is not deployed and contains no operational fixtures.
create role anon noinherit;
create role authenticated noinherit;
create role service_role noinherit;
create schema auth;
create schema extensions;
create schema storage;
create extension pgcrypto with schema extensions;
create table auth.users(id uuid primary key, email text, raw_user_meta_data jsonb not null default '{}');
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.role() returns text language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.role',true),''),current_user) $$;
create table storage.buckets(id text primary key,name text not null,public boolean not null default false,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default extensions.gen_random_uuid(),bucket_id text not null references storage.buckets(id),name text not null,owner_id text);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$ select string_to_array(regexp_replace(name,'/[^/]+$',''),'/') $$;
create publication supabase_realtime;
