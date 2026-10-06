"""
Gera supabase/migrations/20261006000008_limites_das_ufs.sql com o contorno dos 27 estados (malha do IBGE,
qualidade intermediária). O banco usa o contorno para recusar coordenadas da ANP que caem fora do estado do posto.

Fonte: https://servicodados.ibge.gov.br/api/v3/malhas/paises/BR?formato=application/vnd.geo+json&qualidade=intermediaria&intrarregiao=UF
Arquivo baixado: dados/externos/ibge_ufs_intermediaria.geojson

Uso: python scripts/geocodificacao/gerar_migracao_ufs.py
"""
from __future__ import annotations

import json
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
ORIGEM = RAIZ / "dados" / "externos" / "ibge_ufs_intermediaria.geojson"
DESTINO = RAIZ / "supabase" / "migrations" / "20261006000008_limites_das_ufs.sql"
UF = {"11": "RO", "12": "AC", "13": "AM", "14": "RR", "15": "PA", "16": "AP", "17": "TO", "21": "MA", "22": "PI", "23": "CE",
      "24": "RN", "25": "PB", "26": "PE", "27": "AL", "28": "SE", "29": "BA", "31": "MG", "32": "ES", "33": "RJ", "35": "SP",
      "41": "PR", "42": "SC", "43": "RS", "50": "MS", "51": "MT", "52": "GO", "53": "DF"}


def main() -> None:
    geo = json.loads(ORIGEM.read_text(encoding="utf-8"))
    linhas = [
        "-- gasprice · contorno dos estados (malha do IBGE, qualidade intermediária)",
        "-- Gerado por scripts/geocodificacao/gerar_migracao_ufs.py. Usado para recusar coordenadas da ANP fora do estado do posto.",
        "",
        "create table public.ufs_limites (",
        "  uf       char(2) primary key,",
        "  contorno extensions.geography not null",
        ");",
        "create index ufs_limites_contorno_idx on public.ufs_limites using gist (contorno);",
        "alter table public.ufs_limites enable row level security;",
        "-- Sem política: só as funções do servidor leem a tabela.",
        "",
    ]
    for f in sorted(geo["features"], key=lambda f: UF[f["properties"]["codarea"]]):
        uf = UF[f["properties"]["codarea"]]
        gj = json.dumps(f["geometry"], separators=(",", ":"))
        linhas.append(f"insert into public.ufs_limites values ('{uf}', extensions.st_geomfromgeojson('{gj}')::extensions.geography);")
    DESTINO.write_text("\n".join(linhas) + "\n", encoding="utf-8")
    print(f"{DESTINO} ({DESTINO.stat().st_size / 1024:.0f} KB, {len(geo['features'])} estados)")


if __name__ == "__main__":
    main()
