-- gasprice · precisão da localização dos postos
--
-- Nem todo posto tem coordenada confiável. A pesquisa feita em 01/10/2026 (documentacao, página de andamento)
-- mostrou que localizar pelo endereço dá posições que erram de centenas de metros a vários quilômetros.
-- Cada posto passa a guardar quão boa é a sua posição, e as regras do app seguem essa precisão:
--
--   exata        coordenada da ANP, número da casa ou posição confirmada por 2 usuários   envio de preço em 300 m
--   rua          achado pela rua                                                          envio de preço em 1 km
--   cep_rua      achado pelo CEP de uma rua                                               envio de preço em 1 km
--   cep_cidade   CEP que cobre a cidade inteira                                           não aceita envio, não aparece no mapa
--   municipio    centro do município                                                      não aceita envio, não aparece no mapa
--   nenhuma      sem posição                                                              não aceita envio, não aparece no mapa
--
-- Quem está no posto pode informar a posição ("Estou neste posto"), sem enviar preço e sem limite de raio.
-- Quando 2 usuários diferentes informam posições a até 150 m uma da outra, a posição vira a oficial.

alter table public.postos
  add column precisao_localizacao text not null default 'nenhuma'
  check (precisao_localizacao in ('exata', 'rua', 'cep_rua', 'cep_cidade', 'municipio', 'nenhuma'));

update public.postos set precisao_localizacao = 'exata' where localizacao is not null;

insert into public.parametros (chave, valor, descricao) values
  ('raio_envio_aproximado_m',  1000, 'Distância máxima para enviar preço em posto com localização aproximada (rua ou CEP de rua)'),
  ('usuarios_consenso_posicao', 2,   'Usuários distintos necessários para confirmar a posição de um posto'),
  ('tolerancia_posicao_m',      150, 'Distância máxima em metros entre duas posições informadas para valerem como a mesma'),
  ('janela_posicao_d',          30,  'Dias em que uma posição informada espera por confirmação'),
  ('pontos_posicao',            5,   'Pontos por posição de posto confirmada'),
  ('posicoes_por_dia',          10,  'Posições de posto que cada usuário pode informar em 24 horas'),
  ('distancia_max_correcao_km', 100, 'Distância máxima entre a posição informada e a posição aproximada atual do posto'),
  ('precisao_gps_max_m',        100, 'Precisão mínima do GPS, em metros, para informar a posição de um posto');

-- ---------------------------------------------------------------------------
-- Posições informadas por quem está no posto
-- ---------------------------------------------------------------------------
create table public.correcoes_posicao (
  id             bigint generated always as identity primary key,
  posto_id       bigint not null references public.postos (id) on delete cascade,
  usuario_id     uuid references public.perfis (id) on delete set null,
  posicao        extensions.geography(Point, 4326) not null,
  status         text not null default 'pendente' check (status in ('pendente', 'confirmada', 'contestada')),
  criado_em      timestamptz not null default now(),
  consolidado_em timestamptz
);

create index correcoes_posicao_posto_idx on public.correcoes_posicao (posto_id, status);
create unique index correcoes_posicao_pendente_idx on public.correcoes_posicao (posto_id, usuario_id) where status = 'pendente';

alter table public.correcoes_posicao enable row level security;
create policy "le as proprias posicoes" on public.correcoes_posicao
  for select to authenticated using (usuario_id = (select auth.uid()));

-- Confirma a posição quando 2 usuários distintos informam pontos a até 150 m um do outro
create or replace function public.consolidar_posicao(p_posto bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_tol numeric := public.parametro('tolerancia_posicao_m');
  v_min integer := public.parametro('usuarios_consenso_posicao')::int;
  v_janela interval := make_interval(days => public.parametro('janela_posicao_d')::int);
  v_conf numeric := public.parametro('confiabilidade_min');
  v_base record;
  v_ids bigint[];
  v_ponto geography;
  v_item record;
begin
  select c.id, c.posicao,
         (select count(distinct d.usuario_id)
            from public.correcoes_posicao d
            join public.perfis u on u.id = d.usuario_id
           where d.posto_id = p_posto and d.status = 'pendente' and d.criado_em >= now() - v_janela
             and st_distance(d.posicao, c.posicao) <= v_tol
             and u.confiabilidade >= v_conf and not u.banido) as usuarios
    into v_base
  from public.correcoes_posicao c
  where c.posto_id = p_posto and c.status = 'pendente' and c.criado_em >= now() - v_janela
  order by 3 desc, c.criado_em desc
  limit 1;

  if v_base.id is null or v_base.usuarios < v_min then
    return jsonb_build_object('status', 'aguardando', 'usuarios', coalesce(v_base.usuarios, 0));
  end if;

  select array_agg(d.id) into v_ids
  from public.correcoes_posicao d
  join public.perfis u on u.id = d.usuario_id
  where d.posto_id = p_posto and d.status = 'pendente' and d.criado_em >= now() - v_janela
    and st_distance(d.posicao, v_base.posicao) <= v_tol
    and u.confiabilidade >= v_conf and not u.banido;

  select st_centroid(st_collect(posicao::geometry))::geography into v_ponto
  from public.correcoes_posicao where id = any (v_ids);

  update public.postos
     set localizacao = v_ponto, localizacao_validada = true, localizacao_fonte = 'usuario',
         precisao_localizacao = 'exata'
   where id = p_posto;

  for v_item in
    update public.correcoes_posicao set status = 'confirmada', consolidado_em = now()
     where id = any (v_ids) returning usuario_id
  loop
    perform public.registrar_pontos(v_item.usuario_id, null, 'posicao',
              public.parametro('pontos_posicao')::int, 'Posição do posto confirmada');
    perform public.ajustar_confiabilidade(v_item.usuario_id, 0.03);
  end loop;

  -- As demais, que discordam do consenso, são encerradas sem punição: o GPS pode errar
  update public.correcoes_posicao set status = 'contestada', consolidado_em = now()
   where posto_id = p_posto and status = 'pendente';

  return jsonb_build_object('status', 'confirmada', 'usuarios', array_length(v_ids, 1));
end;
$$;

-- Registra a posição informada por um usuário. Chamada só pela Edge Function corrigir-posicao.
create or replace function public.registrar_correcao_posicao(
  p_usuario uuid, p_posto bigint, p_lat double precision, p_lon double precision)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_posto record;
  v_ponto geography := st_makepoint(p_lon, p_lat)::geography;
  v_hoje integer;
begin
  select id, precisao_localizacao, localizacao into v_posto from public.postos where id = p_posto and ativo;
  if not found then
    return jsonb_build_object('ok', false, 'motivo', 'posto_inexistente');
  end if;
  if v_posto.precisao_localizacao = 'exata' then
    return jsonb_build_object('ok', false, 'motivo', 'posicao_confirmada');
  end if;

  select count(*) into v_hoje from public.correcoes_posicao
   where usuario_id = p_usuario and criado_em >= now() - interval '24 hours';
  if v_hoje >= public.parametro('posicoes_por_dia') then
    return jsonb_build_object('ok', false, 'motivo', 'limite_diario');
  end if;

  if v_posto.localizacao is not null
     and st_distance(v_posto.localizacao, v_ponto) / 1000 > public.parametro('distancia_max_correcao_km') then
    return jsonb_build_object('ok', false, 'motivo', 'longe_do_posto');
  end if;

  -- Uma posição pendente por usuário e posto: informar de novo atualiza a anterior
  update public.correcoes_posicao set posicao = v_ponto, criado_em = now()
   where posto_id = p_posto and usuario_id = p_usuario and status = 'pendente';
  if not found then
    insert into public.correcoes_posicao (posto_id, usuario_id, posicao) values (p_posto, p_usuario, v_ponto);
  end if;

  return jsonb_build_object('ok', true) || public.consolidar_posicao(p_posto);
end;
$$;

-- Distância até o posto e precisão da posição dele (validação do envio de preço)
create or replace function public.distancia_e_precisao(p_posto bigint, p_lat double precision, p_lon double precision)
returns table (distancia_m double precision, precisao text)
language sql
stable
set search_path = public, extensions
as $$
  select case when p.localizacao is null then null
              else st_distance(p.localizacao, st_makepoint(p_lon, p_lat)::geography) end,
         p.precisao_localizacao
  from public.postos p where p.id = p_posto and p.ativo
$$;

revoke execute on function public.consolidar_posicao(bigint) from public, anon, authenticated;
revoke execute on function public.registrar_correcao_posicao(uuid, bigint, double precision, double precision) from public, anon, authenticated;
revoke execute on function public.distancia_e_precisao(bigint, double precision, double precision) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Consultas do app: passam a informar a precisão. Postos com posição fraca não vão para o mapa nem para a lista por distância.
-- ---------------------------------------------------------------------------
drop function public.postos_na_area(double precision, double precision, double precision, double precision, integer);
create function public.postos_na_area(
  p_lat_min double precision, p_lon_min double precision,
  p_lat_max double precision, p_lon_max double precision,
  p_limite integer default 300)
returns table (
  id bigint, nome text, bandeira text, endereco text, bairro text, municipio text, uf char(2),
  lat double precision, lon double precision, nota_media numeric, total_avaliacoes integer,
  municipio_pesquisado_anp boolean, precos jsonb, precisao text)
language sql
stable
set search_path = public, extensions
as $$
  select p.id, coalesce(p.nome_exibicao, p.razao_social), p.bandeira, p.endereco, p.bairro, p.municipio, p.uf,
         st_y(p.localizacao::geometry), st_x(p.localizacao::geometry),
         p.nota_media, p.total_avaliacoes, p.municipio_pesquisado_anp, public.precos_json(p.id),
         p.precisao_localizacao
  from public.postos p
  where p.ativo
    and p.precisao_localizacao in ('exata', 'rua', 'cep_rua')
    and p.localizacao && st_makeenvelope(p_lon_min, p_lat_min, p_lon_max, p_lat_max, 4326)::geography
  order by p.total_avaliacoes desc, p.id
  limit least(p_limite, 500)
$$;

drop function public.postos_proximos(double precision, double precision, double precision, integer);
create function public.postos_proximos(
  p_lat double precision, p_lon double precision, p_raio_km double precision default 20, p_limite integer default 200)
returns table (
  id bigint, nome text, bandeira text, endereco text, bairro text, municipio text, uf char(2),
  lat double precision, lon double precision, nota_media numeric, total_avaliacoes integer,
  municipio_pesquisado_anp boolean, precos jsonb, distancia_km double precision, precisao text)
language sql
stable
set search_path = public, extensions
as $$
  select p.id, coalesce(p.nome_exibicao, p.razao_social), p.bandeira, p.endereco, p.bairro, p.municipio, p.uf,
         st_y(p.localizacao::geometry), st_x(p.localizacao::geometry),
         p.nota_media, p.total_avaliacoes, p.municipio_pesquisado_anp, public.precos_json(p.id),
         st_distance(p.localizacao, st_makepoint(p_lon, p_lat)::geography) / 1000,
         p.precisao_localizacao
  from public.postos p
  where p.ativo
    and p.precisao_localizacao in ('exata', 'rua', 'cep_rua')
    and st_dwithin(p.localizacao, st_makepoint(p_lon, p_lat)::geography, least(p_raio_km, 100) * 1000)
  order by p.localizacao <-> st_makepoint(p_lon, p_lat)::geography
  limit least(p_limite, 500)
$$;

drop function public.buscar_postos(text, double precision, double precision, integer);
create function public.buscar_postos(
  p_texto text, p_lat double precision default null, p_lon double precision default null, p_limite integer default 40)
returns table (
  id bigint, nome text, bandeira text, endereco text, bairro text, municipio text, uf char(2),
  lat double precision, lon double precision, nota_media numeric, total_avaliacoes integer,
  municipio_pesquisado_anp boolean, precos jsonb, distancia_km double precision, precisao text)
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
         case when p_lat is null or p.precisao_localizacao not in ('exata', 'rua', 'cep_rua') then null
              else st_distance(p.localizacao, st_makepoint(p_lon, p_lat)::geography) / 1000 end,
         p.precisao_localizacao
  from public.postos p, termos t
  where p.ativo
    and char_length(trim(p_texto)) >= 2
    and not exists (select 1 from unnest(t.palavras) w where p.texto_busca not like '%' || w || '%')
  order by case when p_lat is null or p.precisao_localizacao not in ('exata', 'rua', 'cep_rua') then 0
                else st_distance(p.localizacao, st_makepoint(p_lon, p_lat)::geography) end,
           p.total_avaliacoes desc
  limit least(p_limite, 100)
$$;

drop function public.postos_por_ids(bigint[]);
create function public.postos_por_ids(p_ids bigint[])
returns table (
  id bigint, nome text, bandeira text, endereco text, bairro text, municipio text, uf char(2),
  lat double precision, lon double precision, nota_media numeric, total_avaliacoes integer,
  municipio_pesquisado_anp boolean, precos jsonb, precisao text)
language sql
stable
set search_path = public, extensions
as $$
  select p.id, coalesce(p.nome_exibicao, p.razao_social), p.bandeira, p.endereco, p.bairro, p.municipio, p.uf,
         st_y(p.localizacao::geometry), st_x(p.localizacao::geometry),
         p.nota_media, p.total_avaliacoes, p.municipio_pesquisado_anp, public.precos_json(p.id),
         p.precisao_localizacao
  from public.postos p
  where p.id = any (p_ids[1:100]) and p.ativo
$$;

drop function public.meus_favoritos();
create function public.meus_favoritos()
returns table (
  id bigint, nome text, bandeira text, endereco text, bairro text, municipio text, uf char(2),
  lat double precision, lon double precision, nota_media numeric, total_avaliacoes integer,
  municipio_pesquisado_anp boolean, precos jsonb, notificar boolean, precisao text)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select p.id, coalesce(p.nome_exibicao, p.razao_social), p.bandeira, p.endereco, p.bairro, p.municipio, p.uf,
         st_y(p.localizacao::geometry), st_x(p.localizacao::geometry),
         p.nota_media, p.total_avaliacoes, p.municipio_pesquisado_anp, public.precos_json(p.id), f.notificar,
         p.precisao_localizacao
  from public.favoritos f
  join public.postos p on p.id = f.posto_id
  where f.usuario_id = auth.uid()
  order by f.criado_em desc
$$;

grant execute on function public.postos_na_area(double precision, double precision, double precision, double precision, integer) to anon, authenticated;
grant execute on function public.postos_proximos(double precision, double precision, double precision, integer) to anon, authenticated;
grant execute on function public.buscar_postos(text, double precision, double precision, integer) to anon, authenticated;
grant execute on function public.postos_por_ids(bigint[]) to anon, authenticated;
revoke execute on function public.meus_favoritos() from public, anon;
grant execute on function public.meus_favoritos() to authenticated;

-- Detalhe do posto: precisão, raio de envio e se o próprio usuário já informou a posição
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
    'precisao', p.precisao_localizacao,
    'raio_envio_m', case p.precisao_localizacao
                      when 'exata' then public.parametro('raio_envio_m')
                      when 'rua' then public.parametro('raio_envio_aproximado_m')
                      when 'cep_rua' then public.parametro('raio_envio_aproximado_m') end,
    'posicao_informada', exists (select 1 from correcoes_posicao c
                                  where c.posto_id = p.id and c.status = 'pendente' and c.usuario_id = auth.uid()),
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

-- Importação da ANP: coordenada da ANP passa a valer como posição exata; posição confirmada por usuário é preservada
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
    localizacao, localizacao_validada, localizacao_fonte, precisao_localizacao, autorizacao_anp, ativo, sincronizado_em)
  select r ->> 'cnpj', r ->> 'razao_social', r ->> 'bandeira', r ->> 'endereco', nullif(r ->> 'complemento', ''),
         r ->> 'bairro', r ->> 'municipio', p_uf, nullif(r ->> 'cep', ''),
         case when (r ->> 'lat') is not null and (r ->> 'lon') is not null
              then st_makepoint((r ->> 'lon')::float8, (r ->> 'lat')::float8)::geography end,
         coalesce((r ->> 'validada')::boolean, false),
         case when (r ->> 'lat') is not null then 'anp' end,
         case when (r ->> 'lat') is not null then 'exata' else 'nenhuma' end,
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
    localizacao = case when p.localizacao_fonte = 'usuario' then p.localizacao
                       else coalesce(excluded.localizacao, p.localizacao) end,
    localizacao_validada = case when p.localizacao_fonte = 'usuario' then p.localizacao_validada
                                else excluded.localizacao_validada end,
    localizacao_fonte = case when p.localizacao_fonte = 'usuario' then p.localizacao_fonte
                             else coalesce(excluded.localizacao_fonte, p.localizacao_fonte) end,
    precisao_localizacao = case when p.localizacao_fonte = 'usuario' then p.precisao_localizacao
                                when excluded.localizacao is not null then 'exata'
                                else p.precisao_localizacao end,
    autorizacao_anp = excluded.autorizacao_anp,
    ativo = true,
    sincronizado_em = now();

  get diagnostics v_total = row_count;

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
