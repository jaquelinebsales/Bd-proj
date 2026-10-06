"""
Segurança: funções do banco expostas pela API, manipulação de parâmetros e exposição de dados.
A matriz de permissões por tabela está em t_matriz.py.

Toda tentativa de escrita mira dados criados pela auditoria; o efeito é conferido direto no banco.
"""
from __future__ import annotations

import json

from comum import ALTA, BAIXA, CRITICA, MEDIA, http, resumo

FUNCOES_PUBLICAS = {
    "postos_na_area": {"p_lat_min": -3.80, "p_lon_min": -38.60, "p_lat_max": -3.70, "p_lon_max": -38.45, "p_limite": 20},
    "postos_proximos": {"p_lat": -3.7627, "p_lon": -38.5399, "p_raio_km": 5, "p_limite": 10},
    "buscar_postos": {"p_texto": "fortaleza", "p_limite": 5},
    "postos_por_ids": {"p_ids": [1, 2, 3]},
    "detalhe_posto": {"p_id": 1},
    "historico_precos": {"p_posto": 1, "p_produto": 1, "p_dias": 30},
    "contribuicoes": {"p_posto": 1, "p_produto": 1},
    "avaliacoes_posto": {"p_posto": 1, "p_ordem": "recentes", "p_limite": 5, "p_offset": 0},
    "ranking": {"p_limite": 5},
    "precos_json": {"p_posto": 1},
    "parametro": {"p_chave": "raio_envio_m"},
    "abreviar_nome": {"p_nome": "Maria Silva"},
    "normalizar": {"texto": "Ação"},
    "usuario_pode_contribuir": {},
}
FUNCOES_INTERNAS = {
    "registrar_pontos": {"p_usuario": "00000000-0000-0000-0000-000000000000", "p_item": None, "p_tipo": "x", "p_pontos": 999, "p_descricao": "x"},
    "ajustar_confiabilidade": {"p_usuario": "00000000-0000-0000-0000-000000000000", "p_delta": 1},
    "atualizar_preco_atual": {"p_posto": 1, "p_produto": 1},
    "calcular_preco_exibido": {"p_posto": 1, "p_produto": 1},
    "consolidar_preco": {"p_posto": 1, "p_produto": 1},
    "consolidar_posicao": {"p_posto": 1},
    "registrar_correcao_posicao": {"p_usuario": "00000000-0000-0000-0000-000000000000", "p_posto": 1, "p_lat": -3.7, "p_lon": -38.5},
    "distancia_e_precisao": {"p_posto": 1, "p_lat": -3.7, "p_lon": -38.5},
    "distancia_ate_posto": {"p_posto": 1, "p_lat": -3.7, "p_lon": -38.5},
    "fechar_envios_antigos": {},
    "recalcular_estimativas": {},
    "recalcular_precos_atuais": {},
    "marcar_municipios_pesquisados": {},
    "importar_postos_anp": {"p_uf": "RO", "p_registros": [], "p_completo": True},
    "criar_perfil": {},
    "recalcular_nota_posto": {},
    "recalcular_votos": {},
    "marcar_avaliacao_editada": {},
}
FUNCOES_LOGADO = {"meu_resumo": {}, "meus_favoritos": {}}


def funcoes(s, ctx, token_usuario: str) -> None:
    for nome, args in FUNCOES_PUBLICAS.items():
        r = http("POST", f"/rest/v1/rpc/{nome}", args)
        s.check(r.status == 200, obtido=resumo(r, 200),
                aba="Backend/API", modulo="API do banco (RPC)", tela=f"rpc/{nome}", tipo="Funcional · contrato",
                cenario=f"Função pública {nome} responde ao visitante", precondicoes="Sem login",
                passos=f"POST /rest/v1/rpc/{nome}", entrada=json.dumps(args, ensure_ascii=False),
                esperado="HTTP 200 com o resultado", severidade=MEDIA)
    for nome, args in FUNCOES_INTERNAS.items():
        for quem, tok in (("visitante", None), ("usuário logado", token_usuario)):
            r = http("POST", f"/rest/v1/rpc/{nome}", args, token=tok)
            s.check(r.status in (401, 403, 404), obtido=resumo(r, 200),
                    aba="Segurança", modulo="Funções internas", tela=f"rpc/{nome}", tipo="Segurança · autorização",
                    cenario=f"{quem.capitalize()} não consegue chamar a rotina interna {nome}",
                    precondicoes="Sem login" if tok is None else "Usuário de teste logado",
                    passos=f"POST /rest/v1/rpc/{nome}", entrada=json.dumps(args),
                    esperado="HTTP 401, 403 ou 404 (função sem permissão de execução para o app)",
                    severidade=CRITICA if nome in ("registrar_pontos", "ajustar_confiabilidade", "consolidar_preco",
                                                   "importar_postos_anp", "registrar_correcao_posicao") else ALTA)
    for nome, args in FUNCOES_LOGADO.items():
        r = http("POST", f"/rest/v1/rpc/{nome}", args)
        s.check(r.status in (401, 403, 404), obtido=resumo(r, 160),
                aba="Segurança", modulo="Funções do usuário", tela=f"rpc/{nome}", tipo="Segurança · autenticação",
                cenario=f"{nome} exige login", precondicoes="Sem login", passos=f"POST /rest/v1/rpc/{nome}",
                entrada="{}", esperado="HTTP 401/403/404", severidade=ALTA)
        r = http("POST", f"/rest/v1/rpc/{nome}", args, token=token_usuario)
        s.check(r.status == 200, obtido=resumo(r, 200),
                aba="Backend/API", modulo="API do banco (RPC)", tela=f"rpc/{nome}", tipo="Funcional · contrato",
                cenario=f"{nome} responde ao usuário logado", precondicoes="Usuário de teste logado",
                passos=f"POST /rest/v1/rpc/{nome} com o token", entrada="{}", esperado="HTTP 200", severidade=ALTA)


def manipulacao(s, ctx) -> None:
    """Entradas hostis, limites e valores inválidos nas funções públicas."""
    db = ctx["db"]
    total_postos = db.execute("select count(*) from public.postos where ativo").fetchone()[0]
    casos = [
        ("buscar_postos", {"p_texto": "'; drop table public.postos; --", "p_limite": 5}, "Injeção de SQL no texto da busca",
         lambda r: r.status == 200 and isinstance(r.corpo, list), "HTTP 200, busca tratada como texto, tabela intacta", CRITICA),
        ("buscar_postos", {"p_texto": "%", "p_limite": 5}, "Curinga % na busca não lista o cadastro inteiro sem limite",
         lambda r: r.status == 200 and isinstance(r.corpo, list) and len(r.corpo) <= 5, "No máximo 5 resultados", MEDIA),
        ("buscar_postos", {"p_texto": "", "p_limite": 5}, "Busca com texto vazio",
         lambda r: r.status == 200 and isinstance(r.corpo, list), "HTTP 200 com lista vazia ou limitada, sem erro 500", BAIXA),
        ("buscar_postos", {"p_texto": "a" * 5000, "p_limite": 5}, "Busca com 5.000 caracteres",
         lambda r: r.status in (200, 400) and r.ms < 10000, "Responde em menos de 10 s, sem erro 500", MEDIA),
        ("buscar_postos", {"p_texto": "fortaleza", "p_limite": 100000}, "Busca pedindo 100.000 resultados",
         lambda r: r.status == 200 and isinstance(r.corpo, list) and len(r.corpo) <= 200, "Servidor limita a quantidade (até 200)", MEDIA),
        ("postos_na_area", {"p_lat_min": -34, "p_lon_min": -74, "p_lat_max": 6, "p_lon_max": -28, "p_limite": 1000000},
         "Área do Brasil inteiro pedindo 1 milhão de postos",
         lambda r: r.status in (200, 400) and (not isinstance(r.corpo, list) or len(r.corpo) <= 1000) and r.ms < 15000,
         f"Servidor limita o tamanho da resposta (cadastro ativo tem {total_postos} postos)", ALTA),
        ("postos_proximos", {"p_lat": -3.76, "p_lon": -38.54, "p_raio_km": 100000, "p_limite": 1000000},
         "Raio de 100.000 km e limite de 1 milhão",
         lambda r: r.status in (200, 400) and (not isinstance(r.corpo, list) or len(r.corpo) <= 1000) and r.ms < 15000,
         "Servidor limita raio e quantidade", ALTA),
        ("postos_proximos", {"p_lat": 999, "p_lon": -38.54, "p_raio_km": 5, "p_limite": 10}, "Latitude impossível (999)",
         lambda r: r.status in (200, 400) and r.status != 500, "Erro de validação ou lista vazia, sem erro 500", BAIXA),
        ("postos_proximos", {"p_lat": -3.76, "p_lon": -38.54, "p_raio_km": 5, "p_limite": -1}, "Limite negativo",
         lambda r: r.status in (200, 400), "Lista vazia ou erro de validação, sem erro 500", BAIXA),
        ("detalhe_posto", {"p_id": 999999999}, "Detalhe de posto inexistente",
         lambda r: r.status == 200 and r.corpo is None, "HTTP 200 com null (o app mostra 'não encontrado')", MEDIA),
        ("detalhe_posto", {"p_id": ctx["postos"]["inativo"]}, "Detalhe de posto inativo (fora do cadastro da ANP)",
         lambda r: r.status == 200, "Responde sem erro (o histórico do posto inativo é mantido)", BAIXA),
        ("historico_precos", {"p_posto": 1, "p_produto": 1, "p_dias": 100000}, "Histórico pedindo 100.000 dias",
         lambda r: r.status in (200, 400) and r.ms < 15000, "Responde em menos de 15 s", MEDIA),
        ("historico_precos", {"p_posto": 1, "p_produto": 99, "p_dias": 30}, "Histórico de combustível inexistente",
         lambda r: r.status in (200, 400) and r.status != 500, "Lista vazia ou erro de validação", BAIXA),
        ("avaliacoes_posto", {"p_posto": 1, "p_ordem": "'; delete from avaliacoes; --", "p_limite": 5, "p_offset": 0},
         "Injeção de SQL no parâmetro de ordenação das avaliações",
         lambda r: r.status in (200, 400), "Parâmetro tratado como valor, sem erro 500", CRITICA),
        ("avaliacoes_posto", {"p_posto": 1, "p_ordem": "uteis", "p_limite": 100000, "p_offset": -5}, "Limite enorme e deslocamento negativo",
         lambda r: r.status in (200, 400) and r.status != 500, "Sem erro 500", BAIXA),
        ("ranking", {"p_limite": 100000}, "Ranking pedindo 100.000 posições",
         lambda r: r.status == 200 and isinstance(r.corpo, list) and len(r.corpo) <= 100, "Servidor limita a quantidade", BAIXA),
        ("postos_por_ids", {"p_ids": list(range(1, 5001))}, "Favoritos locais com 5.000 ids",
         lambda r: r.status in (200, 400) and r.ms < 15000 and (not isinstance(r.corpo, list) or len(r.corpo) <= 500),
         "Servidor limita a lista ou responde rápido", MEDIA),
    ]
    for fn, args, cen, criterio, esp, sev in casos:
        r = http("POST", f"/rest/v1/rpc/{fn}", args, timeout=90)
        n = len(r.corpo) if isinstance(r.corpo, list) else "-"
        s.check(bool(criterio(r)), obtido=f"HTTP {r.status} em {r.ms} ms; itens: {n}; {r.texto[:160]}",
                aba="Segurança", modulo="Validação de entrada", tela=f"rpc/{fn}", tipo="Segurança · manipulação de parâmetros",
                cenario=cen, precondicoes="Sem login", passos=f"POST /rest/v1/rpc/{fn}",
                entrada=json.dumps(args)[:300], esperado=esp, severidade=sev)
    vivos = db.execute("select count(*) from public.postos where ativo").fetchone()[0]
    s.check(vivos == total_postos, obtido=f"postos ativos antes {total_postos}, depois {vivos}",
            aba="Segurança", modulo="Validação de entrada", tela="Banco", tipo="Segurança · integridade",
            cenario="Tabela de postos intacta depois das tentativas de injeção", precondicoes="Testes de injeção executados",
            passos="Contar postos ativos antes e depois", entrada="-", esperado="Mesma contagem", severidade=CRITICA)


def exposicao(s, ctx) -> None:
    """O que um visitante consegue ver que não deveria."""
    r = http("GET", "/rest/v1/avaliacoes?select=usuario_id&limit=1")
    expoe = r.status == 200 and isinstance(r.corpo, list) and r.corpo and "usuario_id" in r.corpo[0]
    s.check(not expoe, obtido=resumo(r, 200),
            aba="Segurança", modulo="Exposição de dados", tela="Tabela avaliacoes", tipo="Segurança · privacidade",
            cenario="Visitante não consegue ler o identificador (UUID) de quem avaliou",
            precondicoes="Existe pelo menos uma avaliação (criada pela auditoria)", passos="GET /rest/v1/avaliacoes?select=usuario_id",
            entrada="-", esperado="Coluna usuario_id não exposta ao público (o app usa a função avaliacoes_posto, que abrevia o nome)",
            severidade=MEDIA, obs="A política de leitura pública da tabela libera todas as colunas.")
    r = http("GET", "/rest/v1/avaliacao_votos?select=usuario_id&limit=1")
    expoe = r.status == 200 and isinstance(r.corpo, list) and r.corpo and "usuario_id" in r.corpo[0]
    s.check(not expoe, obtido=resumo(r, 200),
            aba="Segurança", modulo="Exposição de dados", tela="Tabela avaliacao_votos", tipo="Segurança · privacidade",
            cenario="Visitante não consegue ver quem votou em cada avaliação",
            precondicoes="Existe pelo menos um voto (criado pela auditoria)", passos="GET /rest/v1/avaliacao_votos?select=usuario_id",
            entrada="-", esperado="Votos não ligados a pessoas para o público", severidade=BAIXA)
    r = http("POST", "/rest/v1/rpc/contribuicoes", {"p_posto": ctx["postos"]["exata"], "p_produto": 1})
    vaza = any(k in r.texto for k in ("usuario_id", "@", "email"))
    s.check(r.status == 200 and not vaza, obtido=resumo(r, 300),
            aba="Segurança", modulo="Exposição de dados", tela="rpc/contribuicoes", tipo="Segurança · privacidade",
            cenario="Lista de contribuições mostra só o nome abreviado, sem e-mail nem id",
            precondicoes="Envios da auditoria no posto de teste", passos="POST /rest/v1/rpc/contribuicoes",
            entrada="posto de teste, gasolina", esperado="Sem usuario_id nem e-mail na resposta", severidade=ALTA)
    r = http("POST", "/rest/v1/rpc/ranking", {"p_limite": 50})
    vaza = any(k in r.texto for k in ("@", "usuario_id", "email"))
    s.check(r.status == 200 and not vaza, obtido=resumo(r, 300),
            aba="Segurança", modulo="Exposição de dados", tela="rpc/ranking", tipo="Segurança · privacidade",
            cenario="Ranking não expõe e-mail nem id dos usuários", precondicoes="Usuários de teste com pontos",
            passos="POST /rest/v1/rpc/ranking", entrada="p_limite 50", esperado="Só posição, nome abreviado e pontos", severidade=ALTA)
    r = http("POST", "/rest/v1/rpc/avaliacoes_posto", {"p_posto": ctx["postos"]["exata"], "p_ordem": "recentes", "p_limite": 10, "p_offset": 0})
    nomes_completos = "Auditoria Ana" in r.texto or "@" in r.texto
    s.check(r.status == 200 and not nomes_completos, obtido=resumo(r, 300),
            aba="Segurança", modulo="Exposição de dados", tela="rpc/avaliacoes_posto", tipo="Segurança · privacidade",
            cenario="Avaliações mostram o nome abreviado (Auditoria A.), nunca o nome completo nem o e-mail",
            precondicoes="Avaliação da usuária 'Auditoria Ana' no posto de teste", passos="POST /rest/v1/rpc/avaliacoes_posto",
            entrada="posto de teste", esperado="Nome abreviado", severidade=MEDIA)
    r = http("GET", "/rest/v1/")
    s.add(status="PASS" if r.status in (200, 401, 403) else "FAIL", obtido=f"HTTP {r.status}; {len(r.texto)} bytes de descrição da API",
          aba="Segurança", modulo="Exposição de dados", tela="/rest/v1/", tipo="Segurança · reconhecimento",
          cenario="Descrição OpenAPI da API REST para quem tem a chave publicável",
          precondicoes="Chave publicável (ela vai dentro do app)", passos="GET /rest/v1/", entrada="-",
          esperado="Comportamento padrão do Supabase; nenhuma tabela privada fica legível por causa disso",
          severidade=BAIXA, obs="Informativo: a lista de tabelas e funções é visível, mas o acesso continua barrado pelo RLS.")
    # Storage
    r = http("POST", "/storage/v1/object/list/anp-historico", {"prefix": "", "limit": 10})
    s.check(r.status in (400, 401, 403, 404) or (r.status == 200 and r.corpo == []), obtido=resumo(r, 200),
            aba="Segurança", modulo="Storage", tela="Bucket anp-historico", tipo="Segurança · storage",
            cenario="Visitante não lista o bucket privado da série histórica da ANP", precondicoes="Sem login",
            passos="POST /storage/v1/object/list/anp-historico", entrada="prefix ''", esperado="Negado ou lista vazia", severidade=MEDIA)
    r = http("POST", "/storage/v1/object/avatares/invasor/teste.txt", bruto=b"x", cabecalhos={"Content-Type": "text/plain"})
    s.check(r.status in (400, 401, 403), obtido=resumo(r, 200),
            aba="Segurança", modulo="Storage", tela="Bucket avatares", tipo="Segurança · storage",
            cenario="Visitante não envia arquivo para o bucket de avatares", precondicoes="Sem login",
            passos="POST /storage/v1/object/avatares/invasor/teste.txt", entrada="arquivo de 1 byte",
            esperado="HTTP 400/401/403", severidade=ALTA)
