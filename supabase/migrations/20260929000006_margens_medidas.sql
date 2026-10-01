-- As margens de erro da estimativa vinham do estudo por município (erro de estimar a mediana de 12 meses
-- de uma cidade pela cidade pesquisada mais próxima). A rotina, porém, estima por posto, com a mediana dos
-- 5 postos pesquisados mais próximos, e isso erra mais.
--
-- Medido em 29/09/2026 nos dados reais carregados: 3.951 postos pesquisados de gasolina comum, etanol e
-- diesel S10, cada um estimado só pelos vizinhos de OUTRO município (o que acontece com um posto sem pesquisa),
-- pesquisa de 01/05 a 30/06/2026:
--   faixa de distância   casos   erro médio   erro que 9 em 10 casos não passam
--   até 25 km            2.233   R$ 0,247     R$ 0,60
--   25 a 50 km             686   R$ 0,289     R$ 0,60
--   50 a 100 km            726   R$ 0,300     R$ 0,62
--   100 a 200 km           306   R$ 0,386     R$ 0,87
-- A coluna margem passa a guardar o erro médio medido, arredondado para cima. O app mostra "erro médio".
create or replace function public.recalcular_estimativas()
returns integer
language plpgsql
security definer
set search_path = public, extensions
set statement_timeout = '15min'
as $$
declare
  v_total integer;
  v_ref_ate date;
begin
  select max(data_coleta) into v_ref_ate from public.precos_anp where not anomalia;

  if to_regclass('pg_temp.ref') is not null then drop table pg_temp.ref; end if;
  create temporary table ref on commit drop as
  select distinct on (a.posto_id, a.produto_id) a.posto_id, a.produto_id, a.preco, p.localizacao
  from public.precos_anp a
  join public.postos p on p.id = a.posto_id
  where not a.anomalia and a.data_coleta >= v_ref_ate - 60 and p.localizacao is not null
  order by a.posto_id, a.produto_id, a.data_coleta desc;
  create index on ref using gist (localizacao);
  create index on ref (produto_id);

  delete from public.precos_estimados;

  insert into public.precos_estimados (posto_id, produto_id, preco, margem, distancia_km)
  select alvo.posto_id, alvo.produto_id, round(viz.mediana::numeric, 3),
         case when viz.dist_km < 25 then 0.25 when viz.dist_km < 50 then 0.29
              when viz.dist_km < 100 then 0.30 else 0.39 end,
         round(viz.dist_km::numeric, 1)
  from (
    select pp.posto_id, pp.produto_id, p.localizacao
    from public.posto_produtos pp
    join public.postos p on p.id = pp.posto_id
    where p.ativo and p.localizacao is not null
      and not exists (select 1 from ref r where r.posto_id = pp.posto_id and r.produto_id = pp.produto_id)
  ) alvo
  cross join lateral (
    select percentile_cont(0.5) within group (order by k.preco) as mediana, min(k.dist) / 1000 as dist_km
    from (
      select r.preco, st_distance(r.localizacao, alvo.localizacao) as dist
      from ref r
      where r.produto_id = alvo.produto_id
      order by r.localizacao <-> alvo.localizacao
      limit 5
    ) k
    where k.dist <= 200000
  ) viz
  where viz.mediana is not null;

  get diagnostics v_total = row_count;
  return v_total;
end;
$$;

revoke execute on function public.recalcular_estimativas() from public, anon, authenticated;
