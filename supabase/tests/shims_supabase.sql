-- Simula, num Postgres local comum, as partes que o Supabase já traz prontas.
-- Usado só para testar as migrações fora do Supabase (scripts/supabase/testar_banco_local.ps1).
-- NÃO rodar no projeto do Supabase.

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
grant anon, authenticated, service_role to postgres;

create schema extensions;
create schema auth;
create schema storage;
create schema vault;
create schema cron;
create schema net;
grant usage on schema public, extensions, auth, storage to anon, authenticated, service_role;

-- Privilégios padrão do Supabase: tudo liberado por grant, restringido pela RLS
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;

-- auth
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb default '{}'::jsonb,
  email_confirmed_at timestamptz
);

create function auth.uid() returns uuid language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;
grant execute on function auth.uid() to anon, authenticated, service_role;

-- storage
create table storage.buckets (
  id text primary key,
  name text not null,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name text,
  owner uuid
);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;

-- vault, pg_cron e pg_net (versões mínimas só para as migrações rodarem)
create view vault.decrypted_secrets as select null::text as name, null::text as decrypted_secret where false;
create table cron.job (jobname text primary key, schedule text, command text);
create function cron.schedule(p_nome text, p_agenda text, p_comando text) returns bigint language sql as $$
  insert into cron.job values (p_nome, p_agenda, p_comando)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command;
  select 1::bigint
$$;
create function net.http_post(url text, headers jsonb default '{}', body jsonb default '{}',
                              timeout_milliseconds int default 5000) returns bigint
language sql as $$ select 1::bigint $$;

create publication supabase_realtime;
