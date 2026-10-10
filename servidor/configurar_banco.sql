-- Completa o banco do gasprice no servidor próprio (schema combustivel) com o que a cópia do schema não trouxe.
-- Pode ser rodado de novo sem estragar nada.
--
-- Uso, no servidor (os valores vêm de variáveis do psql, nunca ficam neste arquivo):
--   sudo docker exec -i supabase-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 \
--     -v project_url='http://kong:8000' -v cron_secret="$CRON_SECRET" < configurar_banco.sql
--
-- O que faz:
--   1. Gatilho em auth.users que cria o perfil de quem se cadastra (sem ele o app quebra no 1º login)
--   2. Buckets do Storage (avatares, anp-historico) e as políticas da foto de perfil
--   3. Tabela de notificações no Realtime (avisos de preço em tempo real)
--   4. Segredos do Vault usados pela tarefa que chama a Edge Function
--   5. pg_cron e as 4 tarefas agendadas do app

\set ON_ERROR_STOP on

-- 1. Perfil criado no cadastro ---------------------------------------------------------------------------------------
drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario
  after insert on auth.users
  for each row execute function combustivel.criar_perfil();

-- 2. Storage ---------------------------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatares', 'avatares', true, 204800, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('anp-historico', 'anp-historico', false)
on conflict (id) do nothing;

drop policy if exists "avatar publico" on storage.objects;
create policy "avatar publico" on storage.objects
  for select to anon, authenticated using (bucket_id = 'avatares');
drop policy if exists "envia o proprio avatar" on storage.objects;
create policy "envia o proprio avatar" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatares' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "troca o proprio avatar" on storage.objects;
create policy "troca o proprio avatar" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatares' and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists "apaga o proprio avatar" on storage.objects;
create policy "apaga o proprio avatar" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatares' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- 3. Realtime --------------------------------------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'combustivel' and tablename = 'notificacoes') then
    alter publication supabase_realtime add table combustivel.notificacoes;
  end if;
end $$;

-- 4. Vault -----------------------------------------------------------------------------------------------------------
-- project_url: dentro da rede do Docker a API é http://kong:8000 (o pg_net roda no container do banco)
select vault.create_secret(:'project_url', 'project_url')
where not exists (select 1 from vault.secrets where name = 'project_url');
select vault.update_secret(id, :'project_url') from vault.secrets where name = 'project_url';

select vault.create_secret(:'cron_secret', 'cron_secret')
where not exists (select 1 from vault.secrets where name = 'cron_secret');
select vault.update_secret(id, :'cron_secret') from vault.secrets where name = 'cron_secret';

-- 5. Tarefas agendadas (mesmos horários do Supabase da nuvem, em UTC) ------------------------------------------------
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule('gasprice-fechar-envios', '10 * * * *', $$select combustivel.fechar_envios_antigos()$$);
select cron.schedule('gasprice-municipios-anp', '30 4 * * 1', $$select combustivel.marcar_municipios_pesquisados()$$);
select cron.schedule('gasprice-estimativas', '0 5 * * 1',
  $$select combustivel.recalcular_estimativas(); select combustivel.recalcular_precos_atuais();$$);
select cron.schedule('gasprice-sincronizar-cadastro', '*/10 3-7 * * 0', $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/sincronizar-cadastro-anp',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000)
$$);

-- Conferência --------------------------------------------------------------------------------------------------------
select 'gatilho' as item, count(*)::text as valor from pg_trigger where tgname = 'ao_criar_usuario'
union all select 'buckets', string_agg(id, ', ' order by id) from storage.buckets
union all select 'politicas storage', count(*)::text from pg_policies where schemaname = 'storage' and tablename = 'objects'
union all select 'realtime', string_agg(schemaname || '.' || tablename, ', ') from pg_publication_tables where pubname = 'supabase_realtime'
union all select 'vault', string_agg(name, ', ' order by name) from vault.secrets
union all select 'cron', string_agg(jobname, ', ' order by jobname) from cron.job;
