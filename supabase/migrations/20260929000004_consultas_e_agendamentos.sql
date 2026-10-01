-- gasprice · consultas usadas pelo app (RPC), importação do cadastro ANP e tarefas agendadas

-- "Carla Mendes" -> "Carla M."  (nunca expõe nome completo nem e-mail)
create or replace function public.abreviar_nome(p_nome text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_nome is null then 'Usuário removido'
    when position(' ' in trim(p_nome)) = 0 then trim(p_nome)
    else split_part(trim(p_nome), ' ', 1) || ' ' ||
         upper(left(split_part(trim(p_nome), ' ', array_length(string_to_array(trim(p_nome), ' '), 1)), 1)) || '.'
  end
$$;

-- Preços atuais de um posto em JSON (usado por várias consultas)
create or replace function public.precos_json(p_posto bigint)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'produto_id', a.produto_id, 'preco', a.preco, 'fonte', a.fonte, 'situacao', a.situacao,
           'atualizado_em', a.atualizado_em, 'confirmacoes', a.confirmacoes,
           'margem', a.margem, 'distancia_km', a.distancia_km) order by pr.ordem), '[]'::jsonb)
  from public.precos_atuais a
  join public.produtos pr on pr.id = a.produto_id
  where a.posto_id = p_posto
$$;

-- ---------------------------------------------------------------------------
-- Mapa: postos dentro da área visível
-- ---------------------------------------------------------------------------
create or replace function public.postos_na_area(
  p_lat_min double precision, p_lon_min double precision,
  p_lat_max double precision, p_lon_max double precision,
  p_limite integer default 300)
returns table (
  id bigint, nome text, bandeira text, endereco text, bairro text, municipio text, uf char(2),
  lat double precision, lon double precision, nota_media numeric, total_avaliacoes integer,
  municipio_pesquisado_anp boolean, precos jsonb)
language sql
stable
set search_path = public, extensions
as $$
  select p.id, coalesce(p.nome_exibicao, p.razao_social), p.bandeira, p.endereco, p.bairro, p.municipio, p.uf,
         st_y(p.localizacao::geometry), st_x(p.localizacao::geometry),
         p.nota_media, p.total_avaliacoes, p.municipio_pesquisado_anp, public.precos_json(p.id)
  from public.postos p
  where p.ativo
    and p.localizacao && st_makeenvelope(p_lon_min, p_lat_min, p_lon_max, p_lat_max, 4326)::geography
  order by p.total_avaliacoes desc, p.id
  limit least(p_limite, 500)
$$;

-- Lista: postos mais próximos de um ponto
create or replace function public.postos_proximos(
  p_lat double precision, p_lon double precision, p_raio_km double precision default 20, p_limite integer default 200)
returns table (
  id bigint, nome text, bandeira text, endereco text, bairro text, municipio text, uf char(2),
  lat double precision, lon double precision, nota_media numeric, total_avaliacoes integer,
  municipio_pesquisado_anp boolean, precos jsonb, distancia_km double precision)
language sql
stable
set search_path = public, extensions
as $$
  select p.id, coalesce(p.nome_exibicao, p.razao_social), p.bandeira, p.endereco, p.bairro, p.municipio, p.uf,
         st_y(p.localizacao::geometry), st_x(p.localizacao::geometry),
         p.nota_media, p.total_avaliacoes, p.municipio_pesquisado_anp, public.precos_json(p.id),
         st_distance(p.localizacao, st_makepoint(p_lon, p_lat)::geography) / 1000
  from public.postos p
  where p.ativo
    and st_dwithin(p.localizacao, st_makepoint(p_lon, p_lat)::geography, least(p_raio_km, 100) * 1000)
  order by p.localizacao <-> st_makepoint(p_lon, p_lat)::geography
  limit least(p_limite, 500)
$$;

-- Busca por nome, endereço, bairro, cidade ou UF (todas as palavras precisam aparecer)
create or replace function public.buscar_postos(
  p_texto text, p_lat double precision default null, p_lon double precision default null, p_limite integer default 40)
returns table (
  id bigint, nome text, bandeira text, endereco text, bairro text, municipio text, uf char(2),
  lat double precision, lon double precision, nota_media numeric, total_avaliacoes integer,
  municipio_pesquisado_anp boolean, precos jsonb, distancia_km double precision)
language sql
stable
set search_path = public, extensions
as $$
  with termos as (
    select array_remove(string_to_array(public.normalizar(trim(p_texto)), ' '), '') as palavras
  )
  select p.id, coalesce(p.nome_exibicao, p.razao_social), p.bandeira, p.endereco, p.bairro, p.municipio, p.uf,
         st_y(p.localizacao::geometry), st_x(p.localizacao::geometry),
         p.nota_media, p.total_avaliacoes, p.municipio_pesquisado_anp, public.precos_json(p.id),
         case when p_lat is null or p.localizacao is null then null
              else st_distance(p.localizacao, st_makepoint(p_lon, p_lat)::geography) / 1000 end
  from public.postos p, termos t
  where p.ativo
    and char_length(trim(p_texto)) >= 2
    and not exists (select 1 from unnest(t.palavras) w where p.texto_busca not like '%' || w || '%')
  order by case when p_lat is null or p.localizacao is null then 0
                else st_distance(p.localizacao, st_makepoint(p_lon, p_lat)::geography) end,
           p.total_avaliacoes desc
  limit least(p_limite, 100)
$$;

-- ---------------------------------------------------------------------------
-- Detalhe do posto
-- ---------------------------------------------------------------------------
create or replace function public.detalhe_posto(p_id bigint)
returns jsonb
language sql
stable
security definer
set search_path = public, extensions
as $$
  select jsonb_build_object(
    'id', p.id, 'cnpj', p.cnpj, 'nome', coalesce(p.nome_exibicao, p.razao_social),
    'razao_social', p.razao_social, 'bandeira', p.bandeira,
    'endereco', p.endereco, 'complemento', p.complemento, 'bairro', p.bairro,
    'municipio', p.municipio, 'uf', p.uf, 'cep', p.cep,
    'lat', st_y(p.localizacao::geometry), 'lon', st_x(p.localizacao::geometry),
    'localizacao_validada', p.localizacao_validada,
    'municipio_pesquisado_anp', p.municipio_pesquisado_anp,
    'nota_media', p.nota_media, 'total_avaliacoes', p.total_avaliacoes,
    'sincronizado_em', p.sincronizado_em,
    'produtos', (select coalesce(jsonb_agg(pp.produto_id order by pr.ordem), '[]'::jsonb)
                   from posto_produtos pp join produtos pr on pr.id = pp.produto_id where pp.posto_id = p.id),
    'precos', public.precos_json(p.id),
    'distribuicao_notas', (select jsonb_object_agg(n::text, (select count(*) from avaliacoes a where a.posto_id = p.id and a.nota = n))
                             from generate_series(0, 5) n),
    'envios_aguardando', (select coalesce(jsonb_object_agg(x.produto_id::text, x.qtd), '{}'::jsonb) from (
                            select i.produto_id, count(distinct i.usuario_id) as qtd from envio_itens i
                            where i.posto_id = p.id and i.status = 'pendente' group by i.produto_id) x),
    'favorito', exists (select 1 from favoritos f where f.posto_id = p.id and f.usuario_id = auth.uid()),
    'minha_avaliacao', (select jsonb_build_object('id', a.id, 'nota', a.nota, 'comentario', a.comentario)
                          from avaliacoes a where a.posto_id = p.id and a.usuario_id = auth.uid())
  )
  from public.postos p
  where p.id = p_id and p.ativo
$$;

-- Histórico: ANP (semanal) + comunidade (diário), identificando a origem
create or replace function public.historico_precos(p_posto bigint, p_produto smallint, p_dias integer default 180)
returns table (dia date, preco numeric, fonte text, confirmado boolean)
language sql
stable
set search_path = ''
as $$
  select a.data_coleta, a.preco, 'anp', true
  from public.precos_anp a
  where a.posto_id = p_posto and a.produto_id = p_produto and not a.anomalia
    and a.data_coleta >= current_date - least(p_dias, 730)
  union all
  select c.dia, c.preco, 'comunidade', c.confirmado
  from public.precos_comunidade c
  where c.posto_id = p_posto and c.produto_id = p_produto
    and c.dia >= current_date - least(p_dias, 730)
  order by 1
$$;

-- Contribuições recentes de um combustível (tela "Contribuições")
create or replace function public.contribuicoes(p_posto bigint, p_produto smallint)
returns table (item_id bigint, autor text, sou_eu boolean, preco numeric, status public.status_envio,
               editado boolean, criado_em timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select i.id, public.abreviar_nome(u.nome), i.usuario_id = auth.uid(), i.preco, i.status, i.editado, i.criado_em
  from public.envio_itens i
  left join public.perfis u on u.id = i.usuario_id
  where i.posto_id = p_posto and i.produto_id = p_produto
    and i.criado_em >= now() - interval '7 days'
    and i.status <> 'rejeitado'
  order by i.criado_em desc
  limit 50
$$;

-- Avaliações de um posto: 'recentes' ou 'relevantes' (mais votos úteis)
create or replace function public.avaliacoes_posto(
  p_posto bigint, p_ordem text default 'recentes', p_limite integer default 20, p_offset integer default 0)
returns table (id bigint, autor text, nota smallint, comentario text, votos_uteis integer,
               criado_em timestamptz, atualizado_em timestamptz, minha boolean, votei boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select a.id, public.abreviar_nome(u.nome), a.nota, a.comentario, a.votos_uteis, a.criado_em, a.atualizado_em,
         a.usuario_id = auth.uid(),
         exists (select 1 from public.avaliacao_votos v where v.avaliacao_id = a.id and v.usuario_id = auth.uid())
  from public.avaliacoes a
  join public.perfis u on u.id = a.usuario_id
  where a.posto_id = p_posto
  order by case when p_ordem = 'relevantes' then a.votos_uteis end desc nulls last, a.criado_em desc
  limit least(p_limite, 50) offset greatest(p_offset, 0)
$$;

-- Resumo do perfil do usuário logado
create or replace function public.meu_resumo()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', u.id, 'nome', u.nome, 'avatar_url', u.avatar_url, 'pontos', u.pontos,
    'confiabilidade', u.confiabilidade, 'bloqueado_ate', u.bloqueado_ate,
    'notificacoes_ativas', u.notificacoes_ativas, 'criado_em', u.criado_em,
    'total_avaliacoes', (select count(*) from public.avaliacoes a where a.usuario_id = u.id),
    'total_envios', (select count(*) from public.envio_itens i where i.usuario_id = u.id),
    'envios_confirmados', (select count(*) from public.envio_itens i where i.usuario_id = u.id and i.status = 'confirmado'),
    'posicao_ranking', (select count(*) + 1 from public.perfis o where o.pontos > u.pontos and not o.banido),
    'ultimas_avaliacoes', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select a.id, a.posto_id, coalesce(p.nome_exibicao, p.razao_social) as posto, a.nota, a.comentario, a.criado_em
        from public.avaliacoes a join public.postos p on p.id = a.posto_id
        where a.usuario_id = u.id order by a.criado_em desc limit 5) x),
    'ultimos_envios', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
        select i.id, i.posto_id, coalesce(p.nome_exibicao, p.razao_social) as posto, i.produto_id, i.preco, i.status, i.criado_em
        from public.envio_itens i join public.postos p on p.id = i.posto_id
        where i.usuario_id = u.id order by i.criado_em desc limit 10) x)
  )
  from public.perfis u
  where u.id = auth.uid()
$$;

-- Ranking geral (nomes abreviados)
create or replace function public.ranking(p_limite integer default 50)
returns table (posicao bigint, autor text, pontos integer, sou_eu boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select rank() over (order by u.pontos desc), public.abreviar_nome(u.nome), u.pontos, u.id = auth.uid()
  from public.perfis u
  where not u.banido and u.pontos > 0
  order by u.pontos desc
  limit least(p_limite, 100)
$$;

-- Favoritos do usuário com preços atuais
create or replace function public.meus_favoritos()
returns table (
  id bigint, nome text, bandeira text, endereco text, bairro text, municipio text, uf char(2),
  lat double precision, lon double precision, nota_media numeric, total_avaliacoes integer,
  municipio_pesquisado_anp boolean, precos jsonb, notificar boolean)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select p.id, coalesce(p.nome_exibicao, p.razao_social), p.bandeira, p.endereco, p.bairro, p.municipio, p.uf,
         st_y(p.localizacao::geometry), st_x(p.localizacao::geometry),
         p.nota_media, p.total_avaliacoes, p.municipio_pesquisado_anp, public.precos_json(p.id), f.notificar
  from public.favoritos f
  join public.postos p on p.id = f.posto_id
  where f.usuario_id = auth.uid()
  order by f.criado_em desc
$$;

-- Vários postos por id (favoritos guardados no aparelho de quem não fez login)
create or replace function public.postos_por_ids(p_ids bigint[])
returns table (
  id bigint, nome text, bandeira text, endereco text, bairro text, municipio text, uf char(2),
  lat double precision, lon double precision, nota_media numeric, total_avaliacoes integer,
  municipio_pesquisado_anp boolean, precos jsonb)
language sql
stable
set search_path = public, extensions
as $$
  select p.id, coalesce(p.nome_exibicao, p.razao_social), p.bandeira, p.endereco, p.bairro, p.municipio, p.uf,
         st_y(p.localizacao::geometry), st_x(p.localizacao::geometry),
         p.nota_media, p.total_avaliacoes, p.municipio_pesquisado_anp, public.precos_json(p.id)
  from public.postos p
  where p.id = any (p_ids[1:100]) and p.ativo
$$;

grant execute on function public.postos_por_ids(bigint[]) to anon, authenticated;
grant execute on function public.postos_na_area(double precision, double precision, double precision, double precision, integer) to anon, authenticated;
grant execute on function public.postos_proximos(double precision, double precision, double precision, integer) to anon, authenticated;
grant execute on function public.buscar_postos(text, double precision, double precision, integer) to anon, authenticated;
grant execute on function public.detalhe_posto(bigint) to anon, authenticated;
grant execute on function public.historico_precos(bigint, smallint, integer) to anon, authenticated;
grant execute on function public.contribuicoes(bigint, smallint) to anon, authenticated;
grant execute on function public.avaliacoes_posto(bigint, text, integer, integer) to anon, authenticated;
grant execute on function public.ranking(integer) to anon, authenticated;
revoke execute on function public.meu_resumo() from public, anon;
grant execute on function public.meu_resumo() to authenticated;
revoke execute on function public.meus_favoritos() from public, anon;
grant execute on function public.meus_favoritos() to authenticated;

-- ---------------------------------------------------------------------------
-- Importação do cadastro de revendedores (chamada pela Edge Function de sincronização)
-- p_registros: array de objetos já normalizados pela função TypeScript.
-- ---------------------------------------------------------------------------
create or replace function public.importar_postos_anp(p_uf char(2), p_registros jsonb, p_completo boolean)
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_total integer;
begin
  insert into public.postos as p (
    cnpj, razao_social, bandeira, endereco, complemento, bairro, municipio, uf, cep,
    localizacao, localizacao_validada, localizacao_fonte, autorizacao_anp, ativo, sincronizado_em)
  select r ->> 'cnpj', r ->> 'razao_social', r ->> 'bandeira', r ->> 'endereco', nullif(r ->> 'complemento', ''),
         r ->> 'bairro', r ->> 'municipio', p_uf, nullif(r ->> 'cep', ''),
         case when (r ->> 'lat') is not null and (r ->> 'lon') is not null
              then st_makepoint((r ->> 'lon')::float8, (r ->> 'lat')::float8)::geography end,
         coalesce((r ->> 'validada')::boolean, false),
         case when (r ->> 'lat') is not null then 'anp' end,
         r ->> 'autorizacao', true, now()
  from jsonb_array_elements(p_registros) r
  on conflict (cnpj) do update set
    razao_social = excluded.razao_social,
    bandeira = excluded.bandeira,
    endereco = excluded.endereco,
    complemento = excluded.complemento,
    bairro = excluded.bairro,
    municipio = excluded.municipio,
    uf = excluded.uf,
    cep = excluded.cep,
    -- posição corrigida por usuário não é sobrescrita
    localizacao = case when p.localizacao_fonte = 'usuario' then p.localizacao
                       else coalesce(excluded.localizacao, p.localizacao) end,
    localizacao_validada = case when p.localizacao_fonte = 'usuario' then p.localizacao_validada
                                else excluded.localizacao_validada end,
    localizacao_fonte = case when p.localizacao_fonte = 'usuario' then p.localizacao_fonte
                             else coalesce(excluded.localizacao_fonte, p.localizacao_fonte) end,
    autorizacao_anp = excluded.autorizacao_anp,
    ativo = true,
    sincronizado_em = now();

  get diagnostics v_total = row_count;

  -- Produtos vendidos
  delete from public.posto_produtos pp
  using public.postos p
  where pp.posto_id = p.id
    and p.cnpj in (select r ->> 'cnpj' from jsonb_array_elements(p_registros) r);

  insert into public.posto_produtos (posto_id, produto_id, bicos)
  select p.id, (x ->> 'produto_id')::smallint, sum((x ->> 'bicos')::int)::smallint
  from jsonb_array_elements(p_registros) r
  join public.postos p on p.cnpj = r ->> 'cnpj'
  cross join lateral jsonb_array_elements(coalesce(r -> 'produtos', '[]'::jsonb)) x
  group by 1, 2
  on conflict do nothing;

  -- Postos da UF que saíram do cadastro ficam inativos (histórico preservado)
  if p_completo then
    update public.postos set ativo = false
    where uf = p_uf and ativo and (sincronizado_em is null or sincronizado_em < now() - interval '1 hour');
  end if;

  insert into public.sincronizacoes_anp (uf, executado_em, registros, erro)
  values (p_uf, now(), v_total, null)
  on conflict (uf) do update set executado_em = now(),
    registros = case when p_completo then excluded.registros else coalesce(sincronizacoes_anp.registros, 0) + excluded.registros end,
    erro = null;

  return v_total;
end;
$$;

revoke execute on function public.importar_postos_anp(char, jsonb, boolean) from public, anon, authenticated;

-- Distância em metros entre o usuário e o posto (usada na validação do envio)
create or replace function public.distancia_ate_posto(p_posto bigint, p_lat double precision, p_lon double precision)
returns double precision
language sql
stable
set search_path = public, extensions
as $$
  select st_distance(p.localizacao, st_makepoint(p_lon, p_lat)::geography)
  from public.postos p where p.id = p_posto and p.ativo
$$;

revoke execute on function public.distancia_ate_posto(bigint, double precision, double precision) from public, anon, authenticated;

-- Notificações chegam ao app em tempo real (Supabase Realtime respeita a RLS)
alter publication supabase_realtime add table public.notificacoes;

-- ---------------------------------------------------------------------------
-- Tarefas agendadas (pg_cron). A sincronização chama a Edge Function usando
-- dois segredos do Vault: project_url e cron_secret (ver README).
-- ---------------------------------------------------------------------------
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule('gasprice-fechar-envios', '10 * * * *', $$select public.fechar_envios_antigos()$$);
select cron.schedule('gasprice-municipios-anp', '30 4 * * 1', $$select public.marcar_municipios_pesquisados()$$);
select cron.schedule('gasprice-estimativas', '0 5 * * 1',
  $$select public.recalcular_estimativas(); select public.recalcular_precos_atuais();$$);
select cron.schedule('gasprice-sincronizar-cadastro', '*/10 3-7 * * 0', $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/sincronizar-cadastro-anp',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000)
$$);
