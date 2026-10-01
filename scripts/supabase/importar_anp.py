"""
Carrega os dados da ANP no Supabase do projeto.

Passos (cada um pode ser pulado com --pular NOME):
  cadastro   chama a Edge Function sincronizar-cadastro-anp para as 27 UFs (postos + coordenadas)
  historico  cria como inativos os postos que só existem no histórico de preços
  precos     carrega os preços ANP a partir de 01/07/2024 (cabe no plano gratuito)
  storage    envia a série completa compactada para o bucket privado anp-historico
  calculos   marca municípios pesquisados, recalcula estimativas e preços exibidos

Lê as chaves do arquivo .env na raiz do projeto (nunca imprime os valores):
  SUPABASE_URL, SUPABASE_SECRET_KEY (ou SUPABASE_SERVICE_ROLE_KEY), CRON_SECRET, e a conexão com o banco.
  A conexão vem da DATABASE_URL ou, se ela estiver vazia, é montada com SUPABASE_DB_PASSWORD e
  SUPABASE_ACCESS_TOKEN (a API do Supabase informa o endereço do pooler).

Uso:
  python scripts/supabase/verificar_env.py          # antes: confere as chaves
  python scripts/supabase/importar_anp.py
  python scripts/supabase/importar_anp.py --pular cadastro storage
Requer: psycopg[binary]
"""
from __future__ import annotations

import argparse
import csv
import gzip
import io
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import psycopg

import env_util as eu

RAIZ = Path(__file__).resolve().parents[2]
LIMPO = RAIZ / "dados" / "anp_limpo"
INICIO_BANCO = "2024-07-01"
UFS = ["AC", "AL", "AM", "AP", "BA", "CE", "DF", "ES", "GO", "MA", "MG", "MS", "MT", "PA",
       "PB", "PE", "PI", "PR", "RJ", "RN", "RO", "RR", "RS", "SC", "SE", "SP", "TO"]


def exigir(env: dict, *chaves: str) -> None:
    faltando = [c for c in chaves if not eu.preenchido(env, c)]
    if faltando:
        sys.exit(f"Preencha no .env (e salve o arquivo): {', '.join(faltando)}. "
                 "Para conferir: python scripts/supabase/verificar_env.py")


def chave_secreta(env: dict) -> str:
    for k in ("SUPABASE_SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY"):
        if eu.preenchido(env, k):
            return env[k].strip()
    sys.exit("Preencha no .env (e salve o arquivo): SUPABASE_SECRET_KEY")


def post_json(url: str, corpo: dict, cabecalhos: dict, timeout: int = 180) -> tuple[int, dict]:
    req = urllib.request.Request(url, data=json.dumps(corpo).encode(), method="POST",
                                 headers={"Content-Type": "application/json", **cabecalhos})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def passo_cadastro(env: dict) -> None:
    exigir(env, "SUPABASE_URL", "CRON_SECRET")
    url = env["SUPABASE_URL"].rstrip("/") + "/functions/v1/sincronizar-cadastro-anp"
    total = 0
    for uf in UFS:
        status, corpo = post_json(url, {"uf": uf}, {"x-cron-secret": env["CRON_SECRET"]}, timeout=200)
        if status != 200:
            print(f"  {uf}: falhou ({status}) {corpo.get('erro')} {corpo.get('detalhes', '')}")
            continue
        total += corpo.get("postos", 0)
        print(f"  {uf}: {corpo.get('postos')} postos, {corpo.get('sem_coordenada')} sem coordenada")
        time.sleep(1)
    print(f"  cadastro: {total} postos sincronizados")


def passo_historico(con: psycopg.Connection) -> None:
    with con.cursor() as cur, open(LIMPO / "postos.csv", encoding="utf-8") as f:
        cur.execute("""create temp table stg_postos (
            id int, cnpj text, razao_social text, bandeira text, logradouro text, numero text, complemento text,
            bairro text, municipio text, uf text, cep text, primeira_coleta date, ultima_coleta date) on commit drop""")
        with cur.copy("copy stg_postos from stdin with (format csv, header true)") as cp:
            while bloco := f.read(1 << 20):
                cp.write(bloco)
        cur.execute("""
            insert into public.postos (cnpj, razao_social, bandeira, endereco, complemento, bairro, municipio, uf, cep, ativo)
            select cnpj, razao_social, nullif(bandeira, ''),
                   nullif(trim(coalesce(logradouro, '') || ', ' || coalesce(numero, ''), ', '), ''),
                   nullif(complemento, ''), nullif(bairro, ''), municipio, uf, nullif(cep, ''), false
            from stg_postos
            on conflict (cnpj) do nothing""")
        print(f"  histórico: {cur.rowcount} postos antigos criados como inativos")
    con.commit()


def passo_precos(con: psycopg.Connection) -> None:
    ids_locais = {}
    with open(LIMPO / "postos.csv", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            ids_locais[r["id"]] = r["cnpj"]
    with con.cursor() as cur:
        cur.execute("create temp table stg_precos (cnpj text, produto_id smallint, data_coleta date, preco numeric(5,3), anomalia boolean) on commit drop")
        n = 0
        with cur.copy("copy stg_precos from stdin") as cp, open(LIMPO / "precos_anp.csv", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                if r["data_coleta"] < INICIO_BANCO:
                    continue
                cp.write_row((ids_locais[r["posto_id"]], int(r["produto_id"]), r["data_coleta"], r["preco"], r["anomalia"] == "true"))
                n += 1
        cur.execute("""
            insert into public.precos_anp (posto_id, produto_id, data_coleta, preco, anomalia)
            select p.id, s.produto_id, s.data_coleta, s.preco, s.anomalia
            from stg_precos s join public.postos p on p.cnpj = s.cnpj
            on conflict (posto_id, produto_id, data_coleta) do update set preco = excluded.preco, anomalia = excluded.anomalia""")
        print(f"  preços: {n} lidos, {cur.rowcount} gravados (desde {INICIO_BANCO})")
    con.commit()


def passo_storage(env: dict) -> None:
    exigir(env, "SUPABASE_URL")
    chave = chave_secreta(env)
    # Chaves novas (sb_...) vão só em "apikey"; as antigas (JWT) também em Authorization.
    autenticacao = {"apikey": chave}
    if chave.startswith("eyJ"):
        autenticacao["Authorization"] = f"Bearer {chave}"
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", compresslevel=9) as gz, open(LIMPO / "precos_anp.csv", "rb") as f:
        while bloco := f.read(1 << 20):
            gz.write(bloco)
    dados = buf.getvalue()
    url = env["SUPABASE_URL"].rstrip("/") + "/storage/v1/object/anp-historico/precos_anp_2020_2026.csv.gz"
    req = urllib.request.Request(url, data=dados, method="POST", headers={
        **autenticacao, "Content-Type": "application/gzip", "x-upsert": "true"})
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            print(f"  storage: série completa enviada ({len(dados) / 1e6:.1f} MB), status {r.status}")
    except urllib.error.HTTPError as e:
        sys.exit(f"O Storage recusou o envio (HTTP {e.code}). O bucket anp-historico é criado pela migração; "
                 "confira se o banco já foi publicado e se a chave secreta está correta.")


def passo_calculos(con: psycopg.Connection) -> None:
    with con.cursor() as cur:
        cur.execute("set statement_timeout = '45min'")
        cur.execute("select public.marcar_municipios_pesquisados()")
        cur.execute("select public.recalcular_estimativas()")
        print(f"  estimativas: {cur.fetchone()[0]} preços estimados")
        cur.execute("select public.recalcular_precos_atuais()")
        print(f"  preços exibidos: {cur.fetchone()[0]} combinações de posto e combustível")
    con.commit()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pular", nargs="*", default=[], choices=["cadastro", "historico", "precos", "storage", "calculos"])
    args = ap.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    try:
        env = eu.carregar_env()
        url_banco, origem = eu.resolver_database_url(env)
    except eu.ErroEnv as e:
        sys.exit(str(e))
    print(f"Conexão com o banco: {origem}")

    if "cadastro" not in args.pular:
        print("1/5 Sincronizando cadastro de postos pela API da ANP")
        passo_cadastro(env)
    try:
        con_ctx = psycopg.connect(url_banco, connect_timeout=30, prepare_threshold=None)
    except psycopg.Error as e:
        sys.exit("Não consegui conectar ao banco: " + eu.mascarar(str(e).strip().splitlines()[0], env)
                 + "\nRode: python scripts/supabase/verificar_env.py")
    with con_ctx as con:
        if "historico" not in args.pular:
            print("2/5 Postos do histórico")
            passo_historico(con)
        if "precos" not in args.pular:
            print("3/5 Preços ANP")
            passo_precos(con)
        if "storage" not in args.pular:
            print("4/5 Série completa no Storage")
            passo_storage(env)
        if "calculos" not in args.pular:
            print("5/5 Cálculos")
            passo_calculos(con)
    print("Concluído.")


if __name__ == "__main__":
    main()
