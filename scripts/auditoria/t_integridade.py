"""
Integridade dos dados reais (somente leitura), agendamentos e configuração do banco.
Os postos e usuários da auditoria são excluídos das contagens.
"""
from __future__ import annotations

from datetime import date

from comum import ALTA, BAIXA, CRITICA, MEDIA

REAIS = "p.cnpj not like '99999999%%'"


def rodar(s, ctx) -> None:
    db = ctx["db"]
    db.execute("set statement_timeout = '600s'")
    B = dict(aba="Banco de Dados", modulo="Integridade dos dados")

    def consulta(cen, sql, criterio, esp, sev, tela="Banco", tipo="Banco · integridade", obs=""):
        try:
            linhas = db.execute(sql).fetchall()
            ok = criterio(linhas)
            s.check(ok, obtido=str(linhas)[:600], **B, tela=tela, tipo=tipo, cenario=cen, precondicoes="Dados reais do projeto",
                    passos="Consulta SQL somente leitura", entrada=" ".join(sql.split())[:700], esperado=esp, severidade=sev, obs=obs)
        except Exception as e:  # noqa: BLE001
            s.add(status="BLOCKED", obtido=f"Erro ao consultar: {e}"[:400], **B, tela=tela, tipo=tipo, cenario=cen,
                  precondicoes="Dados reais", passos="Consulta SQL", entrada=sql[:400], esperado=esp, severidade=sev)

    zero = lambda l: l[0][0] == 0  # noqa: E731

    consulta("Toda tabela do schema public tem RLS ligado",
             "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and not c.relrowsecurity",
             zero, "0 tabelas sem RLS", CRITICA, tela="Catálogo", tipo="Segurança · configuração")
    consulta("Nenhuma função security definer sem search_path fixo",
             """select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                where n.nspname='public' and p.prosecdef and not exists
                (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%%')""",
             zero, "0 funções", ALTA, tela="Catálogo", tipo="Segurança · configuração")
    consulta("Postos ativos com posição exata têm coordenada",
             f"select count(*) from public.postos p where {REAIS} and ativo and precisao_localizacao in ('exata','rua','cep_rua') and localizacao is null",
             zero, "0", ALTA, tela="Tabela postos")
    consulta("Postos sem local (nenhuma) não têm coordenada antiga esquecida",
             f"select count(*) from public.postos p where {REAIS} and precisao_localizacao = 'nenhuma' and localizacao is not null",
             zero, "0", MEDIA, tela="Tabela postos")
    consulta("Coordenadas dos postos caem dentro do Brasil",
             f"""select count(*) from public.postos p where {REAIS} and localizacao is not null and
                (st_y(localizacao::extensions.geometry) not between -34 and 5.5 or st_x(localizacao::extensions.geometry) not between -74.5 and -28.5)""",
             zero, "0 fora da caixa do Brasil", MEDIA, tela="Tabela postos")
    consulta("Coordenadas da ANP caem dentro do contorno do próprio estado (malha do IBGE, 15 km de tolerância)",
             f"""select count(*) from public.postos p
                where {REAIS} and p.ativo and p.localizacao is not null and coalesce(p.localizacao_fonte, 'anp') <> 'usuario'
                  and not public.coordenada_confiavel(p.uf, p.localizacao)""",
             zero, "0 postos com coordenada fora do próprio estado ou num ponto padrão da API", ALTA, tela="Tabela postos",
             obs="Usa a mesma regra do importador (coordenada_confiavel). Na auditoria de 06/10 a checagem era aproximada "
                 "(distância ao centro dos postos da UF) e apontou 132 postos; ela dava falso alarme no oeste do Amazonas, "
                 "a mais de 1.000 km de Manaus.")
    consulta("Nenhuma coordenada é compartilhada por postos de UFs diferentes (valor padrão da API tratado como posição)",
             f"""select coalesce(sum(n), 0)::int from (select count(*) n from public.postos p where {REAIS} and ativo and localizacao is not null
                group by localizacao having count(distinct uf) > 1) x""",
             zero, "0 postos", ALTA, tela="Importação ANP · tabela postos",
             obs="Um mesmo ponto usado por postos de vários estados é um valor padrão da API, não uma posição real.")
    consulta("Coordenada repetida em postos de UFs diferentes: o ponto e quantos postos",
             f"""select round(st_y(localizacao::extensions.geometry)::numeric, 4), round(st_x(localizacao::extensions.geometry)::numeric, 4),
                       count(*), count(distinct uf) from public.postos p where {REAIS} and ativo and localizacao is not null
                group by localizacao having count(distinct uf) > 1 order by 3 desc""",
             lambda l: True, "Informativo", BAIXA, tela="Importação ANP · tabela postos")
    consulta("CNPJ com 14 dígitos numéricos", f"select count(*) from public.postos p where {REAIS} and cnpj !~ '^[0-9]{{14}}$'",
             zero, "0", MEDIA, tela="Tabela postos")
    consulta("Preços exibidos dentro da faixa do combustível",
             """select count(*) from public.precos_atuais a join public.produtos pr on pr.id=a.produto_id
                where a.preco < pr.preco_min or a.preco > pr.preco_max""", zero, "0", ALTA, tela="Tabela precos_atuais")
    consulta("Nenhum preço exibido vem de preço da ANP marcado como anomalia",
             """select count(*) from public.precos_atuais a where a.fonte='anp' and exists (select 1 from public.precos_anp x
                where x.posto_id=a.posto_id and x.produto_id=a.produto_id and x.anomalia and x.preco=a.preco
                and not exists (select 1 from public.precos_anp y where y.posto_id=a.posto_id and y.produto_id=a.produto_id and not y.anomalia and y.preco=a.preco))""",
             zero, "0", ALTA, tela="Tabela precos_atuais")
    consulta("Preço exibido aponta para posto ativo",
             "select count(*) from public.precos_atuais a join public.postos p on p.id=a.posto_id where not p.ativo",
             lambda l: True, "Informativo: quantos preços de postos inativos continuam na tabela (não aparecem no mapa)", BAIXA,
             tela="Tabela precos_atuais")
    consulta("Estimativas têm margem e distância coerentes",
             "select count(*) from public.precos_estimados where margem <= 0 or distancia_km < 0 or distancia_km > 200",
             zero, "0 (vizinhos até 200 km)", MEDIA, tela="Tabela precos_estimados")
    db.execute("drop table if exists pg_temp.aud_ref")
    db.execute("""create temp table aud_ref as
                  select distinct x.produto_id, q.localizacao from public.precos_anp x join public.postos q on q.id = x.posto_id
                  where q.localizacao is not null and not x.anomalia
                    and x.data_coleta >= (select max(data_coleta) from public.precos_anp) - 60""")
    db.execute("create index on pg_temp.aud_ref using gist (localizacao)")
    db.execute("analyze pg_temp.aud_ref")
    consulta("Combustível vendido por posto com coordenada, sem preço exibido, mas com referência do mesmo combustível a até 200 km",
             f"""select count(*) from public.posto_produtos pp join public.postos p on p.id = pp.posto_id
                where {REAIS} and p.ativo and p.localizacao is not null
                  and not exists (select 1 from public.precos_atuais a where a.posto_id = pp.posto_id and a.produto_id = pp.produto_id)
                  and exists (select 1 from pg_temp.aud_ref r where r.produto_id = pp.produto_id
                              and extensions.st_dwithin(r.localizacao, p.localizacao, 200000))""",
             zero, "0 (a estimativa deveria cobrir cada um)", MEDIA, tela="Cobertura de preços",
             obs="Regra: estimativa por combustível para posto ativo com coordenada, com referência do mesmo combustível a até 200 km.")
    consulta("Postos ativos com coordenada sem preço exibido, por motivo",
             f"""select case when not exists (select 1 from public.posto_produtos pp where pp.posto_id=p.id)
                             then 'sem combustível no cadastro da ANP' else 'vende combustível' end, count(*)
                from public.postos p where {REAIS} and p.ativo and p.localizacao is not null
                  and not exists (select 1 from public.precos_atuais a where a.posto_id=p.id) group by 1""",
             lambda l: True, "Informativo", BAIXA, tela="Cobertura de preços")
    consulta("Nota média e total de avaliações batem com as avaliações",
             f"""select count(*) from public.postos p where {REAIS} and (total_avaliacoes <> (select count(*) from public.avaliacoes a where a.posto_id=p.id)
                or coalesce(nota_media, -1) <> coalesce((select round(avg(nota)::numeric, 2) from public.avaliacoes a where a.posto_id=p.id), -1))""",
             zero, "0 divergências", MEDIA, tela="Tabela postos")
    consulta("Todo usuário do Auth tem perfil", "select count(*) from auth.users u where not exists (select 1 from public.perfis p where p.id=u.id)",
             zero, "0", ALTA, tela="Gatilho criar_perfil")
    consulta("Pontos do perfil batem com o extrato (usuários reais)",
             """select count(*) from public.perfis p where p.id not in (select id from auth.users where email like '%%@auditoria.gasprice.test')
                and p.pontos <> greatest(0, coalesce((select sum(m.pontos) from public.pontos_movimentos m where m.usuario_id=p.id), 0))""",
             zero, "0 divergências", MEDIA, tela="Tabela perfis")
    hoje = date.today()
    consulta("Pesquisa da ANP no banco está atualizada (coleta mais recente com até 14 dias)",
             "select max(data_coleta) from public.precos_anp",
             lambda l: l[0][0] is not None and (hoje - l[0][0]).days <= 14, "Coleta mais recente há no máximo 14 dias", ALTA,
             tela="Tabela precos_anp", tipo="Dados · atualização",
             obs="A ANP publica a pesquisa toda semana; o app pinta de vermelho preço oficial com mais de 7 dias.")
    consulta("Parâmetros obrigatórios presentes (25)", "select count(*) from public.parametros where chave not like 'auditoria%%'",
             lambda l: l[0][0] == 25, "25 parâmetros", ALTA, tela="Tabela parametros")
    consulta("Agendamentos ativos (4)", "select count(*) from cron.job where active", lambda l: l[0][0] == 4, "4 jobs ativos", ALTA,
             tela="pg_cron", tipo="Agendamento")
    consulta("Última execução de cada agendamento terminou sem erro",
             """select j.jobname, d.status, d.start_time::text, left(d.return_message, 120) from cron.job j
                left join lateral (select * from cron.job_run_details r where r.jobid=j.jobid order by r.start_time desc limit 1) d on true
                order by 1""",
             lambda l: all(x[1] in (None, "succeeded") for x in l), "status succeeded (ou ainda sem execução)", ALTA,
             tela="pg_cron", tipo="Agendamento")
    consulta("Fechamento de envios antigos rodou na última hora e meia",
             """select max(d.start_time) > now() - interval '90 minutes' from cron.job j join cron.job_run_details d on d.jobid=j.jobid
                where j.jobname='gasprice-fechar-envios'""",
             lambda l: l[0][0] is True, "Execução recente", MEDIA, tela="pg_cron", tipo="Agendamento")
    consulta("Sincronização do cadastro: última execução de cada UF sem erro",
             "select count(*) filter (where erro is not null), count(*), min(executado_em)::text from public.sincronizacoes_anp",
             lambda l: l[0][0] == 0, "0 UFs com erro", MEDIA, tela="Tabela sincronizacoes_anp", tipo="Agendamento")
    consulta("Endereço do projeto e segredo da sincronização guardados no Vault (usados pelo agendamento)",
             "select count(*) from vault.secrets where name in ('project_url', 'cron_secret')",
             lambda l: l[0][0] == 2, "2 segredos: project_url e cron_secret", ALTA, tela="Vault", tipo="Segurança · configuração")
    consulta("Tamanho do banco dentro do plano gratuito (500 MB)",
             "select pg_database_size(current_database()) / 1024 / 1024", lambda l: l[0][0] < 450, "Menos de 450 MB (folga de 10%)",
             ALTA, tela="Banco", tipo="Capacidade")
    consulta("Índices espaciais e de busca presentes",
             "select count(*) from pg_indexes where schemaname='public' and indexname in ('postos_localizacao_idx','postos_busca_idx','envio_itens_posto_idx','precos_atuais_produto_idx')",
             lambda l: l[0][0] == 4, "4 índices", MEDIA, tela="Catálogo", tipo="Performance · índices")
    consulta("Nenhum índice inválido", "select count(*) from pg_index where not indisvalid", zero, "0", MEDIA, tela="Catálogo",
             tipo="Performance · índices")
