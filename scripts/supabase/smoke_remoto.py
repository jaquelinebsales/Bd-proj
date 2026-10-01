"""
Teste rápido do backend publicado, do jeito que o app o enxerga: só com a chave publishable, sem login.

Confere que a consulta pública funciona e que tudo o que altera dados está bloqueado.
Uso: python scripts/supabase/smoke_remoto.py
Não imprime chaves.
"""
from __future__ import annotations

import json
import sys
import urllib.error
import urllib.request

import env_util as eu

resultados: list[bool] = []


def chamar(env: dict, metodo: str, caminho: str, corpo=None) -> tuple[int, object]:
    chave = env["SUPABASE_PUBLISHABLE_KEY"].strip()
    cab = {"apikey": chave, "Content-Type": "application/json", "User-Agent": "gasprice-scripts/1.0"}
    if chave.startswith("eyJ"):
        cab["Authorization"] = f"Bearer {chave}"
    req = urllib.request.Request(env["SUPABASE_URL"].strip().rstrip("/") + caminho, method=metodo, headers=cab,
                                 data=None if corpo is None else json.dumps(corpo).encode())
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            texto = r.read().decode("utf-8", "replace")
            return r.status, json.loads(texto) if texto else None
    except urllib.error.HTTPError as e:
        texto = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(texto)
        except ValueError:
            return e.code, texto


def conferir(ok: bool, texto: str) -> None:
    resultados.append(ok)
    print(("ok    " if ok else "FALHOU"), texto)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    env = eu.carregar_env()

    s, d = chamar(env, "GET", "/rest/v1/produtos?select=id,nome&order=ordem")
    conferir(s == 200 and isinstance(d, list) and len(d) == 6, f"consulta pública dos combustíveis (HTTP {s})")

    s, d = chamar(env, "POST", "/rest/v1/rpc/postos_proximos", {"p_lat": -3.7627, "p_lon": -38.5399, "p_raio_km": 10, "p_limite": 50})
    conferir(s == 200 and isinstance(d, list) and len(d) > 0, f"postos perto de Fortaleza: {len(d) if isinstance(d, list) else '?'} (HTTP {s})")
    primeiro = d[0] if isinstance(d, list) and d else {}
    conferir("precisao" in primeiro, "a lista de postos informa a precisão da localização")
    com_preco = [p for p in (d if isinstance(d, list) else []) if p.get("precos")]
    conferir(len(com_preco) > 0, f"postos com preço entre eles: {len(com_preco)}")

    s, d = chamar(env, "POST", "/rest/v1/rpc/buscar_postos", {"p_texto": "itaitinga ce", "p_limite": 10})
    conferir(s == 200 and isinstance(d, list) and len(d) > 0, f"busca por cidade e UF sem acento: {len(d) if isinstance(d, list) else '?'} (HTTP {s})")

    if primeiro.get("id"):
        s, d = chamar(env, "POST", "/rest/v1/rpc/detalhe_posto", {"p_id": primeiro["id"]})
        conferir(s == 200 and isinstance(d, dict) and d.get("cnpj"), f"detalhe de um posto (HTTP {s})")
        conferir(isinstance(d, dict) and "precisao" in d and "raio_envio_m" in d, "o detalhe informa a precisão e o raio de envio")
        s, d = chamar(env, "POST", "/rest/v1/rpc/historico_precos", {"p_posto": primeiro["id"], "p_produto": 1, "p_dias": 180})
        conferir(s == 200 and isinstance(d, list), f"histórico de preços (HTTP {s}, {len(d) if isinstance(d, list) else '?'} pontos)")

    s, d = chamar(env, "POST", "/rest/v1/rpc/ranking", {"p_limite": 5})
    conferir(s == 200, f"ranking público (HTTP {s})")

    print("\nO que precisa estar bloqueado para quem não entrou:")
    s, _ = chamar(env, "POST", "/rest/v1/avaliacoes", {"posto_id": 1, "usuario_id": "00000000-0000-0000-0000-000000000000", "nota": 5})
    conferir(s in (401, 403), f"avaliar sem login é recusado (HTTP {s})")
    s, _ = chamar(env, "POST", "/rest/v1/precos_atuais", {"posto_id": 1, "produto_id": 1, "preco": 1, "fonte": "comunidade", "situacao": "confirmado", "atualizado_em": "2026-01-01"})
    conferir(s in (401, 403), f"gravar preço direto na tabela é recusado (HTTP {s})")
    s, _ = chamar(env, "POST", "/rest/v1/envios", {"posto_id": 1})
    conferir(s in (401, 403), f"gravar envio direto na tabela é recusado (HTTP {s})")
    s, _ = chamar(env, "PATCH", "/rest/v1/perfis?id=not.is.null", {"pontos": 9999})
    conferir(s in (401, 403, 404) or s == 200 and _ == [], f"alterar pontos de alguém é recusado (HTTP {s})")
    for rotina, args in [("consolidar_preco", {"p_posto": 1, "p_produto": 1}), ("registrar_pontos", {"p_usuario": "00000000-0000-0000-0000-000000000000", "p_item": None, "p_tipo": "x", "p_pontos": 999, "p_descricao": "x"}),
                         ("recalcular_precos_atuais", {}), ("importar_postos_anp", {"p_uf": "CE", "p_registros": [], "p_completo": True}),
                         ("registrar_correcao_posicao", {"p_usuario": "00000000-0000-0000-0000-000000000000", "p_posto": 1, "p_lat": -3.76, "p_lon": -38.54}),
                         ("consolidar_posicao", {"p_posto": 1}), ("distancia_e_precisao", {"p_posto": 1, "p_lat": -3.76, "p_lon": -38.54})]:
        s, _ = chamar(env, "POST", f"/rest/v1/rpc/{rotina}", args)
        conferir(s in (401, 403, 404), f"rotina interna {rotina} não pode ser chamada pelo app (HTTP {s})")
    s, _ = chamar(env, "POST", "/functions/v1/corrigir-posicao", {"posto_id": 1, "latitude": -3.76, "longitude": -38.54, "precisao_gps_m": 10})
    conferir(s == 401, f"informar a posição de um posto sem login é recusado (HTTP {s})")
    s, _ = chamar(env, "POST", "/rest/v1/correcoes_posicao", {"posto_id": 1})
    conferir(s in (401, 403, 404), f"gravar posição direto na tabela é recusado (HTTP {s})")
    s, _ = chamar(env, "POST", "/rest/v1/rpc/meu_resumo", {})
    conferir(s in (401, 403, 404), f"perfil próprio exige login (HTTP {s})")

    falhas = resultados.count(False)
    print(f"\n{len(resultados) - falhas} de {len(resultados)} verificações ok")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
