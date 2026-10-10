"""
Carga semanal da pesquisa de preços da ANP (Levantamento de Preços de Combustíveis, por revenda).

Toda semana a ANP publica uma planilha com o preço de cada posto pesquisado:
  https://www.gov.br/anp/pt-br/assuntos/precos-e-defesa-da-concorrencia/precos/arquivos-lpc/<ano>/revendas_lpc_<domingo>_<sábado>.xlsx

O script descobre as semanas que faltam desde a coleta mais recente do banco, baixa cada planilha publicada,
grava os preços (sem duplicar) e recalcula as estimativas e os preços exibidos. Semana ainda não publicada é pulada.

Anomalia (mesma regra da limpeza inicial, scripts/anp/limpar_anp.py): preço fora da faixa do combustível, ou
a mais de 35% da mediana do combustível na UF na semana (com 5 preços ou mais) E a mais de 20% da mediana
do próprio posto nos 180 dias anteriores. Preço anômalo é guardado, mas nunca vira preço exibido.

Conexão: DATABASE_URL, ou SUPABASE_PROJECT_REF + SUPABASE_DB_PASSWORD (+ SUPABASE_POOLER_HOST), do ambiente
ou do .env. Schema das tabelas: SUPABASE_SCHEMA (padrão public; no servidor próprio, combustivel). Uso:
  python scripts/anp/carga_semanal.py              # carrega o que falta
  python scripts/anp/carga_semanal.py --simular    # só mostra o que faria
"""
from __future__ import annotations

import argparse
import io
import os
import re
import sys
import time
import urllib.error
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path
from urllib.parse import quote

import psycopg
from openpyxl import load_workbook

RAIZ = Path(__file__).resolve().parents[2]
BASE = "https://www.gov.br/anp/pt-br/assuntos/precos-e-defesa-da-concorrencia/precos/arquivos-lpc"
PRODUTOS = {"GASOLINA COMUM": 1, "GASOLINA ADITIVADA": 2, "ETANOL": 3, "DIESEL S500": 4, "DIESEL S10": 5, "GNV": 6}
DESVIO_UF, DESVIO_POSTO, MIN_AMOSTRA = 0.35, 0.20, 5


def configuracao() -> dict:
    env = dict(os.environ)
    arq = RAIZ / ".env"
    if arq.exists():
        sys.path.insert(0, str(RAIZ / "scripts" / "supabase"))
        import env_util  # noqa: PLC0415
        for k, v in env_util.carregar_env().items():
            env.setdefault(k, v)
    return env


def url_banco(env: dict) -> str:
    url = env.get("DATABASE_URL", "")
    if url.startswith("postgres") and "SENHA" not in url.upper() and "YOUR-PASSWORD" not in url.upper():
        return url
    ref = env.get("SUPABASE_PROJECT_REF") or env["SUPABASE_URL"].split("//")[1].split(".")[0]
    host = env.get("SUPABASE_POOLER_HOST", "aws-0-us-west-2.pooler.supabase.com")
    return f"postgresql://postgres.{ref}:{quote(env['SUPABASE_DB_PASSWORD'], safe='')}@{host}:5432/postgres"


def esquema(env: dict) -> str:
    """Schema das tabelas do app: public no Supabase da nuvem, combustivel no servidor próprio."""
    s = env.get("SUPABASE_SCHEMA") or "public"
    if not re.fullmatch(r"[a-z_][a-z0-9_]*", s):
        raise SystemExit(f"SUPABASE_SCHEMA inválido: {s!r}")
    return s


def no_esquema(sql: str, s: str) -> str:
    """As consultas são escritas com public.; aqui viram o schema configurado."""
    return sql.replace("public.", f"{s}.")


def domingo(d: date) -> date:
    return d - timedelta(days=(d.weekday() + 1) % 7)


def baixar(inicio: date) -> bytes | None:
    fim = inicio + timedelta(days=6)
    nome = f"revendas_lpc_{inicio:%Y-%m-%d}_{fim:%Y-%m-%d}.xlsx"
    for ano in dict.fromkeys((inicio.year, fim.year)):
        req = urllib.request.Request(f"{BASE}/{ano}/{nome}", headers={"User-Agent": "Mozilla/5.0 (gasprice; carga semanal)"})
        for tentativa in range(3):
            try:
                with urllib.request.urlopen(req, timeout=120) as r:
                    dados = r.read()
                return dados if dados[:2] == b"PK" else None
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    break
                time.sleep(5 * (tentativa + 1))
            except urllib.error.URLError:
                time.sleep(5 * (tentativa + 1))
    return None


def ler(dados: bytes) -> list[tuple[str, int, date, float]]:
    ws = load_workbook(io.BytesIO(dados), read_only=True).worksheets[0]
    linhas, cab = [], None
    for row in ws.iter_rows(values_only=True):
        if cab is None:
            if row and row[0] == "CNPJ":
                cab = {nome: i for i, nome in enumerate(row)}
            continue
        prod = PRODUTOS.get(str(row[cab["PRODUTO"]] or "").strip().upper())
        if prod is None or row[cab["CNPJ"]] is None:
            continue
        cnpj = "".join(ch for ch in str(row[cab["CNPJ"]]) if ch.isdigit()).zfill(14)
        quando = row[cab["DATA DA COLETA"]]
        quando = quando.date() if isinstance(quando, datetime) else quando
        try:
            preco = float(str(row[cab["PREÇO DE REVENDA"]]).replace(",", "."))
        except ValueError:
            continue
        if len(cnpj) == 14 and isinstance(quando, date) and 0 < preco < 100:
            linhas.append((cnpj, prod, quando, round(preco, 3)))
    return linhas


GRAVAR = f"""
with s as (
  select p.id as posto_id, s.produto_id, s.data_coleta, s.preco, p.uf, pr.preco_min, pr.preco_max
  from stg_semana s
  join public.postos p on p.cnpj = s.cnpj
  join public.produtos pr on pr.id = s.produto_id
),
uf as (
  select uf, produto_id, count(*) n, percentile_cont(0.5) within group (order by preco) mediana
  from s where preco between preco_min and preco_max group by 1, 2
),
posto as (
  select a.posto_id, a.produto_id, percentile_cont(0.5) within group (order by a.preco) mediana
  from public.precos_anp a
  where not a.anomalia and a.data_coleta >= (select min(data_coleta) from s) - 180
    and (a.posto_id, a.produto_id) in (select posto_id, produto_id from s)
  group by 1, 2
),
novos as (
  insert into public.precos_anp (posto_id, produto_id, data_coleta, preco, anomalia)
  select distinct on (s.posto_id, s.produto_id, s.data_coleta)
         s.posto_id, s.produto_id, s.data_coleta, s.preco,
         s.preco not between s.preco_min and s.preco_max
         or (uf.n >= {MIN_AMOSTRA} and abs(s.preco - uf.mediana) / uf.mediana > {DESVIO_UF}
             and (posto.mediana is null or abs(s.preco - posto.mediana) / posto.mediana > {DESVIO_POSTO}))
  from s
  left join uf on uf.uf = s.uf and uf.produto_id = s.produto_id
  left join posto on posto.posto_id = s.posto_id and posto.produto_id = s.produto_id
  order by s.posto_id, s.produto_id, s.data_coleta, s.preco
  on conflict (posto_id, produto_id, data_coleta) do nothing
  returning anomalia
)
select count(*), count(*) filter (where anomalia), (select count(*) from s),
       (select count(*) from stg_semana st where not exists (select 1 from public.postos p where p.cnpj = st.cnpj))
from novos
"""


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--simular", action="store_true")
    a = ap.parse_args()
    env = configuracao()
    esq = esquema(env)
    # autocommit: cada "with con.transaction()" abaixo é uma transação real, confirmada ao fim de cada semana
    con = psycopg.connect(url_banco(env), autocommit=True, connect_timeout=30)
    con.execute("set statement_timeout = '15min'")
    ultima = con.execute(no_esquema("select max(data_coleta) from public.precos_anp", esq)).fetchone()[0] or date(2024, 7, 1)
    semanas, s = [], domingo(ultima)
    while s <= date.today():
        semanas.append(s)
        s += timedelta(days=7)
    print(f"coleta mais recente no banco: {ultima:%d/%m/%Y}; semanas a verificar: {len(semanas)}")
    total_novos = 0
    resumo = []
    for inicio in semanas:
        dados = baixar(inicio)
        if dados is None:
            print(f"  {inicio:%d/%m/%Y}: planilha ainda não publicada")
            continue
        linhas = ler(dados)
        if a.simular:
            print(f"  {inicio:%d/%m/%Y}: {len(linhas)} preços na planilha (simulação: nada gravado)")
            continue
        with con.transaction():
            con.execute("create temp table if not exists stg_semana (cnpj char(14), produto_id smallint, data_coleta date, preco numeric(5,3)) on commit delete rows")
            with con.cursor().copy("copy stg_semana from stdin") as cp:
                for linha in linhas:
                    cp.write_row(linha)
            novos, anomalos, casados, sem_posto = con.execute(no_esquema(GRAVAR, esq)).fetchone()
        total_novos += novos
        resumo.append((inicio, len(linhas), casados, novos, anomalos, sem_posto))
        print(f"  {inicio:%d/%m/%Y}: {len(linhas)} preços; {casados} de postos cadastrados; {novos} novos; "
              f"{anomalos} anomalias; {sem_posto} de CNPJ fora do cadastro")
    if total_novos and not a.simular:
        print("recalculando municípios pesquisados, estimativas e preços exibidos…")
        with con.transaction():
            con.execute(no_esquema("select public.marcar_municipios_pesquisados()", esq))
            n_est = con.execute(no_esquema("select public.recalcular_estimativas()", esq)).fetchone()[0]
            n_atu = con.execute(no_esquema("select public.recalcular_precos_atuais()", esq)).fetchone()[0]
        print(f"estimativas: {n_est}; preços exibidos: {n_atu}")
    nova = con.execute(no_esquema("select max(data_coleta) from public.precos_anp", esq)).fetchone()[0]
    print(f"coleta mais recente agora: {nova:%d/%m/%Y}; preços novos: {total_novos}")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as f:
            f.write("## Carga semanal da ANP\n\n| Semana | Na planilha | De postos cadastrados | Novos | Anomalias |\n|---|---:|---:|---:|---:|\n")
            for inicio, lidos, casados, novos, anomalos, _ in resumo:
                f.write(f"| {inicio:%d/%m/%Y} | {lidos} | {casados} | {novos} | {anomalos} |\n")
            f.write(f"\nColeta mais recente no banco: **{nova:%d/%m/%Y}**.\n")
    con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
