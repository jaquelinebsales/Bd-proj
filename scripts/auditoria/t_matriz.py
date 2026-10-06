"""
Matriz de acesso do visitante (chave publicável, sem login): ler, inserir, alterar e apagar em cada tabela.

Toda tabela tem pelo menos uma linha criada pela auditoria como alvo, para que "nenhuma linha alterada"
signifique permissão negada e não tabela vazia. O efeito de cada escrita é conferido direto no banco.
"""
from __future__ import annotations

import json

from comum import ALTA, BAIXA, CRITICA, http, resumo

PUBLICAS = ["produtos", "postos", "posto_produtos", "precos_anp", "precos_comunidade", "precos_estimados",
            "precos_atuais", "avaliacoes", "avaliacao_votos", "previsoes", "parametros"]
PRIVADAS = ["perfis", "envios", "envio_itens", "favoritos", "pontos_movimentos", "notificacoes",
            "correcoes_posicao", "sincronizacoes_anp"]
CRITICAS = {"precos_atuais", "postos", "parametros", "perfis", "envios", "envio_itens", "pontos_movimentos", "precos_anp"}


def _negado_ou_vazio(r) -> bool:
    return r.status in (401, 403) or (r.status in (200, 204) and (r.corpo in (None, []) or r.texto.strip() in ("", "[]")))


def rodar(s, ctx) -> None:
    db, p, u = ctx["db"], ctx["postos"], ctx["usuarios"]
    alvo, ana = p["exata"], u["ana"]["id"]
    envio = db.execute("select id::text from public.envios where posto_id=%s limit 1", (alvo,)).fetchone()
    envio_id = envio[0] if envio else "00000000-0000-0000-0000-000000000000"
    db.execute("insert into public.parametros (chave, valor, descricao) values ('auditoria_alvo', 1, 'alvo do teste') on conflict do nothing")
    ponto = "SRID=4326;POINT(-59.5 -10.5)"

    # tabela: (filtro do alvo, corpo de inserção válido, alteração)
    casos = {
        "produtos": ("id=eq.1", {"id": 99, "codigo": "XX", "nome": "Invasor", "preco_min": 1, "preco_max": 2, "ordem": 9}, {"nome": "Gasolina comum"}),
        "postos": (f"id=eq.{alvo}", {"cnpj": "99999999009999", "razao_social": "INVASOR", "municipio": "X", "uf": "RO"}, {"nome_exibicao": "Invadido"}),
        "posto_produtos": (f"posto_id=eq.{alvo}", {"posto_id": alvo, "produto_id": 2, "bicos": 1}, {"bicos": 9}),
        "precos_anp": (f"posto_id=eq.{alvo}", {"posto_id": alvo, "produto_id": 1, "data_coleta": "2026-10-01", "preco": 1}, {"preco": 0.5}),
        "precos_comunidade": (f"posto_id=eq.{alvo}", {"posto_id": alvo, "produto_id": 2, "dia": "2026-10-01", "preco": 1, "envios": 1, "usuarios": 1, "confirmado": True}, {"preco": 0.5}),
        "precos_estimados": (f"posto_id=eq.{alvo}", {"posto_id": alvo, "produto_id": 3, "preco": 1, "margem": 0.1, "distancia_km": 1}, {"preco": 0.5}),
        "precos_atuais": (f"posto_id=eq.{alvo}", {"posto_id": alvo, "produto_id": 6, "preco": 0.5, "fonte": "comunidade", "situacao": "confirmado", "atualizado_em": "2026-10-06T00:00:00Z"}, {"preco": 0.5}),
        "avaliacoes": (f"posto_id=eq.{alvo}", {"posto_id": p["rua"], "usuario_id": ana, "nota": 0}, {"nota": 0}),
        "avaliacao_votos": ("usuario_id=not.is.null", {"avaliacao_id": ctx.get("avaliacao_ana") or 0, "usuario_id": ana}, {"criado_em": "2020-01-01T00:00:00Z"}),
        "previsoes": ("municipio=eq.Auditoria", {"uf": "RO", "municipio": "Invasor", "produto_id": 1, "semana": "2026-10-05", "preco_previsto": 1, "modelo": "x"}, {"preco_previsto": 0.5}),
        "parametros": ("chave=eq.auditoria_alvo", {"chave": "auditoria_invasor", "valor": 1, "descricao": "x"}, {"valor": 999}),
        "perfis": ("id=not.is.null", {"id": "00000000-0000-0000-0000-000000000000", "nome": "Invasor"}, {"nome": "Invadido"}),
        "envios": ("usuario_id=not.is.null", {"posto_id": alvo, "usuario_id": ana, "posicao": ponto, "distancia_m": 0}, {"distancia_m": 0}),
        "envio_itens": ("usuario_id=not.is.null", {"envio_id": envio_id, "posto_id": alvo, "produto_id": 2, "usuario_id": ana, "preco": 5}, {"status": "confirmado"}),
        "favoritos": ("usuario_id=not.is.null", {"usuario_id": ana, "posto_id": p["rua"]}, {"notificar": False}),
        "pontos_movimentos": ("usuario_id=not.is.null", {"usuario_id": ana, "tipo": "x", "pontos": 1000, "descricao": "x"}, {"pontos": 9999}),
        "notificacoes": ("usuario_id=not.is.null", {"usuario_id": ana, "posto_id": alvo, "produto_id": 1, "preco_anterior": 1, "preco_novo": 2}, {"lida": True}),
        "correcoes_posicao": ("usuario_id=not.is.null", {"posto_id": p["sem_local"], "usuario_id": ana, "posicao": ponto}, {"status": "confirmada"}),
        "sincronizacoes_anp": ("uf=eq.CE", {"uf": "ZZ"}, {"erro": "invadido"}),
    }
    for t in PUBLICAS + PRIVADAS:
        publica = t in PUBLICAS
        filtro, corpo, mud = casos[t]
        alvos = db.execute(f"select count(*) from public.{t} where " + _sql(filtro)).fetchone()[0]

        # avaliacoes: só as colunas públicas (quem avaliou não é público; testado à parte em t_seguranca.exposicao)
        colunas = "id,posto_id,nota,comentario,votos_uteis,criado_em" if t == "avaliacoes" else "*"
        r = http("GET", f"/rest/v1/{t}?select={colunas}&limit=5")
        ok = (r.status == 200 and isinstance(r.corpo, list)) if publica else (r.status in (401, 403) or (r.status == 200 and r.corpo == []))
        s.check(ok, obtido=f"{resumo(r, 160)} (linhas no banco: {db.execute(f'select count(*) from public.{t}').fetchone()[0]})",
                aba="Segurança", modulo="Controle de acesso", tela=f"Tabela {t}", tipo="Segurança · RLS",
                cenario=f"Visitante sem login lê a tabela {t}", precondicoes="Chave publicável do app, sem token",
                passos=f"GET /rest/v1/{t}?select=*&limit=5", entrada="apikey publicável",
                esperado="HTTP 200 com a lista (leitura pública por desenho)" if publica else "Nenhuma linha devolvida (RLS)",
                severidade=BAIXA if publica else ALTA)

        antes = db.execute(f"select count(*) from public.{t}").fetchone()[0]
        r = http("POST", f"/rest/v1/{t}", corpo, cabecalhos={"Prefer": "return=representation"})
        depois = db.execute(f"select count(*) from public.{t}").fetchone()[0]
        s.check(r.status in (401, 403) and depois == antes, obtido=f"{resumo(r, 200)}; linhas antes {antes}, depois {depois}",
                aba="Segurança", modulo="Controle de acesso", tela=f"Tabela {t}", tipo="Segurança · RLS",
                cenario=f"Visitante sem login tenta inserir em {t}", precondicoes="Chave publicável, sem token; corpo com colunas válidas",
                passos=f"POST /rest/v1/{t}; contar linhas antes e depois", entrada=json.dumps(corpo, ensure_ascii=False)[:300],
                esperado="HTTP 401/403 e nenhuma linha criada", severidade=CRITICA if t in CRITICAS else ALTA)

        foto = db.execute(f"select md5(string_agg(t::text, '|' order by t::text)) from public.{t} t where " + _sql(filtro)).fetchone()[0]
        r = http("PATCH", f"/rest/v1/{t}?{filtro}", mud, cabecalhos={"Prefer": "return=representation"})
        foto2 = db.execute(f"select md5(string_agg(t::text, '|' order by t::text)) from public.{t} t where " + _sql(filtro)).fetchone()[0]
        s.check(alvos > 0 and _negado_ou_vazio(r) and foto == foto2,
                obtido=f"{resumo(r, 160)}; linhas-alvo {alvos}; conteúdo {'inalterado' if foto == foto2 else 'ALTERADO'}",
                aba="Segurança", modulo="Controle de acesso", tela=f"Tabela {t}", tipo="Segurança · RLS",
                cenario=f"Visitante sem login tenta alterar linhas de {t}", precondicoes=f"{alvos} linha(s)-alvo existentes",
                passos=f"PATCH /rest/v1/{t}?{filtro}; comparar o conteúdo das linhas antes e depois",
                entrada=json.dumps(mud), esperado="Nenhuma linha alterada", severidade=CRITICA if t in CRITICAS else ALTA)

        alvo_del = "id=eq.1" if t == "produtos" else filtro
        antes = db.execute(f"select count(*) from public.{t}").fetchone()[0]
        r = http("DELETE", f"/rest/v1/{t}?{alvo_del}", cabecalhos={"Prefer": "return=representation"})
        depois = db.execute(f"select count(*) from public.{t}").fetchone()[0]
        s.check(alvos > 0 and _negado_ou_vazio(r) and depois == antes,
                obtido=f"{resumo(r, 160)}; linhas antes {antes}, depois {depois}",
                aba="Segurança", modulo="Controle de acesso", tela=f"Tabela {t}", tipo="Segurança · RLS",
                cenario=f"Visitante sem login tenta apagar linhas de {t}", precondicoes=f"{alvos} linha(s)-alvo existentes",
                passos=f"DELETE /rest/v1/{t}?{alvo_del}; contar linhas antes e depois", entrada=alvo_del,
                esperado="Nenhuma linha apagada", severidade=CRITICA)


def _sql(filtro: str) -> str:
    """Traduz o filtro do PostgREST usado acima para SQL (só os formatos usados aqui)."""
    col, op = filtro.split("=", 1)
    if op == "not.is.null":
        return f"{col} is not null"
    valor = op.removeprefix("eq.")
    return f"{col} = {valor}" if valor.lstrip("-").isdigit() else f"{col} = '{valor}'"
