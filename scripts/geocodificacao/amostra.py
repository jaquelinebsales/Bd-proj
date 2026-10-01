"""
Teste de geocodificação dos postos sem coordenada (amostra). Só lê o banco: não grava nada no Supabase.

Grupo A: 100 postos ativos SEM coordenada -> quanto cada camada resolve.
Grupo B: 100 postos ativos COM coordenada da ANP -> o mesmo método, medindo a distância até a coordenada da ANP.

Camadas, nesta ordem:
  1. Nominatim (OpenStreetMap), busca estruturada por rua e número, cidade e UF  -> "numero" ou "rua"
  2. Nominatim sem o número                                                       -> "rua"
  3. CEP pela BrasilAPI (CEP de rua ou CEP da cidade inteira)                     -> "cep_rua" ou "cep_cidade"
  4. Centro do município (malha do IBGE)                                          -> "municipio"
Todo ponto encontrado precisa cair dentro do município do posto (malha do IBGE), senão é descartado.

Respeita a política do Nominatim: no máximo 1 consulta por segundo, User-Agent identificado.
Uso: python scripts/geocodificacao/amostra.py [--n 100]
Saída: dados/geocodificacao/amostra_resultados.json
"""
from __future__ import annotations

import argparse
import difflib
import json
import math
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / "scripts" / "supabase"))
import env_util as eu  # noqa: E402

EXT = RAIZ / "dados" / "externos"
SAIDA = RAIZ / "dados" / "geocodificacao"
UA = "gasprice/1.0 (projeto academico de precos de combustiveis)"
NIVEIS = ["numero", "rua", "cep_rua", "cep_cidade", "municipio", "nada"]

APELIDOS = {
    ("SP", "MOJI MIRIM"): "MOGI MIRIM", ("SP", "MOJI DAS CRUZES"): "MOGI DAS CRUZES",
    ("SP", "MOJI GUACU"): "MOGI GUACU", ("RN", "ACU"): "ASSU", ("RN", "AUGUSTO SEVERO"): "CAMPO GRANDE",
    ("RN", "BOA SAUDE"): "JANUARIO CICCO", ("GO", "BOM JESUS"): "BOM JESUS DE GOIAS",
    ("RR", "SAO LUIZ"): "SAO LUIZ DO ANAUA", ("TO", "FORTALEZA DO TABOCAO"): "TABOCAO",
    ("PB", "SANTAREM"): "JOCA CLAUDINO", ("MG", "SAO THOME DAS LETRAS"): "SAO TOME DAS LETRAS",
    ("PE", "BELEM DE SAO FRANCISCO"): "BELEM DO SAO FRANCISCO", ("TO", "SAO VALERIO DA NATIVIDADE"): "SAO VALERIO",
    ("BA", "SANTA TERESINHA"): "SANTA TEREZINHA", ("MT", "POXOREO"): "POXOREU",
    ("SC", "PICARRAS"): "BALNEARIO PICARRAS", ("SC", "PRESIDENTE CASTELO BRANCO"): "PRESIDENTE CASTELLO BRANCO",
    ("RS", "SANTANA DO LIVRAMENTO"): "SANT ANA DO LIVRAMENTO",
}


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKD", str(s)).encode("ascii", "ignore").decode()
    s = s.upper().replace("-", " ").replace("'", " ").replace("`", " ")
    return " ".join(s.split())


def km(lon1, lat1, lon2, lat2) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2
    return 2 * 6371.0 * math.asin(math.sqrt(a))


# ------------------------------------------------------------------ malha do IBGE
class Municipios:
    def __init__(self) -> None:
        lista = json.loads((EXT / "ibge_municipios_lista.json").read_text(encoding="utf-8"))
        geo = json.loads((EXT / "ibge_municipios.geojson").read_text(encoding="utf-8"))
        self.geom = {f["properties"]["codarea"]: f["geometry"] for f in geo["features"]}
        self.chave = {}
        self.nomes_uf: dict[str, list[str]] = {}
        for m in lista:
            try:
                uf = m["microrregiao"]["mesorregiao"]["UF"]["sigla"]
            except (TypeError, KeyError):
                uf = m["regiao-imediata"]["regiao-intermediaria"]["UF"]["sigla"]
            n = norm(m["nome"])
            self.chave[(uf, n)] = str(m["id"])
            self.nomes_uf.setdefault(uf, []).append(n)

    def codigo(self, uf: str, nome: str) -> str | None:
        n = APELIDOS.get((uf, norm(nome)), norm(nome))
        c = self.chave.get((uf, n))
        if c is None:
            m = difflib.get_close_matches(n, self.nomes_uf.get(uf, []), n=1, cutoff=0.8)
            c = self.chave.get((uf, m[0])) if m else None
        return c if c in self.geom else None

    def contem(self, cod: str, lon: float, lat: float) -> bool:
        g = self.geom[cod]
        polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        for poly in polys:
            if _dentro(poly[0], lon, lat) and not any(_dentro(buraco, lon, lat) for buraco in poly[1:]):
                return True
        return False

    def centro(self, cod: str) -> tuple[float, float]:
        """Centroide ponderado por área (lon, lat) do maior anel externo."""
        g = self.geom[cod]
        polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        melhor, area_max = None, -1.0
        for poly in polys:
            anel = poly[0]
            a = cx = cy = 0.0
            for (x0, y0), (x1, y1) in zip(anel, anel[1:]):
                f = x0 * y1 - x1 * y0
                a += f; cx += (x0 + x1) * f; cy += (y0 + y1) * f
            if abs(a) > area_max and a:
                area_max, melhor = abs(a), (cx / (3 * a), cy / (3 * a))
        return melhor


def _dentro(anel, x, y) -> bool:
    dentro = False
    for (x0, y0), (x1, y1) in zip(anel, anel[1:]):
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
            dentro = not dentro
    return dentro


# ------------------------------------------------------------------ serviços externos
_ultima_nominatim = 0.0


def http_json(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json", "Accept-Language": "pt-BR"})
    for tentativa in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read() or b"null")
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code in (429, 503):
                time.sleep(5 * (tentativa + 1))
                continue
            return None
        except (urllib.error.URLError, TimeoutError, OSError):
            time.sleep(3)
    return None


def nominatim(rua: str, cidade: str, uf: str):
    global _ultima_nominatim
    espera = 1.1 - (time.time() - _ultima_nominatim)
    if espera > 0:
        time.sleep(espera)
    _ultima_nominatim = time.time()
    q = urllib.parse.urlencode({"street": rua, "city": cidade, "state": uf, "country": "Brasil", "countrycodes": "br",
                                "format": "jsonv2", "addressdetails": 1, "limit": 1})
    r = http_json(f"https://nominatim.openstreetmap.org/search?{q}")
    return r[0] if r else None


def brasilapi_cep(cep: str):
    time.sleep(0.4)
    return http_json(f"https://brasilapi.com.br/api/cep/v2/{cep}")


def separar_numero(endereco: str) -> tuple[str, str | None]:
    """'AVENIDA JOSE RUI LINO, 500' -> ('AVENIDA JOSE RUI LINO', '500')."""
    e = re.sub(r"\s+", " ", endereco or "").strip()
    m = re.match(r"^(.*?)[,\s]+(?:N[º°O.]?\s*)?(\d+[A-Z]?)\b.*$", e)
    if m and not re.search(r"\b(BR|KM|RODOVIA|SP|MG|GO|PR|RS|SC|BA|CE)\s*-?\s*$", m.group(1)):
        return m.group(1).strip(" ,"), m.group(2)
    return re.sub(r",?\s*(S/?N|SN)\b.*$", "", e).strip(" ,"), None


# ------------------------------------------------------------------ geocodificação de um posto
def geocodificar(p: dict, mun: Municipios, todas_camadas: bool) -> dict:
    cod = mun.codigo(p["uf"], p["municipio"])
    r = {"id": p["id"], "uf": p["uf"], "municipio": p["municipio"], "cod_ibge": cod, "camadas": {}}
    if cod is None:
        r["nivel"] = "nada"
        r["motivo"] = "município não encontrado na malha do IBGE"
        return r
    rua, numero = separar_numero(p["endereco"] or "")
    cidade = p["municipio"]

    def aceita(lat, lon) -> bool:
        return lat is not None and mun.contem(cod, lon, lat)

    # Camadas 1 e 2: Nominatim
    tentativas = ([f"{numero} {rua}"] if numero else []) + ([rua] if rua else [])
    for consulta in tentativas:
        res = nominatim(consulta, cidade, p["uf"])
        if not res:
            continue
        lat, lon = float(res["lat"]), float(res["lon"])
        end = res.get("address", {})
        tipo = res.get("addresstype") or res.get("type")
        if "house_number" in end:
            nivel = "numero"
        elif res.get("category") == "highway" or tipo in ("road", "highway") or "road" in end and tipo not in (
                "city", "town", "village", "municipality", "suburb", "neighbourhood", "quarter", "hamlet", "state"):
            nivel = "rua"
        else:
            continue
        if aceita(lat, lon):
            r["camadas"]["nominatim"] = {"nivel": nivel, "lat": lat, "lon": lon}
            break
        r.setdefault("descartados", []).append("nominatim fora do município")
    # Camada 3: CEP
    if todas_camadas or "nominatim" not in r["camadas"]:
        cep = re.sub(r"\D", "", p.get("cep") or "")
        if len(cep) == 8:
            c = brasilapi_cep(cep)
            coord = ((c or {}).get("location") or {}).get("coordinates") or {}
            if coord.get("latitude") and coord.get("longitude"):
                lat, lon = float(coord["latitude"]), float(coord["longitude"])
                nivel = "cep_rua" if c.get("street") else "cep_cidade"
                if aceita(lat, lon):
                    r["camadas"]["cep"] = {"nivel": nivel, "lat": lat, "lon": lon}
                else:
                    r.setdefault("descartados", []).append("cep fora do município")
    # Camada 4: centro do município
    lon, lat = mun.centro(cod)
    r["camadas"]["municipio"] = {"nivel": "municipio", "lat": lat, "lon": lon}

    for camada in ("nominatim", "cep", "municipio"):
        if camada in r["camadas"]:
            r["nivel"] = r["camadas"][camada]["nivel"]
            r["lat"], r["lon"] = r["camadas"][camada]["lat"], r["camadas"][camada]["lon"]
            break
    return r


def percentil(v: list[float], q: float) -> float | None:
    if not v:
        return None
    v = sorted(v)
    k = (len(v) - 1) * q
    f = math.floor(k)
    return v[f] + (v[min(f + 1, len(v) - 1)] - v[f]) * (k - f)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=100)
    args = ap.parse_args()

    import psycopg
    env = eu.carregar_env()
    url, _ = eu.resolver_database_url(env)
    colunas = "id, endereco, complemento, bairro, municipio, uf, cep"
    with psycopg.connect(url, connect_timeout=30, prepare_threshold=None) as con, con.cursor() as cur:
        cur.execute("select setseed(0.42)")
        cur.execute(f"select {colunas} from public.postos where ativo and localizacao is null order by random() limit %s", (args.n,))
        sem = [dict(zip([d.name for d in cur.description], r)) for r in cur.fetchall()]
        cur.execute(f"select {colunas}, extensions.st_y(localizacao::extensions.geometry) as lat_anp, "
                    f"extensions.st_x(localizacao::extensions.geometry) as lon_anp from public.postos "
                    f"where ativo and localizacao is not null and localizacao_fonte = 'anp' order by random() limit %s", (args.n,))
        com = [dict(zip([d.name for d in cur.description], r)) for r in cur.fetchall()]
        # Panorama dos postos sem coordenada
        cur.execute("""select uf, count(*) as postos,
                              count(*) filter (where cep ~ '000$') as cep_da_cidade,
                              count(*) filter (where endereco ~ '\\d') as endereco_com_numero
                       from public.postos where ativo and localizacao is null group by uf order by 2 desc""")
        por_uf = [dict(zip([d.name for d in cur.description], r)) for r in cur.fetchall()]

    mun = Municipios()
    print(f"Grupo A: {len(sem)} postos sem coordenada")
    res_sem = []
    for i, p in enumerate(sem, 1):
        res_sem.append(geocodificar(p, mun, todas_camadas=False))
        if i % 10 == 0:
            print(f"  {i}/{len(sem)}", flush=True)
    print(f"Grupo B: {len(com)} postos com coordenada da ANP")
    res_com = []
    for i, p in enumerate(com, 1):
        r = geocodificar(p, mun, todas_camadas=True)
        for camada in r["camadas"].values():
            camada["erro_km"] = round(km(p["lon_anp"], p["lat_anp"], camada["lon"], camada["lat"]), 3)
        res_com.append(r)
        if i % 10 == 0:
            print(f"  {i}/{len(com)}", flush=True)

    # Resumo
    cobertura = {n: sum(1 for r in res_sem if r["nivel"] == n) for n in NIVEIS}
    erros: dict[str, list[float]] = {n: [] for n in NIVEIS}
    for r in res_com:
        for camada in r["camadas"].values():
            erros[camada["nivel"]].append(camada["erro_km"])
    erro_por_nivel = {
        n: {"casos": len(v), "mediana_km": round(percentil(v, .5), 2) if v else None,
            "p90_km": round(percentil(v, .9), 2) if v else None,
            "ate_300m": round(100 * sum(x <= 0.3 for x in v) / len(v)) if v else None,
            "ate_1km": round(100 * sum(x <= 1 for x in v) / len(v)) if v else None}
        for n, v in erros.items() if v}
    resultado = {
        "gerado_em": datetime.now().isoformat(timespec="minutes"),
        "amostra": args.n,
        "panorama_por_uf": por_uf,
        "cobertura_sem_coordenada": cobertura,
        "erro_com_coordenada": erro_por_nivel,
        "postos_sem_coordenada": res_sem,
        "postos_com_coordenada": res_com,
    }
    SAIDA.mkdir(parents=True, exist_ok=True)
    (SAIDA / "amostra_resultados.json").write_text(json.dumps(resultado, ensure_ascii=False, indent=1, default=str), encoding="utf-8")

    print("\nGrupo A, nível alcançado (postos sem coordenada):")
    for n, q in cobertura.items():
        print(f"  {n:<11} {q:>4}")
    print("\nGrupo B, distância até a coordenada da ANP por nível:")
    for n, e in erro_por_nivel.items():
        print(f"  {n:<11} casos={e['casos']:>3}  mediana={e['mediana_km']} km  p90={e['p90_km']} km  "
              f"até 300 m={e['ate_300m']}%  até 1 km={e['ate_1km']}%")
    total = sum(x["postos"] for x in por_uf)
    print(f"\nPanorama: {total} postos sem coordenada; com CEP de cidade inteira (termina em 000): "
          f"{sum(x['cep_da_cidade'] for x in por_uf)}; endereço com número: {sum(x['endereco_com_numero'] for x in por_uf)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
