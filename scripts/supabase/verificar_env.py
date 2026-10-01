"""
Confere o .env e testa cada chave contra o Supabase, sem exibir nenhum valor.

Uso:
  python scripts/supabase/verificar_env.py
  python scripts/supabase/verificar_env.py --gerar-cron-secret   # cria o CRON_SECRET se estiver vazio

Testes feitos (cada um só mostra ok, falha ou aviso):
  1. URL do projeto e chave publishable
  2. Chave secreta (e se ela vazou para o app/config/app.json)
  3. Token de acesso (nome, região e situação do projeto)
  4. Conexão com o banco (a DATABASE_URL ou a URL montada pela API), PostGIS e tabelas do gasprice
  5. CRON_SECRET
Sai com código 0 quando tudo o que é obrigatório está pronto.
"""
from __future__ import annotations

import argparse
import json
import re
import secrets
import sys
import urllib.error
import urllib.request

import env_util as eu

OK, FALHA, AVISO, PULADO = "ok   ", "FALHA", "aviso", "pulou"
resultados: list[tuple[str, str, str]] = []


def registrar(status: str, nome: str, detalhe: str = "") -> None:
    resultados.append((status, nome, detalhe))
    print(f"[{status}] {nome}" + (f": {detalhe}" if detalhe else ""))


def http(url: str, cabecalhos: dict | None = None, timeout: int = 20) -> tuple[int, bytes]:
    req = urllib.request.Request(url, headers={"User-Agent": "gasprice-scripts/1.0", **(cabecalhos or {})})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        return 0, str(e).encode()


def cabecalhos_chave(chave: str) -> dict:
    # Chaves novas (sb_...) vão só em "apikey"; as antigas (JWT) também em Authorization.
    h = {"apikey": chave}
    if chave.startswith("eyJ"):
        h["Authorization"] = f"Bearer {chave}"
    return h


def conferir_preenchimento(env: dict) -> None:
    obrigatorias = [
        ("SUPABASE_URL", "URL do projeto"),
        ("SUPABASE_PUBLISHABLE_KEY", "chave publishable"),
        ("SUPABASE_SECRET_KEY", "chave secreta"),
        ("SUPABASE_DB_PASSWORD", "senha do banco"),
        ("SUPABASE_ACCESS_TOKEN", "token de acesso"),
        ("CRON_SECRET", "senha da sincronização"),
    ]
    print("Chaves no .env")
    for chave, rotulo in obrigatorias:
        est = eu.estado(chave, env.get(chave))
        if chave == "SUPABASE_SECRET_KEY" and est == "vazio" and eu.preenchido(env, "SUPABASE_SERVICE_ROLE_KEY"):
            est = "preenchido"
        texto = {"vazio": "vazio", "exemplo": "ainda com o texto de exemplo", "preenchido": "preenchido"}[est]
        print(f"  {chave:<26} {texto}")
    opcionais = [("DATABASE_URL", "montada sozinha se ficar vazia"), ("SUPABASE_PROJECT_REF", "sai da SUPABASE_URL")]
    for chave, nota in opcionais:
        print(f"  {chave:<26} {eu.estado(chave, env.get(chave))} ({nota})")
    print()


def testar_url_e_publishable(env: dict) -> None:
    nome = "URL do projeto e chave publishable"
    if not eu.preenchido(env, "SUPABASE_URL") or not eu.preenchido(env, "SUPABASE_PUBLISHABLE_KEY"):
        return registrar(FALHA, nome, "preencha SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY")
    if eu.ref_do_projeto(env) is None:
        registrar(AVISO, "Formato da URL", "esperado https://<20 letras>.supabase.co")
    chave = env["SUPABASE_PUBLISHABLE_KEY"].strip()
    if chave.startswith("sb_secret_"):
        return registrar(FALHA, nome, "você colocou uma chave SECRETA neste campo. Use a publishable (sb_publishable_...)")
    codigo, corpo = http(env["SUPABASE_URL"].strip().rstrip("/") + "/auth/v1/settings", cabecalhos_chave(chave))
    if codigo == 200:
        registrar(OK, nome, "o projeto respondeu e aceitou a chave")
    elif codigo in (401, 403):
        registrar(FALHA, nome, "o projeto existe, mas recusou a chave. Copie de novo em Project Settings > API Keys")
    elif codigo == 0:
        registrar(FALHA, nome, "sem resposta. Confira a URL. Projetos gratuitos pausam após 1 semana sem uso: abra o painel e clique em Restore")
    else:
        registrar(AVISO, nome, f"resposta inesperada (HTTP {codigo})")


def testar_secreta(env: dict) -> None:
    nome = "Chave secreta"
    chave = (env.get("SUPABASE_SECRET_KEY") or "").strip()
    if eu.estado("SUPABASE_SECRET_KEY", chave) != "preenchido":
        chave = (env.get("SUPABASE_SERVICE_ROLE_KEY") or "").strip()
    if not chave or eu.estado("SUPABASE_SECRET_KEY", chave) == "exemplo":
        return registrar(FALHA, nome, "preencha SUPABASE_SECRET_KEY (sb_secret_...)")
    if chave.startswith("sb_publishable_"):
        return registrar(FALHA, nome, "você colocou a chave PUBLISHABLE neste campo. A secreta começa com sb_secret_")
    if not eu.preenchido(env, "SUPABASE_URL"):
        return registrar(PULADO, nome, "depende da SUPABASE_URL")
    codigo, _ = http(env["SUPABASE_URL"].strip().rstrip("/") + "/auth/v1/admin/users?per_page=1", cabecalhos_chave(chave))
    if codigo == 200:
        registrar(OK, nome, "aceita pelo servidor")
    elif codigo in (401, 403):
        registrar(FALHA, nome, "recusada. Copie de novo em Project Settings > API Keys > Secret keys")
    elif codigo == 0:
        registrar(PULADO, nome, "sem resposta do projeto")
    else:
        registrar(AVISO, nome, f"não consegui confirmar (HTTP {codigo})")

    # A chave secreta nunca pode ir no app
    app_json = eu.RAIZ / "app" / "config" / "app.json"
    if app_json.exists() and chave in app_json.read_text(encoding="utf-8"):
        registrar(FALHA, "Vazamento", "a chave secreta está em app/config/app.json. Apague-a de lá e gere outra no painel")


def testar_token(env: dict) -> None:
    nome = "Token de acesso"
    if not eu.preenchido(env, "SUPABASE_ACCESS_TOKEN"):
        return registrar(FALHA, nome, "preencha SUPABASE_ACCESS_TOKEN (sbp_...): supabase.com/dashboard/account/tokens")
    ref = eu.ref_do_projeto(env)
    if not ref:
        return registrar(PULADO, nome, "depende da SUPABASE_URL")
    codigo, corpo = http(f"{eu.API_SUPABASE}/v1/projects/{ref}", {"Authorization": f"Bearer {env['SUPABASE_ACCESS_TOKEN'].strip()}"})
    if codigo == 200:
        try:
            j = json.loads(corpo)
            situacao = j.get("status", "?")
            detalhe = f"projeto \"{j.get('name', '?')}\", região {j.get('region', '?')}, situação {situacao}"
            if situacao not in ("ACTIVE_HEALTHY", "ACTIVE"):
                return registrar(AVISO, nome, detalhe + ". Se estiver pausado, clique em Restore no painel")
            registrar(OK, nome, detalhe)
        except ValueError:
            registrar(OK, nome, "aceito")
    elif codigo == 401:
        registrar(FALHA, nome, "token recusado. Gere outro em supabase.com/dashboard/account/tokens")
    elif codigo in (403, 404):
        registrar(FALHA, nome, "o token não enxerga este projeto. Ele precisa ser da mesma conta que criou o projeto")
    elif codigo == 0:
        registrar(PULADO, nome, "sem conexão com api.supabase.com")
    else:
        registrar(AVISO, nome, f"resposta inesperada (HTTP {codigo})")


def explicar_erro_banco(msg: str) -> str:
    m = msg.lower()
    if "tenant or user not found" in m:
        return ("o pooler não reconhece o projeto: região ou usuário errados na string. "
                "Deixe a DATABASE_URL vazia que eu monto a certa, ou copie de Connect > Session pooler")
    if "password authentication failed" in m or "authentication failed" in m:
        return "senha do banco incorreta. Para trocar: Project Settings > Database > Reset database password"
    if any(t in m for t in ("timeout", "timed out", "could not translate", "network is unreachable", "no route", "could not connect", "connection refused")):
        return ("não consegui alcançar o servidor. A conexão direta (db.xxx.supabase.co) só funciona com IPv6; "
                "use o Session pooler, que funciona em qualquer rede")
    if "ssl" in m:
        return "problema de SSL na conexão"
    return "erro ao conectar: " + msg.strip().splitlines()[0][:160]


def testar_banco(env: dict) -> None:
    nome = "Banco de dados"
    try:
        url, origem = eu.resolver_database_url(env)
    except eu.ErroEnv as e:
        return registrar(FALHA, nome, str(e))
    try:
        import psycopg
    except ImportError:
        return registrar(AVISO, nome, "instale o driver: pip install -r scripts/requirements.txt")
    try:
        with psycopg.connect(url, connect_timeout=20, prepare_threshold=None) as con, con.cursor() as cur:
            cur.execute("select current_setting('server_version'), (select count(*) from pg_extension where extname = 'postgis')")
            versao, postgis = cur.fetchone()
            cur.execute("select to_regclass('public.postos') is not null, to_regclass('public.precos_atuais') is not null")
            tem_postos, tem_precos = cur.fetchone()
        registrar(OK, nome, f"conectou (Postgres {versao}; URL {origem})")
        registrar(OK if postgis else AVISO, "PostGIS", "instalado" if postgis else "ainda não instalado (a migração instala)")
        registrar(OK if (tem_postos and tem_precos) else AVISO, "Tabelas do gasprice",
                  "já criadas" if (tem_postos and tem_precos) else "ainda não criadas: rode a publicação")
    except Exception as e:  # noqa: BLE001
        registrar(FALHA, nome, eu.mascarar(explicar_erro_banco(str(e)), env))


def conferir_cron(env: dict, gerar: bool) -> None:
    nome = "CRON_SECRET"
    valor = (env.get("CRON_SECRET") or "").strip()
    if not valor and gerar:
        novo = secrets.token_urlsafe(32)
        arq = eu.ARQUIVO_ENV
        texto = arq.read_text(encoding="utf-8-sig")
        if re.search(r"(?m)^\s*CRON_SECRET\s*=.*$", texto):
            texto = re.sub(r"(?m)^\s*CRON_SECRET\s*=.*$", f"CRON_SECRET={novo}", texto)
        else:
            texto += f"\nCRON_SECRET={novo}\n"
        arq.write_text(texto, encoding="utf-8")
        env["CRON_SECRET"] = novo
        return registrar(OK, nome, "gerado e gravado no .env (43 caracteres)")
    if not valor:
        return registrar(FALHA, nome, "vazio. Rode com --gerar-cron-secret para criar um automaticamente")
    if len(valor) < 24:
        return registrar(AVISO, nome, f"curto demais ({len(valor)} caracteres). Use 24 ou mais")
    registrar(OK, nome, "preenchido")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gerar-cron-secret", action="store_true")
    args = ap.parse_args()
    try:
        env = eu.carregar_env()
    except eu.ErroEnv as e:
        print(e)
        return 1

    conferir_preenchimento(env)
    print("Testes")
    testar_url_e_publishable(env)
    testar_secreta(env)
    testar_token(env)
    testar_banco(env)
    conferir_cron(env, args.gerar_cron_secret)

    falhas = [r for r in resultados if r[0] == FALHA]
    print()
    if falhas:
        print(f"Faltam {len(falhas)} item(ns) obrigatório(s). Corrija, salve o .env e rode de novo.")
        return 1
    print("Tudo pronto para publicar.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
