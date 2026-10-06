"""
Tempos de resposta e comportamento com requisições simultâneas, contra o projeto real.
Medido deste computador (Brasil) até o Supabase em us-west-2: inclui a latência da rede.
"""
from __future__ import annotations

import concurrent.futures as cf
import statistics

from comum import ALTA, MEDIA, http

CONSULTAS = [
    ("Mapa · postos na área (Fortaleza)", "postos_na_area",
     {"p_lat_min": -3.80, "p_lon_min": -38.60, "p_lat_max": -3.70, "p_lon_max": -38.45, "p_limite": 300}, 1500),
    ("Mapa · área grande (região metropolitana de SP)", "postos_na_area",
     {"p_lat_min": -23.8, "p_lon_min": -46.9, "p_lat_max": -23.3, "p_lon_max": -46.3, "p_limite": 300}, 2000),
    ("Busca · lista por distância", "postos_proximos", {"p_lat": -23.55, "p_lon": -46.63, "p_raio_km": 20, "p_limite": 100}, 1500),
    ("Busca · texto", "buscar_postos", {"p_texto": "shell avenida paulista", "p_limite": 50}, 1500),
    ("Busca · texto curto e comum", "buscar_postos", {"p_texto": "posto", "p_limite": 50}, 2000),
    ("Posto · detalhe", "detalhe_posto", {"p_id": 1}, 1000),
    ("Posto · histórico de 180 dias", "historico_precos", {"p_posto": 1, "p_produto": 1, "p_dias": 180}, 1000),
    ("Posto · avaliações", "avaliacoes_posto", {"p_posto": 1, "p_ordem": "uteis", "p_limite": 20, "p_offset": 0}, 1000),
    ("Ranking", "ranking", {"p_limite": 50}, 1000),
]


def rodar(s, ctx) -> None:
    for nome, fn, args, limite in CONSULTAS:
        tempos, status = [], []
        for _ in range(10):
            r = http("POST", f"/rest/v1/rpc/{fn}", args, timeout=60)
            tempos.append(r.ms)
            status.append(r.status)
        t = sorted(tempos)
        p50, p95 = statistics.median(t), t[min(len(t) - 1, int(round(0.95 * (len(t) - 1))))]
        s.check(all(x == 200 for x in status) and p95 <= limite,
                obtido=f"p50 {p50:.0f} ms; p95 {p95} ms; mín {t[0]} ms; máx {t[-1]} ms; status {sorted(set(status))}",
                aba="Performance", modulo="Tempo de resposta", tela=nome, tipo="Performance · latência",
                cenario=f"{nome}: 10 chamadas seguidas", precondicoes="Dados reais (45 mil postos); rede Brasil → us-west-2",
                passos=f"Chamar rpc/{fn} 10 vezes e medir", entrada=str(args)[:200], esperado=f"p95 até {limite} ms, todas HTTP 200",
                severidade=MEDIA, duracao_ms=int(p50))

    for n, fn, args in ((30, "postos_na_area", CONSULTAS[0][2]), (50, "buscar_postos", {"p_texto": "posto", "p_limite": 20})):
        with cf.ThreadPoolExecutor(max_workers=n) as ex:
            rs = list(ex.map(lambda _: http("POST", f"/rest/v1/rpc/{fn}", args, timeout=90), range(n)))
        ok = sum(r.status == 200 for r in rs)
        t = sorted(r.ms for r in rs)
        s.check(ok == n and t[-1] <= 10000, obtido=f"{ok}/{n} com HTTP 200; mediana {statistics.median(t):.0f} ms; máximo {t[-1]} ms; "
                                                    f"códigos {sorted(set(r.status for r in rs))}",
                aba="Performance", modulo="Concorrência", tela=f"rpc/{fn}", tipo="Performance · carga",
                cenario=f"{n} requisições simultâneas em {fn}", precondicoes="Plano gratuito do Supabase",
                passos=f"Disparar {n} chamadas ao mesmo tempo", entrada=str(args)[:150],
                esperado=f"Todas HTTP 200 e nenhuma acima de 10 s", severidade=ALTA)

    for nome, f in (("enviar-precos", "/functions/v1/enviar-precos"), ("corrigir-posicao", "/functions/v1/corrigir-posicao")):
        tempos = [http("POST", f, {}, timeout=60).ms for _ in range(5)]
        s.check(max(tempos) <= 5000, obtido=f"tempos (sem login, recusa rápida): {tempos} ms",
                aba="Performance", modulo="Edge Functions", tela=nome, tipo="Performance · latência",
                cenario=f"{nome} responde a 5 chamadas seguidas (inclui partida a frio)", precondicoes="Função publicada",
                passos="5 POST sem token", entrada="{}", esperado="Todas abaixo de 5 s", severidade=MEDIA)
    ctx.setdefault("tempos_envio", [])
