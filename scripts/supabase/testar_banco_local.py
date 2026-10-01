"""
Testa as migrações e as regras de negócio num Postgres local com PostGIS.

Cria um banco temporário, aplica supabase/tests/shims_supabase.sql (simula o
que o Supabase já traz), todas as migrações e depois supabase/tests/regras_test.sql.
As extensões pg_cron e pg_net são simuladas pelos shims.

Uso:
  python scripts/supabase/testar_banco_local.py --pg-bin "C:/caminho/pgsql/bin"
Requer PostgreSQL 15+ com PostGIS instalado nessa pasta (bin/initdb, pg_ctl, psql).
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
PADRAO = os.environ.get("PG_BIN", r"C:\Users\michael\dev-tools\pgsql\bin")


def rodar(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=600, **kw)


def iniciar_servidor(pg_ctl: str, dados: Path, porta: int) -> None:
    # Sem capturar a saída: o servidor herdaria o pipe e o script esperaria para sempre.
    r = subprocess.run(
        [pg_ctl, "-D", str(dados), "-o", f"-p {porta}", "-l", str(dados / "log.txt"), "-w", "-t", "60", "start"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, timeout=120,
    )
    if r.returncode:
        sys.exit("Não foi possível iniciar o Postgres de teste. Veja " + str(dados / "log.txt"))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pg-bin", default=PADRAO)
    ap.add_argument("--porta", type=int, default=54329)
    a = ap.parse_args()
    bin_ = Path(a.pg_bin)
    exe = lambda nome: str(bin_ / (nome + (".exe" if os.name == "nt" else "")))

    dados = Path(tempfile.gettempdir()) / "gasprice-pg-teste"
    if dados.exists():
        subprocess.run([exe("pg_ctl"), "-D", str(dados), "stop", "-m", "immediate"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
        shutil.rmtree(dados, ignore_errors=True)
    r = rodar([exe("initdb"), "-D", str(dados), "-U", "postgres", "-A", "trust", "-E", "UTF8", "--locale=C"])
    if r.returncode:
        sys.exit(r.stderr)
    iniciar_servidor(exe("pg_ctl"), dados, a.porta)

    env = {**os.environ, "PGCLIENTENCODING": "UTF8"}
    psql = [exe("psql"), "-h", "localhost", "-p", str(a.porta), "-U", "postgres", "-d", "postgres",
            "-v", "ON_ERROR_STOP=1", "-q", "-X"]
    try:
        arquivos = [RAIZ / "supabase" / "tests" / "shims_supabase.sql"]
        arquivos += sorted((RAIZ / "supabase" / "migrations").glob("*.sql"))
        for arq in arquivos:
            sql = arq.read_text(encoding="utf-8")
            # pg_cron e pg_net não existem fora do Supabase: os shims fazem o papel deles
            sql = re.sub(r"(?im)^create extension if not exists pg_(cron|net)\s*;",
                         r"-- teste local: pg_\1 simulada", sql)
            tmp = dados / arq.name
            tmp.write_text(sql, encoding="utf-8")
            r = rodar(psql + ["-f", str(tmp)], env=env)
            if r.returncode:
                print(r.stdout, r.stderr)
                sys.exit(f"FALHOU ao aplicar {arq.name}")
            print(f"aplicado: {arq.name}")

        r = rodar(psql + ["-f", str(RAIZ / "supabase" / "tests" / "regras_test.sql")], env=env)
        for linha in (r.stderr + "\n" + r.stdout).splitlines():
            linha = linha.replace("psql:", "").strip()
            if "NOTICE:" in linha or "ERROR" in linha or "FALHOU" in linha or "TODOS" in linha:
                print(linha.split("NOTICE:")[-1].strip() if "NOTICE:" in linha else linha)
        if r.returncode:
            sys.exit("Algum teste falhou.")
    finally:
        subprocess.run([exe("pg_ctl"), "-D", str(dados), "stop", "-m", "fast"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120)


if __name__ == "__main__":
    main()
