-- gasprice · correções da auditoria de 06/10/2026
--   BUG-01  envios simultâneos furavam a regra de 6 h e multiplicavam pontos
--   BUG-02  coordenada padrão da API da ANP gravada como posição exata
--   BUG-05  identificador de quem avaliou e de quem votou era público
--   BUG-08  autora conseguia votar na própria avaliação pela API

-- A limpeza das coordenadas percorre todos os postos: mais tempo que o padrão do Supabase
set statement_timeout = '15min';

-- ===========================================================================
-- BUG-01 · envio de preço numa só transação, com trava por usuário
-- ===========================================================================
-- A Edge Function valida o corpo e a distância e chama esta função. Limite diário, regra de 6 h,
-- gravação e consenso acontecem juntos, um envio por vez para cada usuário.
create or replace function public.registrar_envio(
  p_usuario uuid, p_posto bigint, p_lat double precision, p_lon double precision, p_distancia_m integer,
  p_itens jsonb, p_ocr_texto text default null, p_ocr_duracao_ms integer default null, p_app_versao text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_envio uuid;
  v_no_dia integer;
  v_repetidos smallint[];
  v_aceitos jsonb;
  v_produto smallint;
  v_itens jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended('envio:' || p_usuario::text, 0));

  select count(*) into v_no_dia
  from public.envios where usuario_id = p_usuario and criado_em >= now() - interval '24 hours';
  if v_no_dia >= public.parametro('envios_por_dia') then
    return jsonb_build_object('ok', false, 'motivo', 'limite_diario');
  end if;

  select coalesce(array_agg(distinct produto_id), '{}') into v_repetidos
  from public.envio_itens
  where usuario_id = p_usuario and posto_id = p_posto
    and criado_em >= now() - make_interval(hours => public.parametro('intervalo_mesmo_item_h')::int);

  select coalesce(jsonb_agg(i.v), '[]'::jsonb) into v_aceitos
  from jsonb_array_elements(p_itens) as i(v)
  where not ((i.v ->> 'produto_id')::smallint = any (v_repetidos));
  if jsonb_array_length(v_aceitos) = 0 then
    return jsonb_build_object('ok', false, 'motivo', 'repetido');
  end if;

  insert into public.envios (usuario_id, posto_id, posicao, distancia_m, ocr_texto, ocr_duracao_ms, app_versao)
  values (p_usuario, p_posto, st_makepoint(p_lon, p_lat)::geography, p_distancia_m, p_ocr_texto, p_ocr_duracao_ms, p_app_versao)
  returning id into v_envio;

  insert into public.envio_itens (envio_id, posto_id, produto_id, usuario_id, preco, preco_lido, confianca_ocr, em_revisao, motivo_revisao)
  select v_envio, p_posto, (i.v ->> 'produto_id')::smallint, p_usuario, (i.v ->> 'preco')::numeric,
         (i.v ->> 'preco_lido')::numeric, (i.v ->> 'confianca_ocr')::real,
         coalesce((i.v ->> 'em_revisao')::boolean, false), i.v ->> 'motivo_revisao'
  from jsonb_array_elements(v_aceitos) as i(v);

  for v_produto in select distinct (i.v ->> 'produto_id')::smallint from jsonb_array_elements(v_aceitos) as i(v) loop
    perform public.consolidar_preco(p_posto, v_produto);
  end loop;

  select jsonb_agg(jsonb_build_object('id', e.id, 'produto_id', e.produto_id, 'preco', e.preco, 'status', e.status,
                                      'em_revisao', e.em_revisao, 'motivo_revisao', e.motivo_revisao) order by e.produto_id)
    into v_itens
  from public.envio_itens e where e.envio_id = v_envio;

  return jsonb_build_object(
    'ok', true, 'envio_id', v_envio, 'itens', v_itens,
    'ignorados', to_jsonb(array(select (i.v ->> 'produto_id')::int from jsonb_array_elements(p_itens) as i(v)
                                where (i.v ->> 'produto_id')::smallint = any (v_repetidos))));
end;
$$;

revoke execute on function public.registrar_envio(uuid, bigint, double precision, double precision, integer, jsonb, text, integer, text)
  from public, anon, authenticated;

-- Consenso: pontos e confiabilidade uma vez por pessoa em cada consenso, mesmo que ela tenha
-- mais de um envio no grupo (antes era um crédito por envio).
create or replace function public.consolidar_preco(p_posto bigint, p_produto smallint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tol numeric := public.parametro('tolerancia_consenso');
  v_janela interval := make_interval(hours => public.parametro('janela_consenso_h')::int);
  v_min_conf numeric := public.parametro('confiabilidade_min');
  v_melhor record;
  v_necessario integer;
  v_mult integer := 1;
  v_item record;
  v_estava_parado boolean;
  v_primeiro bigint;
  v_confirmados bigint[];
  v_contestados bigint[];
begin
  select i.id, i.preco, i.em_revisao,
         (select count(distinct j.usuario_id)
            from public.envio_itens j
            join public.perfis u on u.id = j.usuario_id
           where j.posto_id = p_posto and j.produto_id = p_produto
             and j.status in ('pendente', 'confirmado')
             and j.criado_em >= now() - v_janela
             and abs(j.preco - i.preco) <= v_tol
             and u.confiabilidade >= v_min_conf
             and not u.banido) as usuarios,
         (select bool_or(j.em_revisao)
            from public.envio_itens j
           where j.posto_id = p_posto and j.produto_id = p_produto
             and j.status = 'pendente' and j.criado_em >= now() - v_janela
             and abs(j.preco - i.preco) <= v_tol) as algum_em_revisao
    into v_melhor
  from public.envio_itens i
  where i.posto_id = p_posto and i.produto_id = p_produto
    and i.status = 'pendente' and i.criado_em >= now() - v_janela
  order by 4 desc, i.criado_em desc
  limit 1;

  if v_melhor.id is null then
    perform public.atualizar_preco_atual(p_posto, p_produto);
    return;
  end if;

  v_necessario := case when v_melhor.algum_em_revisao
                       then public.parametro('usuarios_consenso_revisao')::int
                       else public.parametro('usuarios_consenso')::int end;

  if v_melhor.usuarios < v_necessario then
    perform public.atualizar_preco_atual(p_posto, p_produto);
    return;
  end if;

  select case when p.municipio_pesquisado_anp then 1 else public.parametro('multiplicador_sem_anp')::int end
    into v_mult from public.postos p where p.id = p_posto;

  select not exists (
    select 1 from public.envio_itens j
    where j.posto_id = p_posto and j.produto_id = p_produto and j.status = 'confirmado'
      and j.consolidado_em >= now() - interval '24 hours'
  ) into v_estava_parado;

  select j.id into v_primeiro
  from public.envio_itens j
  where j.posto_id = p_posto and j.produto_id = p_produto and j.status = 'pendente'
    and j.criado_em >= now() - v_janela and abs(j.preco - v_melhor.preco) <= v_tol
  order by j.criado_em
  limit 1;

  with u as (
    update public.envio_itens j
       set status = 'confirmado', consolidado_em = now()
     where j.posto_id = p_posto and j.produto_id = p_produto and j.status = 'pendente'
       and j.criado_em >= now() - v_janela and abs(j.preco - v_melhor.preco) <= v_tol
    returning j.id)
  select coalesce(array_agg(id), '{}') into v_confirmados from u;

  for v_item in
    select distinct on (j.usuario_id) j.id, j.usuario_id
    from public.envio_itens j
    where j.id = any (v_confirmados) and j.usuario_id is not null
    order by j.usuario_id, (j.id = v_primeiro) desc, j.id
  loop
    perform public.registrar_pontos(v_item.usuario_id, v_item.id, 'confirmado',
              public.parametro('pontos_confirmado')::int * v_mult, 'Preço confirmado pela comunidade');
    if v_estava_parado and v_item.id = v_primeiro then
      perform public.registrar_pontos(v_item.usuario_id, v_item.id, 'primeiro',
                public.parametro('pontos_primeiro')::int * v_mult, 'Primeiro envio em posto sem atualização');
    end if;
    perform public.ajustar_confiabilidade(v_item.usuario_id, 0.05);
  end loop;

  with u as (
    update public.envio_itens j
       set status = 'contestado', consolidado_em = now()
     where j.posto_id = p_posto and j.produto_id = p_produto and j.status = 'pendente'
       and j.criado_em >= now() - v_janela and abs(j.preco - v_melhor.preco) > v_tol
    returning j.id)
  select coalesce(array_agg(id), '{}') into v_contestados from u;

  for v_item in
    select distinct on (j.usuario_id) j.id, j.usuario_id
    from public.envio_itens j
    where j.id = any (v_contestados) and j.usuario_id is not null
    order by j.usuario_id, j.id
  loop
    perform public.registrar_pontos(v_item.usuario_id, v_item.id, 'contestado',
              public.parametro('pontos_contestado')::int, 'Preço contrariado por outros usuários');
    perform public.ajustar_confiabilidade(v_item.usuario_id, -0.10);
  end loop;

  insert into public.precos_comunidade (posto_id, produto_id, dia, preco, envios, usuarios, confirmado)
  select p_posto, p_produto, current_date, v_melhor.preco,
         count(*), count(distinct usuario_id), true
  from public.envio_itens
  where posto_id = p_posto and produto_id = p_produto and status = 'confirmado'
    and consolidado_em >= date_trunc('day', now())
  on conflict (posto_id, produto_id, dia) do update set
    preco = excluded.preco, envios = excluded.envios, usuarios = excluded.usuarios, confirmado = true;

  perform public.atualizar_preco_atual(p_posto, p_produto);
end;
$$;

revoke execute on function public.consolidar_preco(bigint, smallint) from public, anon, authenticated;

-- ===========================================================================
-- BUG-02 · coordenada da ANP só vale se cair no estado do posto e não for valor padrão
-- ===========================================================================
insert into public.parametros (chave, valor, descricao) values
  ('tolerancia_uf_m', 15000, 'Distância máxima, em metros, entre a coordenada da ANP e o contorno do estado do posto');

-- Pontos que a API da ANP usa como valor padrão para postos de vários estados
create table public.coordenadas_invalidas (
  id      bigint generated always as identity primary key,
  ponto   extensions.geography(Point, 4326) not null,
  motivo  text not null
);
create index coordenadas_invalidas_ponto_idx on public.coordenadas_invalidas using gist (ponto);
alter table public.coordenadas_invalidas enable row level security;

insert into public.coordenadas_invalidas (ponto, motivo) values
  ('SRID=4326;POINT(-43.3371 -22.7780)', 'Valor padrão da API da ANP, achado na auditoria de 06/10/2026 em postos de 21 UFs');
insert into public.coordenadas_invalidas (ponto, motivo)
select localizacao, 'Mesmo ponto em postos de ' || count(distinct uf) || ' UFs (auditoria de 06/10/2026)'
from public.postos
where localizacao is not null
group by localizacao
having count(distinct uf) >= 3
   and not exists (select 1 from public.coordenadas_invalidas c
                   where extensions.st_dwithin(c.ponto, localizacao, 50));

create or replace function public.coordenada_confiavel(p_uf char(2), p_ponto extensions.geography)
returns boolean
language sql
stable
set search_path = public, extensions
as $$
  select p_ponto is not null
     and not exists (select 1 from public.coordenadas_invalidas c where st_dwithin(c.ponto, p_ponto, 50))
     and coalesce((select st_dwithin(l.contorno, p_ponto, public.parametro('tolerancia_uf_m'))
                   from public.ufs_limites l where l.uf = p_uf), true)
$$;

revoke execute on function public.coordenada_confiavel(char, extensions.geography) from public, anon, authenticated;

-- Importação: coordenada fora do estado ou de valor padrão entra como posição desconhecida,
-- e uma coordenada ruim já gravada é limpa na próxima sincronização.
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
         case when ok then ponto end,
         ok and coalesce((r ->> 'validada')::boolean, false),
         case when ok then 'anp' end,
         case when ok then 'exata' else 'nenhuma' end,
         r ->> 'autorizacao', true, now()
  from jsonb_array_elements(p_registros) r
  cross join lateral (select case when (r ->> 'lat') is not null and (r ->> 'lon') is not null
                                  then st_makepoint((r ->> 'lon')::float8, (r ->> 'lat')::float8)::geography end as ponto) c
  cross join lateral (select public.coordenada_confiavel(p_uf, c.ponto) as ok) v
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
                       when excluded.localizacao is not null then excluded.localizacao
                       when not public.coordenada_confiavel(p_uf, p.localizacao) then null
                       else p.localizacao end,
    localizacao_validada = case when p.localizacao_fonte = 'usuario' then p.localizacao_validada
                                when excluded.localizacao is not null then excluded.localizacao_validada
                                when not public.coordenada_confiavel(p_uf, p.localizacao) then false
                                else p.localizacao_validada end,
    localizacao_fonte = case when p.localizacao_fonte = 'usuario' then p.localizacao_fonte
                             when excluded.localizacao is not null then excluded.localizacao_fonte
                             when not public.coordenada_confiavel(p_uf, p.localizacao) then null
                             else p.localizacao_fonte end,
    precisao_localizacao = case when p.localizacao_fonte = 'usuario' then p.precisao_localizacao
                                when excluded.localizacao is not null then 'exata'
                                when not public.coordenada_confiavel(p_uf, p.localizacao) then 'nenhuma'
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

-- Corrige os postos já gravados: coordenada ruim vira posição desconhecida (até a comunidade confirmar)
do $$
declare
  v_ids bigint[];
  v_par record;
begin
  select coalesce(array_agg(id), '{}') into v_ids
  from public.postos
  where localizacao is not null and coalesce(localizacao_fonte, 'anp') <> 'usuario'
    and not public.coordenada_confiavel(uf, localizacao);

  update public.postos
     set localizacao = null, localizacao_validada = false, localizacao_fonte = null, precisao_localizacao = 'nenhuma'
   where id = any (v_ids);

  delete from public.precos_estimados where posto_id = any (v_ids);
  for v_par in select posto_id, produto_id from public.precos_atuais where posto_id = any (v_ids) loop
    perform public.atualizar_preco_atual(v_par.posto_id, v_par.produto_id);
  end loop;

  raise notice 'postos com coordenada da ANP recusada: %', coalesce(array_length(v_ids, 1), 0);
end
$$;

-- ===========================================================================
-- BUG-05 · quem avaliou e quem votou deixa de ser público
-- ===========================================================================
-- O app lê avaliações pela função avaliacoes_posto, que já mostra o nome abreviado.
revoke select on public.avaliacoes from anon, authenticated;
grant select (id, posto_id, nota, comentario, votos_uteis, criado_em, atualizado_em) on public.avaliacoes to anon, authenticated;

drop policy "le votos" on public.avaliacao_votos;
create policy "le os proprios votos" on public.avaliacao_votos
  for select to authenticated using (usuario_id = (select auth.uid()));

-- ===========================================================================
-- BUG-08 · ninguém vota na própria avaliação
-- ===========================================================================
create or replace function public.e_minha_avaliacao(p_avaliacao bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.avaliacoes a where a.id = p_avaliacao and a.usuario_id = auth.uid())
$$;

revoke execute on function public.e_minha_avaliacao(bigint) from public, anon;
grant execute on function public.e_minha_avaliacao(bigint) to authenticated;

drop policy "vota" on public.avaliacao_votos;
create policy "vota" on public.avaliacao_votos
  for insert to authenticated
  with check (usuario_id = (select auth.uid()) and not public.e_minha_avaliacao(avaliacao_id));
