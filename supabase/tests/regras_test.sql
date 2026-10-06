-- Testes das regras de negócio do gasprice.
-- Rodam num Postgres local com PostGIS, depois de shims_supabase.sql e das migrações.
-- Uso: python scripts/supabase/testar_banco_local.py
\set ON_ERROR_STOP on
set client_min_messages = notice;

create function pg_temp.checar(p_ok boolean, p_msg text) returns void language plpgsql as $$
begin
  if p_ok is distinct from true then
    raise exception 'FALHOU: %', p_msg;
  end if;
  raise notice 'ok  %', p_msg;
end
$$;

-- Simula a Edge Function enviar-precos: grava o envio (sem foto) e consolida
create function pg_temp.enviar(p_usuario uuid, p_posto bigint, p_produto int, p_preco numeric,
                               p_revisao boolean default false)
returns bigint language plpgsql as $$
declare
  v_envio uuid;
  v_item bigint;
begin
  insert into public.envios (usuario_id, posto_id, posicao, distancia_m, ocr_texto)
  values (p_usuario, p_posto, 'SRID=4326;POINT(-38.52 -3.73)', 40, 'GASOLINA 5,99')
  returning id into v_envio;
  insert into public.envio_itens (envio_id, posto_id, produto_id, usuario_id, preco, preco_lido, confianca_ocr, em_revisao)
  values (v_envio, p_posto, p_produto, p_usuario, p_preco, p_preco, 0.9, p_revisao)
  returning id into v_item;
  perform public.consolidar_preco(p_posto, p_produto::smallint);
  return v_item;
end
$$;

-- ============================================================ cadastro de usuários
insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@exemplo.com',   '{"nome": "Ana Souza"}',    now()),
  ('00000000-0000-0000-0000-00000000000b', 'bruno@exemplo.com', '{"nome": "Bruno Lima"}',   now()),
  ('00000000-0000-0000-0000-00000000000c', 'carla@exemplo.com', '{"nome": "Carla Mendes"}', now()),
  ('00000000-0000-0000-0000-00000000000d', 'x@y.com',           '{}',                       now());

select pg_temp.checar((select count(*) from public.perfis) = 4, 'perfil criado automaticamente no cadastro');
select pg_temp.checar((select nome from public.perfis where id = '00000000-0000-0000-0000-00000000000d') = 'Usuário',
                      'e-mail curto sem nome gera o nome "Usuário"');
select pg_temp.checar(public.abreviar_nome('Carla Mendes Souza') = 'Carla S.' and public.abreviar_nome('Ana') = 'Ana',
                      'nome abreviado para exibição pública');
select pg_temp.checar(public.normalizar('Ação São João') = 'acao sao joao', 'busca ignora acentos e maiúsculas');

-- ============================================================ postos e dados da ANP
insert into public.postos (id, cnpj, razao_social, bandeira, endereco, bairro, municipio, uf, localizacao, localizacao_fonte, precisao_localizacao) values
  (1, '11111111000191', 'POSTO CENTRO LTDA',       'IPIRANGA',        'AV DUQUE DE CAXIAS, 100', 'CENTRO',  'FORTALEZA', 'CE', 'SRID=4326;POINT(-38.5270 -3.7300)', 'anp', 'exata'),
  (2, '22222222000191', 'AUTO POSTO ALDEOTA LTDA', 'VIBRA',           'AV SANTOS DUMONT, 2000',  'ALDEOTA', 'FORTALEZA', 'CE', 'SRID=4326;POINT(-38.5100 -3.7350)', 'anp', 'exata'),
  (3, '33333333000191', 'POSTO ITAITINGA EIRELI',  'Bandeira branca', 'RUA PRINCIPAL, 10',       'CENTRO',  'ITAITINGA', 'CE', 'SRID=4326;POINT(-38.5280 -3.9690)', 'anp', 'exata');
select setval(pg_get_serial_sequence('public.postos', 'id'), 3);

insert into public.posto_produtos (posto_id, produto_id, bicos) values (1, 1, 4), (1, 3, 2), (2, 1, 4), (3, 1, 2), (3, 3, 2);
insert into public.precos_anp (posto_id, produto_id, data_coleta, preco, anomalia) values
  (1, 1, current_date - 5, 6.190, false),
  (1, 3, current_date - 5, 4.290, false),
  (2, 1, current_date - 3, 6.090, false),
  (2, 1, current_date - 1, 9.990, true);   -- anomalia: nunca vira preço exibido
insert into public.favoritos (usuario_id, posto_id) values ('00000000-0000-0000-0000-00000000000d', 1);

select public.marcar_municipios_pesquisados();
select pg_temp.checar((select municipio_pesquisado_anp from public.postos where id = 1)
                      and not (select municipio_pesquisado_anp from public.postos where id = 3),
                      'Fortaleza tem coleta da ANP e Itaitinga não');

select pg_temp.checar(public.recalcular_estimativas() = 2, 'estimativa só para posto e combustível sem preço ANP');
select pg_temp.checar((select preco = 6.140 and margem = 0.29 from public.precos_estimados where posto_id = 3 and produto_id = 1),
                      'estimativa de Itaitinga = mediana dos vizinhos (6,14) com o erro médio medido da faixa 25-50 km');

select public.recalcular_precos_atuais();
select pg_temp.checar((select preco = 6.190 and fonte = 'anp' and situacao = 'oficial' from public.precos_atuais where posto_id = 1 and produto_id = 1),
                      'sem envios, vale o preço oficial da ANP');
select pg_temp.checar((select preco = 6.090 from public.precos_atuais where posto_id = 2 and produto_id = 1),
                      'preço ANP marcado como anomalia é ignorado');
select pg_temp.checar((select fonte = 'estimativa' and margem = 0.29 from public.precos_atuais where posto_id = 3 and produto_id = 1),
                      'posto sem nenhuma fonte mostra estimativa com margem');

-- ============================================================ envio e consenso
select pg_temp.enviar('00000000-0000-0000-0000-00000000000a', 1, 1, 5.99);
select pg_temp.checar((select status = 'pendente' from public.envio_itens where usuario_id = '00000000-0000-0000-0000-00000000000a' and posto_id = 1),
                      'envio isolado fica pendente');
select pg_temp.checar((select preco = 5.990 and situacao = 'nao_confirmado' and ultimo_confiavel = 6.190
                       from public.precos_atuais where posto_id = 1 and produto_id = 1),
                      'envio isolado aparece como não confirmado e guarda o último preço confiável');
select pg_temp.checar((select count(*) from public.notificacoes) = 0, 'envio isolado não gera aviso');

select pg_temp.enviar('00000000-0000-0000-0000-00000000000b', 1, 1, 5.99);
select pg_temp.checar((select count(*) from public.envio_itens where posto_id = 1 and produto_id = 1 and status = 'confirmado') = 2,
                      'dois usuários com o mesmo valor confirmam o preço');
select pg_temp.checar((select situacao = 'confirmado' and confirmacoes = 2 from public.precos_atuais where posto_id = 1 and produto_id = 1),
                      'preço exibido passa a ser o confirmado');
select pg_temp.checar((select pontos from public.perfis where id = '00000000-0000-0000-0000-00000000000a') = 15,
                      'primeiro a enviar ganha 10 + 5 de bônus');
select pg_temp.checar((select pontos from public.perfis where id = '00000000-0000-0000-0000-00000000000b') = 10,
                      'quem confirma ganha 10');
select pg_temp.checar((select confiabilidade from public.perfis where id = '00000000-0000-0000-0000-00000000000a') = 0.550,
                      'confiabilidade sobe com envio confirmado');
select pg_temp.checar((select confirmado from public.precos_comunidade where posto_id = 1 and produto_id = 1 and dia = current_date),
                      'preço confirmado entra no histórico no mesmo dia');
select pg_temp.checar((select count(*) = 1 and min(preco_anterior) = 6.190 and min(preco_novo) = 5.990
                       from public.notificacoes where usuario_id = '00000000-0000-0000-0000-00000000000d'),
                      'quem favoritou é avisado da queda de 6,19 para 5,99');

select pg_temp.enviar('00000000-0000-0000-0000-00000000000c', 1, 1, 6.49);
select pg_temp.checar((select preco = 5.990 and situacao = 'confirmado' from public.precos_atuais where posto_id = 1 and produto_id = 1),
                      'envio isolado diferente não derruba um preço confirmado');

-- Divergência: vale a ANP
select pg_temp.enviar('00000000-0000-0000-0000-00000000000a', 2, 1, 5.79);
select pg_temp.enviar('00000000-0000-0000-0000-00000000000d', 2, 1, 5.99);
select pg_temp.checar((select preco = 6.090 and fonte = 'anp' and situacao = 'divergente' from public.precos_atuais where posto_id = 2 and produto_id = 1),
                      'envios divergentes fazem valer o preço da ANP');

-- Consenso contraria o envio divergente
select pg_temp.enviar('00000000-0000-0000-0000-00000000000b', 2, 1, 5.79);
select pg_temp.checar((select status = 'contestado' from public.envio_itens where usuario_id = '00000000-0000-0000-0000-00000000000d' and posto_id = 2),
                      'envio contrariado pelo consenso é marcado como contestado');
select pg_temp.checar((select pontos = 0 and confiabilidade = 0.400 from public.perfis where id = '00000000-0000-0000-0000-00000000000d'),
                      'contestado perde 5 pontos (sem ficar negativo) e confiabilidade');
select pg_temp.checar((select pontos from public.perfis where id = '00000000-0000-0000-0000-00000000000a') = 30,
                      'segundo posto confirmado soma 10 + 5 de bônus');

-- Cidade sem coleta da ANP: pontos em dobro
select pg_temp.enviar('00000000-0000-0000-0000-00000000000a', 3, 1, 5.89);
select pg_temp.enviar('00000000-0000-0000-0000-00000000000c', 3, 1, 5.89);
select pg_temp.checar((select pontos from public.perfis where id = '00000000-0000-0000-0000-00000000000a') = 60,
                      'cidade sem ANP dobra pontos e bônus (20 + 10)');
select pg_temp.checar((select pontos from public.perfis where id = '00000000-0000-0000-0000-00000000000c') = 20,
                      'cidade sem ANP dobra os pontos de quem confirma');
select pg_temp.checar((select fonte = 'comunidade' and situacao = 'confirmado' from public.precos_atuais where posto_id = 3 and produto_id = 1),
                      'preço da comunidade substitui a estimativa');

-- Envio em revisão (desvio grande) exige 3 usuários
select pg_temp.enviar('00000000-0000-0000-0000-00000000000a', 1, 3, 5.50, true);
select pg_temp.enviar('00000000-0000-0000-0000-00000000000b', 1, 3, 5.50, true);
select pg_temp.checar((select count(*) from public.envio_itens where posto_id = 1 and produto_id = 3 and status = 'pendente') = 2,
                      'em revisão, dois usuários ainda não bastam');
select pg_temp.checar((select preco = 4.290 and situacao = 'oficial' from public.precos_atuais where posto_id = 1 and produto_id = 3),
                      'envio em revisão não aparece como preço antes de confirmado');
select pg_temp.enviar('00000000-0000-0000-0000-00000000000d', 1, 3, 5.50, true);
select pg_temp.checar((select count(*) from public.envio_itens where posto_id = 1 and produto_id = 3 and status = 'confirmado') = 3,
                      'em revisão, o terceiro usuário confirma');
select pg_temp.checar((select count(*) from public.notificacoes where usuario_id = '00000000-0000-0000-0000-00000000000d') = 2,
                      'mudança do etanol também gera aviso para o favorito');

-- Expiração em 24 h
update public.envio_itens set criado_em = now() - interval '25 hours'
where usuario_id = '00000000-0000-0000-0000-00000000000c' and posto_id = 1;
select pg_temp.checar(public.fechar_envios_antigos() = 1, 'envio sem confirmação há mais de 24 h é fechado');
select pg_temp.checar((select status = 'expirado' from public.envio_itens where usuario_id = '00000000-0000-0000-0000-00000000000c' and posto_id = 1),
                      'envio fechado fica como expirado');
select pg_temp.checar((select not confirmado from public.precos_comunidade
                       where posto_id = 1 and produto_id = 1 and dia = (now() - interval '25 hours')::date),
                      'envio expirado entra no histórico como não confirmado');
select pg_temp.checar((select preco = 5.990 and situacao = 'confirmado' from public.precos_atuais where posto_id = 1 and produto_id = 1),
                      'preço confirmado continua exibido');

-- Teto diário e bloqueio
select pg_temp.checar(public.registrar_pontos('00000000-0000-0000-0000-00000000000b', null, 'teste', 500, 'Teste do teto') = 170,
                      'teto de 200 pontos por dia limita o ganho');
select pg_temp.checar(public.registrar_pontos('00000000-0000-0000-0000-00000000000b', null, 'teste', 10, 'Teste do teto') = 0,
                      'acima do teto não ganha mais pontos');
do $$
declare
  v uuid;
begin
  insert into public.envios (usuario_id, posto_id, posicao, distancia_m)
  values ('00000000-0000-0000-0000-00000000000c', 2, 'SRID=4326;POINT(-38.51 -3.735)', 10) returning id into v;
  insert into public.envio_itens (envio_id, posto_id, produto_id, usuario_id, preco, status)
  select v, 2, 1, '00000000-0000-0000-0000-00000000000c', 6.00, 'contestado' from generate_series(1, 3);
  perform public.ajustar_confiabilidade('00000000-0000-0000-0000-00000000000c', -0.10);
end
$$;
select pg_temp.checar((select bloqueado_ate > now() from public.perfis where id = '00000000-0000-0000-0000-00000000000c'),
                      '3 envios contestados em 7 dias pausam novos envios');

-- ============================================================ recálculo semanal em bloco
create temp table antes as
  select posto_id, produto_id, preco, fonte, situacao, confirmacoes from public.precos_atuais;
select public.recalcular_precos_atuais();
select pg_temp.checar(not exists (
    select 1 from antes a full join public.precos_atuais p using (posto_id, produto_id)
    where (a.preco, a.fonte, a.situacao, a.confirmacoes) is distinct from (p.preco, p.fonte, p.situacao, p.confirmacoes)),
  'recálculo em bloco reproduz o que o caminho individual já tinha calculado');
select pg_temp.checar((select preco = 5.990 and situacao = 'confirmado' and confirmacoes = 2
                       from public.precos_atuais where posto_id = 1 and produto_id = 1),
                      'recálculo preserva o preço confirmado pela comunidade');

insert into public.postos (id, cnpj, razao_social, municipio, uf, localizacao, localizacao_fonte, precisao_localizacao)
values (9, '99999999000191', 'POSTO NOVO NOVE LTDA', 'FORTALEZA', 'CE', 'SRID=4326;POINT(-38.52 -3.75)', 'anp', 'exata');
insert into public.posto_produtos (posto_id, produto_id, bicos) values (9, 1, 2);
insert into public.precos_anp (posto_id, produto_id, data_coleta, preco) values (9, 1, current_date - 7, 6.000);
insert into public.favoritos (usuario_id, posto_id) values ('00000000-0000-0000-0000-00000000000a', 9);
select public.recalcular_precos_atuais();
select pg_temp.checar((select preco = 6.000 and fonte = 'anp' and situacao = 'oficial' and ultimo_confiavel = 6.000
                       from public.precos_atuais where posto_id = 9 and produto_id = 1),
                      'em bloco, o preço da ANP vira o preço exibido');
select pg_temp.checar((select count(*) from public.notificacoes where posto_id = 9) = 0,
                      'primeiro preço oficial do posto não gera aviso');
insert into public.precos_anp (posto_id, produto_id, data_coleta, preco) values (9, 1, current_date - 1, 6.200);
select public.recalcular_precos_atuais();
select pg_temp.checar((select count(*) = 1 and min(preco_anterior) = 6.000 and min(preco_novo) = 6.200
                       from public.notificacoes where posto_id = 9),
                      'nova pesquisa da ANP com mudança de R$ 0,20 avisa quem favoritou');
select public.recalcular_precos_atuais();
select pg_temp.checar((select count(*) from public.notificacoes where posto_id = 9) = 1,
                      'recalcular de novo não repete o aviso');
delete from public.precos_anp where posto_id = 9;
select public.recalcular_precos_atuais();
select pg_temp.checar(not exists (select 1 from public.precos_atuais where posto_id = 9),
                      'posto que perdeu todas as fontes sai dos preços exibidos');
delete from public.postos where id = 9;   -- limpa o posto de teste (favoritos e avisos saem em cascata)

-- Estimativa com a pesquisa da ANP parada há mais de 60 dias: a janela é relativa ao dado mais novo
update public.precos_anp set data_coleta = data_coleta - 200;
select pg_temp.checar(public.recalcular_estimativas() >= 1,
                      'estimativa continua funcionando quando o dado da ANP é antigo');
select pg_temp.checar(exists (select 1 from public.precos_estimados where preco > 0),
                      'estimativa gerada a partir de pesquisa com mais de 60 dias de idade');
update public.precos_anp set data_coleta = data_coleta + 200;
select public.recalcular_estimativas();

-- ============================================================ regras de acesso (RLS)
do $$
declare
  n int;
  negado boolean := false;
begin
  set local role anon;
  select count(*) into n from public.postos;
  begin
    insert into public.avaliacoes (posto_id, usuario_id, nota) values (1, '00000000-0000-0000-0000-00000000000a', 5);
  exception when insufficient_privilege then
    negado := true;
  end;
  reset role;
  perform pg_temp.checar(n = 3, 'visitante sem login consulta os postos');
  perform pg_temp.checar(negado, 'visitante sem login não consegue avaliar');
end
$$;

do $$
declare
  negado_outro boolean := false;
  negado_pontos boolean := false;
  perfis_visiveis int;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}', true);
  set local role authenticated;
  insert into public.avaliacoes (posto_id, usuario_id, nota, comentario) values (1, '00000000-0000-0000-0000-00000000000a', 5, 'Atendimento rápido');
  begin
    insert into public.avaliacoes (posto_id, usuario_id, nota) values (2, '00000000-0000-0000-0000-00000000000b', 1);
  exception when insufficient_privilege then
    negado_outro := true;
  end;
  begin
    update public.perfis set pontos = 9999 where id = '00000000-0000-0000-0000-00000000000a';
  exception when insufficient_privilege then
    negado_pontos := true;
  end;
  update public.perfis set nome = 'Ana Paula Souza' where id = '00000000-0000-0000-0000-00000000000a';
  select count(*) into perfis_visiveis from public.perfis;
  reset role;
  perform pg_temp.checar(negado_outro, 'usuário não avalia em nome de outra pessoa');
  perform pg_temp.checar(negado_pontos, 'usuário não altera os próprios pontos');
  perform pg_temp.checar(perfis_visiveis = 1, 'usuário só enxerga o próprio perfil');
end
$$;
select pg_temp.checar((select nota_media = 5.00 and total_avaliacoes = 1 from public.postos where id = 1),
                      'nota média calculada no servidor');

do $$
declare
  alteradas int;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000b", "role": "authenticated"}', true);
  set local role authenticated;
  update public.avaliacoes set nota = 0 where posto_id = 1;
  get diagnostics alteradas = row_count;
  insert into public.avaliacao_votos (avaliacao_id, usuario_id)
  select id, '00000000-0000-0000-0000-00000000000b' from public.avaliacoes where posto_id = 1;
  reset role;
  perform pg_temp.checar(alteradas = 0, 'usuário não altera avaliação de outra pessoa');
end
$$;
select pg_temp.checar((select votos_uteis from public.avaliacoes where posto_id = 1) = 1, 'voto de "útil" contado');

-- ============================================================ consultas do app
do $$
declare
  n int;
  j jsonb;
  primeiro bigint;
begin
  set local role anon;
  select count(*) into n from public.postos_na_area(-3.80, -38.60, -3.70, -38.45);
  perform pg_temp.checar(n = 2, 'mapa traz os postos da área visível');
  select id into primeiro from public.postos_proximos(-3.73, -38.52, 5) limit 1;
  perform pg_temp.checar(primeiro = 1, 'lista de próximos começa pelo mais perto');
  select count(*) into n from public.buscar_postos('itaitinga');
  perform pg_temp.checar(n = 1, 'busca por cidade');
  select count(*) into n from public.buscar_postos('posto aldeota');
  perform pg_temp.checar(n = 1, 'busca com várias palavras');
  select count(*) into n from public.buscar_postos('a');
  perform pg_temp.checar(n = 0, 'busca exige pelo menos 2 letras');
  j := public.detalhe_posto(1);
  perform pg_temp.checar(jsonb_array_length(j -> 'precos') = 2 and (j ->> 'favorito')::boolean = false
                         and (j -> 'distribuicao_notas' ->> '5')::int = 1, 'detalhe do posto com preços e notas');
  select count(*) into n from public.historico_precos(1, 1::smallint, 30);
  perform pg_temp.checar(n = 3, 'histórico junta ANP e comunidade');
  select count(*) into n from public.contribuicoes(1, 1::smallint) where autor in ('Ana S.', 'Bruno L.', 'Carla M.');
  perform pg_temp.checar(n = 3, 'contribuições mostram nomes abreviados');
  select count(*) into n from public.avaliacoes_posto(1, 'relevantes');
  perform pg_temp.checar(n = 1, 'avaliações do posto');
  select count(*) into n from public.postos_por_ids(array[1, 3]::bigint[]);
  perform pg_temp.checar(n = 2, 'favoritos locais buscados por id');
  reset role;
end
$$;
select pg_temp.checar((select autor from public.ranking(10) limit 1) = 'Bruno L.', 'ranking ordenado por pontos');

do $$
declare
  j jsonb;
  n int;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}', true);
  set local role authenticated;
  j := public.meu_resumo();
  reset role;
  perform pg_temp.checar((j ->> 'pontos')::int = 75 and (j ->> 'total_avaliacoes')::int = 1 and (j ->> 'posicao_ranking')::int = 2,
                         'resumo do perfil com pontos, avaliações e posição');
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000d", "role": "authenticated"}', true);
  set local role authenticated;
  select count(*) into n from public.meus_favoritos();
  reset role;
  perform pg_temp.checar(n = 1, 'favoritos da conta');
end
$$;

-- ============================================================ precisão da localização dos postos
insert into public.postos (id, cnpj, razao_social, municipio, uf, localizacao, localizacao_fonte, precisao_localizacao) values
  (20, '20000000000191', 'POSTO RUA UM LTDA',        'FORTALEZA', 'CE', 'SRID=4326;POINT(-38.5200 -3.7500)', 'geocodificacao', 'rua'),
  (21, '21000000000191', 'POSTO CEP CIDADE LTDA',    'ITAITINGA', 'CE', 'SRID=4326;POINT(-38.5500 -3.9990)', 'geocodificacao', 'cep_cidade'),
  (22, '22000000000191', 'POSTO SEM POSICAO LTDA',   'ITAITINGA', 'CE', null, null, 'nenhuma');

do $$
declare
  n int;
  j jsonb;
  r record;
begin
  set local role anon;
  select count(*) into n from public.postos_na_area(-4.10, -38.70, -3.60, -38.40) where id in (20, 21, 22);
  perform pg_temp.checar(n = 1, 'mapa mostra posto de rua e esconde os de CEP da cidade e sem posição');
  select count(*) into n from public.postos_proximos(-3.75, -38.52, 80) where id in (21, 22);
  perform pg_temp.checar(n = 0, 'lista por distância também esconde os de posição fraca');
  select * into r from public.postos_na_area(-4.10, -38.70, -3.60, -38.40) where id = 20;
  perform pg_temp.checar(r.precisao = 'rua', 'o mapa informa a precisão da posição');
  select * into r from public.buscar_postos('sem posicao', -3.75, -38.52) where id = 22;
  perform pg_temp.checar(r.id = 22 and r.distancia_km is null and r.precisao = 'nenhuma',
                         'busca encontra o posto sem posição, sem distância');
  j := public.detalhe_posto(1);
  perform pg_temp.checar((j ->> 'raio_envio_m')::int = 300 and j ->> 'precisao' = 'exata', 'posição exata: envio em 300 m');
  j := public.detalhe_posto(20);
  perform pg_temp.checar((j ->> 'raio_envio_m')::int = 1000 and j ->> 'precisao' = 'rua', 'posição de rua: envio em 1 km');
  j := public.detalhe_posto(21);
  perform pg_temp.checar(j -> 'raio_envio_m' = 'null'::jsonb or j -> 'raio_envio_m' is null, 'CEP da cidade: não aceita envio');
  reset role;
end
$$;
select pg_temp.checar((select precisao = 'rua' and distancia_m < 1 from public.distancia_e_precisao(20, -3.75, -38.52)),
                      'validação do envio recebe distância e precisão do posto');
select pg_temp.checar((select distancia_m is null and precisao = 'nenhuma' from public.distancia_e_precisao(22, -3.75, -38.52)),
                      'posto sem posição não tem distância');

-- "Estou neste posto": posição informada por quem está lá
select pg_temp.checar((public.registrar_correcao_posicao('00000000-0000-0000-0000-00000000000a', 1, -3.73, -38.527) ->> 'motivo') = 'posicao_confirmada',
                      'posto de posição exata não aceita correção');
select pg_temp.checar((public.registrar_correcao_posicao('00000000-0000-0000-0000-00000000000a', 21, -1.0, -38.55) ->> 'motivo') = 'longe_do_posto',
                      'posição a mais de 100 km da aproximada é recusada');
select pg_temp.checar((public.registrar_correcao_posicao('00000000-0000-0000-0000-00000000000a', 22, -3.9900, -38.5400) ->> 'status') = 'aguardando',
                      'primeira pessoa informa a posição e o posto aguarda confirmação');
select pg_temp.checar((public.registrar_correcao_posicao('00000000-0000-0000-0000-00000000000a', 22, -3.9901, -38.5401) ->> 'status') = 'aguardando'
                      and (select count(*) from public.correcoes_posicao where posto_id = 22) = 1,
                      'a mesma pessoa informando de novo atualiza a posição e não conta duas vezes');
select pg_temp.checar((select precisao_localizacao = 'nenhuma' and localizacao is null from public.postos where id = 22),
                      'enquanto aguarda, a posição do posto não muda');
create temp table pontos_antes as select id, pontos from public.perfis;
select pg_temp.checar((public.registrar_correcao_posicao('00000000-0000-0000-0000-00000000000d', 22, -3.9902, -38.5402) ->> 'status') = 'confirmada',
                      'segunda pessoa a menos de 150 m confirma a posição');
select pg_temp.checar((select precisao_localizacao = 'exata' and localizacao_fonte = 'usuario' and localizacao_validada
                              and extensions.st_distance(localizacao, 'SRID=4326;POINT(-38.5401 -3.9901)'::extensions.geography) < 50
                       from public.postos where id = 22),
                      'posto passa a ter posição exata, no meio das duas informadas');
select pg_temp.checar((select p.pontos - a.pontos = 5 from public.perfis p join pontos_antes a using (id)
                       where p.id = '00000000-0000-0000-0000-00000000000d'),
                      'quem confirma a posição ganha 5 pontos');
select pg_temp.checar((select count(*) from public.correcoes_posicao where posto_id = 22 and status = 'confirmada') = 2,
                      'as duas posições ficam como confirmadas');
select pg_temp.checar((public.registrar_correcao_posicao('00000000-0000-0000-0000-00000000000b', 22, -3.99, -38.54) ->> 'motivo') = 'posicao_confirmada',
                      'depois de confirmada, a posição não aceita nova correção');

-- Duas posições distantes não se confirmam; a terceira, perto da primeira, confirma e encerra a que discorda
select public.registrar_correcao_posicao('00000000-0000-0000-0000-00000000000a', 20, -3.7500, -38.5200);
select pg_temp.checar((public.registrar_correcao_posicao('00000000-0000-0000-0000-00000000000d', 20, -3.7900, -38.5200) ->> 'status') = 'aguardando',
                      'posições a mais de 150 m uma da outra não se confirmam');
select pg_temp.checar((public.registrar_correcao_posicao('00000000-0000-0000-0000-00000000000b', 20, -3.7501, -38.5201) ->> 'status') = 'confirmada',
                      'a terceira posição, perto da primeira, confirma');
select pg_temp.checar((select status = 'contestada' from public.correcoes_posicao
                       where posto_id = 20 and usuario_id = '00000000-0000-0000-0000-00000000000d'),
                      'a posição que discorda do consenso é encerrada como contestada');
select pg_temp.checar((select count(*) from public.correcoes_posicao where posto_id = 20 and status = 'pendente') = 0,
                      'nenhuma posição fica pendente depois do consenso');

-- Limite diário
do $$
declare i int; r jsonb;
begin
  for i in 1..10 loop
    insert into public.postos (id, cnpj, razao_social, municipio, uf, precisao_localizacao)
    values (100 + i, '1000000000' || lpad(i::text, 4, '0'), 'POSTO LOTE ' || i, 'ITAITINGA', 'CE', 'nenhuma');
    perform public.registrar_correcao_posicao('00000000-0000-0000-0000-00000000000c', 100 + i, -3.9, -38.5);
  end loop;
  insert into public.postos (id, cnpj, razao_social, municipio, uf, precisao_localizacao)
  values (111, '10000000009999', 'POSTO LOTE 11', 'ITAITINGA', 'CE', 'nenhuma');
  r := public.registrar_correcao_posicao('00000000-0000-0000-0000-00000000000c', 111, -3.9, -38.5);
  perform pg_temp.checar(r ->> 'motivo' = 'limite_diario', 'cada pessoa informa no máximo 10 posições por dia');
end
$$;

-- ============================================================ importação do cadastro da ANP
update public.postos set localizacao_fonte = 'usuario', localizacao = 'SRID=4326;POINT(-38.5 -3.7)' where id = 1;
select pg_temp.checar(public.importar_postos_anp('CE', '[
  {"cnpj": "11111111000191", "razao_social": "POSTO CENTRO LTDA", "bandeira": "SHELL", "endereco": "AV DUQUE DE CAXIAS, 100",
   "complemento": "", "bairro": "CENTRO", "municipio": "FORTALEZA", "cep": "60035111", "lat": -3.7301, "lon": -38.5271,
   "validada": true, "autorizacao": "PR/CE001", "produtos": [{"produto_id": 1, "bicos": 4}, {"produto_id": 5, "bicos": 2}]},
  {"cnpj": "44444444000191", "razao_social": "POSTO NOVO LTDA", "bandeira": "Bandeira branca", "endereco": "RUA NOVA, 1",
   "complemento": null, "bairro": "MESSEJANA", "municipio": "FORTALEZA", "cep": "60840000", "lat": -3.83, "lon": -38.49,
   "validada": false, "autorizacao": "PR/CE002", "produtos": [{"produto_id": 1, "bicos": 2}]}
]'::jsonb, true) = 2, 'importação do cadastro grava 2 postos');
select pg_temp.checar((select bandeira = 'SHELL' and localizacao_fonte = 'usuario'
                       and abs(extensions.st_y(localizacao::extensions.geometry) - (-3.7)) < 0.0001
                       from public.postos where id = 1),
                      'cadastro atualiza bandeira e preserva a posição corrigida por usuário');
select pg_temp.checar((select array_agg(produto_id order by produto_id) = '{1,5}'::smallint[] from public.posto_produtos where posto_id = 1),
                      'combustíveis vendidos seguem o cadastro da ANP');
select pg_temp.checar((select localizacao is not null and ativo from public.postos where cnpj = '44444444000191'),
                      'posto novo do cadastro entra com localização');
select pg_temp.checar(not (select ativo from public.postos where id = 2), 'posto que saiu do cadastro fica inativo');
select pg_temp.checar((select count(*) from cron.job) = 4, 'quatro tarefas agendadas registradas');
select pg_temp.checar((select precisao_localizacao = 'exata' from public.postos where cnpj = '44444444000191'),
                      'posto novo do cadastro com coordenada da ANP entra com posição exata');
select pg_temp.checar(public.importar_postos_anp('CE', '[
  {"cnpj": "21000000000191", "razao_social": "POSTO CEP CIDADE LTDA", "bandeira": "Bandeira branca", "endereco": "RUA A, 1",
   "complemento": null, "bairro": "CENTRO", "municipio": "ITAITINGA", "cep": "61880000", "lat": -3.9700, "lon": -38.5300,
   "validada": false, "autorizacao": "PR/CE003", "produtos": [{"produto_id": 1, "bicos": 2}]}
]'::jsonb, false) = 1, 'importação de um posto que já tinha posição aproximada');
select pg_temp.checar((select precisao_localizacao = 'exata' and localizacao_fonte = 'anp' from public.postos where id = 21),
                      'coordenada da ANP substitui a posição aproximada');
select pg_temp.checar((select precisao_localizacao = 'exata' and localizacao_fonte = 'usuario' from public.postos where id = 22),
                      'posição confirmada por usuários não é trocada pela sincronização');

-- ============================================================ correções da auditoria (06/10/2026)
-- BUG-01: envio numa só transação, com limite diário e regra de 6 h
do $$
declare r jsonb;
begin
  r := public.registrar_envio('00000000-0000-0000-0000-00000000000c', 1, -3.7301, -38.5271, 15, '[{"produto_id": 2, "preco": 6.30}]'::jsonb);
  perform pg_temp.checar((r ->> 'ok')::boolean and r -> 'itens' -> 0 ->> 'status' = 'pendente', 'registrar_envio grava o envio e devolve os itens');
  r := public.registrar_envio('00000000-0000-0000-0000-00000000000c', 1, -3.7301, -38.5271, 15, '[{"produto_id": 2, "preco": 6.31}]'::jsonb);
  perform pg_temp.checar(r ->> 'motivo' = 'repetido', 'mesmo combustível no mesmo posto em menos de 6 h é recusado');
  r := public.registrar_envio('00000000-0000-0000-0000-00000000000c', 1, -3.7301, -38.5271, 15,
                              '[{"produto_id": 2, "preco": 6.31}, {"produto_id": 4, "preco": 6.10}]'::jsonb);
  perform pg_temp.checar((r ->> 'ok')::boolean and r -> 'ignorados' = '[2]'::jsonb and jsonb_array_length(r -> 'itens') = 1,
                         'envio misto ignora o combustível repetido e grava o novo');
  insert into public.envios (usuario_id, posto_id, posicao, distancia_m)
  select '00000000-0000-0000-0000-00000000000c', 1, 'SRID=4326;POINT(-38.52 -3.73)', 10 from generate_series(1, 20);
  r := public.registrar_envio('00000000-0000-0000-0000-00000000000c', 2, -3.7350, -38.5100, 15, '[{"produto_id": 3, "preco": 4.30}]'::jsonb);
  perform pg_temp.checar(r ->> 'motivo' = 'limite_diario', 'limite de 20 envios em 24 horas vale dentro da função');
end
$$;

-- BUG-01: dois envios da mesma pessoa no mesmo consenso rendem pontos uma vez só
select pg_temp.enviar('00000000-0000-0000-0000-00000000000a', 3, 3, 4.10);
select pg_temp.enviar('00000000-0000-0000-0000-00000000000a', 3, 3, 4.11);
select pg_temp.enviar('00000000-0000-0000-0000-00000000000b', 3, 3, 4.10);
select pg_temp.checar((select count(*) from public.envio_itens where posto_id = 3 and produto_id = 3 and status = 'confirmado') = 3,
                      'os três envios do consenso ficam confirmados');
select pg_temp.checar((select count(*) from public.pontos_movimentos m join public.envio_itens i on i.id = m.envio_item_id
                       where i.posto_id = 3 and i.produto_id = 3 and m.tipo = 'confirmado'
                         and m.usuario_id = '00000000-0000-0000-0000-00000000000a') = 1,
                      'quem tinha dois envios no consenso ganha os pontos uma vez só');

-- BUG-02: coordenada da ANP só vale dentro do estado e fora dos pontos de valor padrão
select pg_temp.checar(public.coordenada_confiavel('CE', 'SRID=4326;POINT(-38.5271 -3.7301)'), 'coordenada de Fortaleza vale para o CE');
select pg_temp.checar(not public.coordenada_confiavel('AM', 'SRID=4326;POINT(-43.20 -22.90)'), 'coordenada do Rio não vale para posto do AM');
select pg_temp.checar(not public.coordenada_confiavel('RJ', 'SRID=4326;POINT(-43.3371 -22.7780)'), 'ponto padrão da API da ANP nunca vale');
select pg_temp.checar(public.coordenada_confiavel('PE', 'SRID=4326;POINT(-32.401 -3.836)'), 'Fernando de Noronha vale para PE');
select pg_temp.checar(public.coordenada_confiavel('AM', 'SRID=4326;POINT(-71.688 -7.056)'), 'Ipixuna, na divisa com o AC, vale para o AM');
insert into public.postos (id, cnpj, razao_social, municipio, uf, localizacao, localizacao_fonte, precisao_localizacao) values
  (200, '20000000000200', 'POSTO PONTO PADRAO LTDA', 'IPIXUNA', 'AM', 'SRID=4326;POINT(-43.3371 -22.7780)', 'anp', 'exata');
select public.importar_postos_anp('AM', '[
  {"cnpj": "20000000000200", "razao_social": "POSTO PONTO PADRAO LTDA", "municipio": "IPIXUNA", "lat": -22.7780, "lon": -43.3371,
   "validada": true, "produtos": []},
  {"cnpj": "20000000000201", "razao_social": "POSTO NO RIO LTDA", "municipio": "EIRUNEPE", "lat": -22.90, "lon": -43.20,
   "validada": true, "produtos": []},
  {"cnpj": "20000000000202", "razao_social": "POSTO CERTO LTDA", "municipio": "IPIXUNA", "lat": -7.056, "lon": -71.688,
   "validada": false, "produtos": []}
]'::jsonb, false);
select pg_temp.checar((select localizacao is null and precisao_localizacao = 'nenhuma' and localizacao_fonte is null
                       from public.postos where id = 200),
                      'coordenada ruim já gravada é limpa na sincronização');
select pg_temp.checar((select localizacao is null and precisao_localizacao = 'nenhuma' from public.postos where cnpj = '20000000000201'),
                      'posto novo com coordenada fora do estado entra sem posição');
select pg_temp.checar((select localizacao is not null and precisao_localizacao = 'exata' from public.postos where cnpj = '20000000000202'),
                      'posto novo com coordenada dentro do estado entra com posição exata');

-- BUG-05 e BUG-08: quem avaliou e quem votou não é público; ninguém vota na própria avaliação
do $$
declare
  negado_coluna boolean := false;
  notas int;
  alteradas int;
  negado_voto boolean := false;
  votos_visiveis int;
begin
  set local role anon;
  begin
    perform usuario_id from public.avaliacoes;
  exception when insufficient_privilege then
    negado_coluna := true;
  end;
  select count(nota) into notas from public.avaliacoes;
  select count(*) into votos_visiveis from public.avaliacao_votos;
  reset role;
  perform pg_temp.checar(negado_coluna, 'visitante não lê quem fez cada avaliação');
  perform pg_temp.checar(notas >= 1, 'visitante continua lendo nota e comentário');
  perform pg_temp.checar(votos_visiveis = 0, 'visitante não vê os votos de útil');

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}', true);
  set local role authenticated;
  update public.avaliacoes set nota = 4 where id = (select id from public.avaliacoes where posto_id = 1);
  get diagnostics alteradas = row_count;
  begin
    insert into public.avaliacao_votos (avaliacao_id, usuario_id)
    select id, '00000000-0000-0000-0000-00000000000a' from public.avaliacoes where posto_id = 1;
  exception when insufficient_privilege then
    negado_voto := true;
  end;
  reset role;
  perform pg_temp.checar(alteradas = 1, 'autora continua editando a própria avaliação');
  perform pg_temp.checar(negado_voto, 'autora não vota na própria avaliação');

  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000b", "role": "authenticated"}', true);
  set local role authenticated;
  select count(*) into votos_visiveis from public.avaliacao_votos;
  delete from public.avaliacao_votos where usuario_id = '00000000-0000-0000-0000-00000000000b';
  get diagnostics alteradas = row_count;
  reset role;
  perform pg_temp.checar(votos_visiveis = 1, 'usuário vê só os próprios votos');
  perform pg_temp.checar(alteradas = 1, 'usuário retira o próprio voto');
end
$$;

\echo 'TODOS OS TESTES PASSARAM'
