"""
Publica o gasprice no projeto Supabase do .env.

Passos:
  1. banco     aplica as migrações (supabase db push, direto pela conexão do banco)
  2. funcoes   publica as Edge Functions (sem Docker: o servidor do Supabase faz o pacote)
  3. segredos  grava o CRON_SECRET nas funções e guarda o endereço e a senha da sincronização no Vault
  4. teste     chama cada função sem login e confere que ela respondeu com a mensagem certa
  5. dados     (opcional, --com-dados) carrega os dados da ANP com importar_anp.py

Uso:
  python scripts/supabase/verificar_env.py             # antes: tudo precisa estar ok
  python scripts/supabase/publicar.py --simular        # mostra os passos, sem executar nada
  python scripts/supabase/publicar.py
  python scripts/supabase/publicar.py --com-dados

Nenhum valor secreto é exibido: a saída dos comandos passa por uma máscara.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

import env_util as eu

FUNCOES = ["enviar-precos", "sincronizar-cadastro-anp", "excluir-conta"]
# Mensagem que cada função devolve quando chamada sem login: prova que o código dela rodou.
RESPOSTA_ESPERADA = {
    "enviar-precos": "Entre na sua conta",
    "sincronizar-cadastro-anp": "Não autorizado",
    "excluir-conta": "Entre na sua conta",
}


def achar_cli() -> str:
    candidatos = [os.environ.get("SUPABASE_CLI"), shutil.which("supabase"),
                  str(Path.home() / "dev-tools" / "supabase" / "supabase.exe")]
    for c in candidatos:
        if c and Path(c).exists():
            return c
    raise eu.ErroEnv("Supabase CLI não encontrada. Instale (supabase.com/docs/guides/cli) ou defina SUPABASE_CLI com o caminho.")


def executar(cmd: list[str], env_extra: dict[str, str], segredos: dict[str, str], timeout: int = 900) -> tuple[int, str]:
    r = subprocess.run(cmd, cwd=eu.RAIZ, env={**os.environ, **env_extra}, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout, stdin=subprocess.DEVNULL)
    return r.returncode, eu.mascarar(((r.stdout or "") + (r.stderr or "")).strip(), segredos)


def mostrar(texto: str) -> None:
    for linha in texto.splitlines()[-25:]:
        print("      " + linha)


def obrigatorias(env: dict[str, str]) -> None:
    faltando = [c for c in ("SUPABASE_URL", "SUPABASE_SECRET_KEY", "SUPABASE_ACCESS_TOKEN", "CRON_SECRET")
                if not eu.preenchido(env, c)]
    if not eu.preenchido(env, "SUPABASE_SECRET_KEY") and eu.preenchido(env, "SUPABASE_SERVICE_ROLE_KEY"):
        faltando = [c for c in faltando if c != "SUPABASE_SECRET_KEY"]
    if faltando:
        raise eu.ErroEnv("Faltam no .env (e o arquivo precisa estar salvo): " + ", ".join(faltando)
                         + ". Rode: python scripts/supabase/verificar_env.py")
    if not eu.ref_do_projeto(env):
        raise eu.ErroEnv("A SUPABASE_URL não tem o formato https://<20 letras>.supabase.co.")


def passo_banco(cli: str, url: str, segredos: dict) -> None:
    print("  [1/4] Aplicando as migrações no banco")
    cod, out = executar([cli, "db", "push", "--db-url", url, "--dry-run", "--yes"], {}, segredos)
    if cod:
        mostrar(out)
        raise eu.ErroEnv("O supabase db push --dry-run falhou. Confira a conexão com o banco: python scripts/supabase/verificar_env.py")
    mostrar(out)
    cod, out = executar([cli, "db", "push", "--db-url", url, "--yes"], {}, segredos)
    mostrar(out)
    if cod:
        raise eu.ErroEnv("Uma migração falhou. A saída acima mostra qual. As migrações já aplicadas ficam; corrija e rode de novo.")


def passo_funcoes(cli: str, ref: str, token: str, segredos: dict) -> None:
    print("  [2/4] Publicando as Edge Functions")
    for nome in FUNCOES:
        cod, out = executar([cli, "functions", "deploy", nome, "--project-ref", ref, "--use-api", "--no-verify-jwt"],
                            {"SUPABASE_ACCESS_TOKEN": token}, segredos)
        if cod:
            mostrar(out)
            raise eu.ErroEnv(f"Não consegui publicar a função {nome}.")
        print(f"      publicada: {nome}")


def passo_segredos(cli: str, ref: str, token: str, env: dict, url_banco: str, segredos: dict) -> None:
    print("  [3/4] Gravando os segredos")
    # O segredo vai por arquivo temporário, não pela linha de comando
    with tempfile.TemporaryDirectory() as d:
        arq = Path(d) / "segredos.env"
        arq.write_text(f"CRON_SECRET={env['CRON_SECRET'].strip()}\n", encoding="utf-8")
        cod, out = executar([cli, "secrets", "set", "--env-file", str(arq), "--project-ref", ref],
                            {"SUPABASE_ACCESS_TOKEN": token}, segredos)
    if cod:
        mostrar(out)
        raise eu.ErroEnv("Não consegui gravar o CRON_SECRET nas funções.")
    print("      CRON_SECRET gravado nas funções")

    import psycopg
    valores = {"project_url": env["SUPABASE_URL"].strip().rstrip("/"), "cron_secret": env["CRON_SECRET"].strip()}
    try:
        with psycopg.connect(url_banco, connect_timeout=30, prepare_threshold=None) as con, con.cursor() as cur:
            for nome, valor in valores.items():
                cur.execute("select id from vault.secrets where name = %s", (nome,))
                existente = cur.fetchone()
                if existente:
                    cur.execute("select vault.update_secret(%s, %s)", (existente[0], valor))
                else:
                    cur.execute("select vault.create_secret(%s, %s)", (valor, nome))
            con.commit()
    except psycopg.Error as e:
        raise eu.ErroEnv("Não consegui gravar no Vault do banco: " + eu.mascarar(str(e).strip().splitlines()[0], segredos))
    print("      Vault atualizado (a sincronização semanal com a ANP já pode se identificar)")


def passo_teste(env: dict) -> None:
    print("  [4/4] Testando as funções no ar")
    base = env["SUPABASE_URL"].strip().rstrip("/")
    problemas = []
    for nome in FUNCOES:
        req = urllib.request.Request(f"{base}/functions/v1/{nome}", data=b"{}", method="POST",
                                     headers={"Content-Type": "application/json", "x-cron-secret": "teste-invalido",
                                              "User-Agent": "gasprice-scripts/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                codigo, corpo = r.status, r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            codigo, corpo = e.code, e.read().decode("utf-8", "replace")
        except (urllib.error.URLError, TimeoutError, OSError):
            problemas.append(f"{nome}: sem resposta")
            continue
        try:
            mensagem = str(json.loads(corpo).get("erro", ""))
        except ValueError:
            mensagem = ""
        if codigo == 401 and RESPOSTA_ESPERADA[nome] in mensagem:
            print(f"      no ar: {nome}")
        elif codigo == 404:
            problemas.append(f"{nome}: não encontrada (não foi publicada?)")
        elif codigo == 401:
            problemas.append(f"{nome}: o gateway barrou antes do código rodar (JWT ligado). Publique com --no-verify-jwt")
        else:
            problemas.append(f"{nome}: resposta inesperada (HTTP {codigo})")
    if problemas:
        raise eu.ErroEnv("Teste das funções falhou: " + "; ".join(problemas))


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--simular", action="store_true", help="mostra os passos sem executar nada")
    ap.add_argument("--com-dados", action="store_true", help="depois de publicar, carrega os dados da ANP")
    ap.add_argument("--so-banco", action="store_true", help="aplica só as migrações novas (não publica funções nem segredos)")
    args = ap.parse_args()

    try:
        env = eu.carregar_env()
        if args.so_banco:
            url_banco, origem = eu.resolver_database_url(env)
            print(f"Aplicando só as migrações (conexão: {origem})\n")
            passo_banco(achar_cli(), url_banco, {**env, "DATABASE_URL": url_banco})
            print("\nMigrações aplicadas.")
            return 0
        obrigatorias(env)
        ref = eu.ref_do_projeto(env)
        cli = achar_cli()
        if args.simular:
            print(f"Simulação para o projeto {ref}. Nada será executado.\n")
            print("  0. Descobrir o endereço do banco (DATABASE_URL, ou senha + token pela API do Supabase)")
            print("  1. supabase db push --db-url <banco> (primeiro com --dry-run)")
            for f in FUNCOES:
                print(f"  2. supabase functions deploy {f} --project-ref {ref} --use-api --no-verify-jwt")
            print("  3. supabase secrets set --env-file <temporário> (CRON_SECRET) e Vault: project_url, cron_secret")
            print("  4. chamar cada função sem login e conferir a mensagem de resposta")
            if args.com_dados:
                print("  5. python scripts/supabase/importar_anp.py")
            return 0

        url_banco, origem = eu.resolver_database_url(env)
        segredos = {**env, "DATABASE_URL": url_banco}
        token = env["SUPABASE_ACCESS_TOKEN"].strip()
        print(f"Publicando no projeto {ref} (conexão: {origem})\n")
        passo_banco(cli, url_banco, segredos)
        passo_funcoes(cli, ref, token, segredos)
        passo_segredos(cli, ref, token, env, url_banco, segredos)
        passo_teste(env)
        if args.com_dados:
            print("\nCarregando os dados da ANP (leva alguns minutos)")
            r = subprocess.run([sys.executable, str(Path(__file__).with_name("importar_anp.py"))], cwd=eu.RAIZ)
            if r.returncode:
                return r.returncode
    except eu.ErroEnv as e:
        print(f"\nParei: {e}")
        return 1
    except subprocess.TimeoutExpired:
        print("\nParei: um comando passou do tempo limite.")
        return 1
    print("\nPublicado.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
