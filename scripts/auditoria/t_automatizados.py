"""
Roda as suítes automáticas do repositório e registra cada caso como uma linha da matriz:
análise estática do Dart, testes do app (Flutter), das Edge Functions (Deno), dos scripts (Python)
e das regras do banco num Postgres 17 + PostGIS local.

Uso: python scripts/auditoria/t_automatizados.py
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

from comum import ALTA, BAIXA, CRITICA, EVIDENCIAS, MEDIA, RAIZ, Suite

FERRAMENTAS = r"C:\Users\michael\dev-tools"
ENV = {**os.environ, "PATH": os.pathsep.join([rf"{FERRAMENTAS}\flutter\bin", rf"{FERRAMENTAS}\git\cmd", rf"{FERRAMENTAS}\deno",
                                              os.environ.get("PATH", "")]), "PYTHONIOENCODING": "utf-8"}
LOGS = RAIZ / "documentacao" / "auditoria" / "logs"


def rodar(cmd, cwd, timeout=1200) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True, text=True, encoding="utf-8", errors="replace",
                          timeout=timeout, shell=isinstance(cmd, str))


def guardar(nome: str, texto: str) -> str:
    LOGS.mkdir(parents=True, exist_ok=True)
    (LOGS / nome).write_text(texto, encoding="utf-8")
    return f"logs/{nome}"


def analise_estatica(s: Suite) -> None:
    r = rodar("flutter analyze --no-pub", RAIZ / "app")
    ev = guardar("flutter_analyze.txt", r.stdout + r.stderr)
    m = re.search(r"(\d+) issues? found", r.stdout + r.stderr)
    s.check(r.returncode == 0 and "No issues found" in r.stdout, obtido=(m.group(0) if m else "No issues found!") if r.returncode == 0 else (r.stdout + r.stderr)[-600:],
            aba="Regressão", modulo="App Flutter", tela="Código do app", tipo="Análise estática", cenario="flutter analyze sem avisos nem erros",
            precondicoes="Dependências instaladas", passos="flutter analyze --no-pub", entrada="app/lib, app/test",
            esperado="No issues found", severidade=MEDIA, evidencia=ev)
    r = rodar(r"deno check enviar-precos/index.ts corrigir-posicao/index.ts sincronizar-cadastro-anp/index.ts excluir-conta/index.ts",
              RAIZ / "supabase" / "functions")
    ev = guardar("deno_check.txt", r.stdout + r.stderr)
    s.check(r.returncode == 0, obtido="sem erros de tipo" if r.returncode == 0 else (r.stdout + r.stderr)[-600:],
            aba="Regressão", modulo="Edge Functions", tela="Código das funções", tipo="Análise estática",
            cenario="deno check das 4 Edge Functions", precondicoes="Deno 2", passos="deno check <4 arquivos>", entrada="-",
            esperado="Sem erros de tipo", severidade=ALTA, evidencia=ev)


def flutter_testes(s: Suite) -> None:
    r = rodar("flutter test --no-pub --reporter json", RAIZ / "app")
    ev = guardar("flutter_test.jsonl", r.stdout)
    nomes, arquivos, grupos = {}, {}, {}
    for linha in r.stdout.splitlines():
        try:
            e = json.loads(linha)
        except ValueError:
            continue
        if e.get("type") == "suite":
            arquivos[e["suite"]["id"]] = os.path.basename(e["suite"]["path"])
        if e.get("type") == "testStart":
            t = e["test"]
            if t["name"].startswith("loading "):
                continue
            nomes[t["id"]] = (t["name"], arquivos.get(t["suiteID"], "?"))
        if e.get("type") == "testDone" and e["testID"] in nomes and not e.get("hidden"):
            nome, arq = nomes[e["testID"]]
            ok = e["result"] == "success"
            s.check(ok, obtido=f"{e['result']} em {e.get('time', 0)} ms (tempo acumulado da suíte)",
                    aba="Regressão", modulo="App Flutter", tela=arq, tipo="Teste automatizado · unidade/widget",
                    cenario=nome, precondicoes="flutter test", passos=f"flutter test {arq}", entrada="-",
                    esperado="success", severidade=MEDIA, evidencia=ev)
            grupos[arq] = grupos.get(arq, 0) + 1
    if not grupos:
        s.add(status="BLOCKED", obtido=(r.stdout + r.stderr)[-500:], aba="Regressão", modulo="App Flutter", tela="flutter test",
              tipo="Teste automatizado", cenario="Rodar a suíte do app", precondicoes="-", passos="flutter test", entrada="-",
              esperado="Testes executados", severidade=ALTA)


def deno_testes(s: Suite) -> None:
    r = rodar("deno test --reporter=junit", RAIZ / "supabase" / "functions")
    ev = guardar("deno_test.xml", r.stdout)
    try:
        raiz = ET.fromstring(r.stdout[r.stdout.index("<?xml"):] if "<?xml" in r.stdout else r.stdout)
    except (ET.ParseError, ValueError):
        s.add(status="BLOCKED", obtido=(r.stdout + r.stderr)[-500:], aba="Edge Functions", modulo="Validação", tela="deno test",
              tipo="Teste automatizado", cenario="Rodar a suíte das funções", precondicoes="-", passos="deno test", entrada="-",
              esperado="Testes executados", severidade=ALTA)
        return
    for caso in raiz.iter("testcase"):
        falhou = caso.find("failure") is not None or caso.find("error") is not None
        arq = (caso.get("classname") or "").split("/")[-1]
        mod = "corrigir-posicao" if "corrigir" in (caso.get("classname") or "") else (
            "sincronizar-cadastro-anp" if "normalizar" in arq else "enviar-precos")
        s.check(not falhou, obtido=f"{'falhou' if falhou else 'passou'} em {float(caso.get('time') or 0) * 1000:.0f} ms",
                aba="Edge Functions", modulo=mod, tela=arq or "validação", tipo="Teste automatizado · unidade",
                cenario=caso.get("name") or "?", precondicoes="deno test", passos=f"deno test {arq}", entrada="-",
                esperado="passou", severidade=MEDIA, evidencia=ev)


def python_testes(s: Suite) -> None:
    r = rodar([sys.executable, "-m", "unittest", "discover", "-s", "scripts/supabase", "-p", "test_*.py", "-v"], RAIZ)
    ev = guardar("python_unittest.txt", r.stderr + r.stdout)
    for m in re.finditer(r"^(test\w+) \(([\w.]+)\)(?:\n.*?)? \.\.\. (ok|FAIL|ERROR|skipped.*)$", r.stderr, flags=re.M):
        nome, classe, res = m.groups()
        s.check(res == "ok", obtido=res, aba="Regressão", modulo="Scripts de publicação", tela=classe.split(".")[0],
                tipo="Teste automatizado · unidade", cenario=f"{classe.split('.')[-1]}.{nome}", precondicoes="Python 3.12",
                passos="python -m unittest discover -s scripts/supabase", entrada="-", esperado="ok", severidade=BAIXA, evidencia=ev)


MODULOS_REGRAS = [
    ("Consenso", ("consenso", "confirm", "cluster", "toler", "revis", "contest")),
    ("Pontos e confiabilidade", ("ponto", "confiab", "teto", "bloque", "bônus", "bonus")),
    ("Preço exibido", ("exibid", "anp", "estimat", "diverg", "anomalia", "fonte", "recalcul")),
    ("Localização dos postos", ("posição", "posicao", "precis", "mapa", "raio", "cep", "rua")),
    ("Avisos de preço", ("aviso", "notific")),
    ("Avaliações", ("avalia", "nota", "voto")),
    ("Permissões", ("anon", "permiss", "acesso", "rls", "não pode", "nao pode")),
    ("Importação ANP", ("import", "sincroniz", "cadastro")),
]


def regras_banco(s: Suite) -> None:
    r = rodar([sys.executable, str(RAIZ / "scripts" / "supabase" / "testar_banco_local.py")], RAIZ, timeout=1800)
    saida = r.stdout + r.stderr
    ev = guardar("regras_banco_local.txt", saida)
    casos = re.findall(r"^ok\s+(.*)$", saida, flags=re.M)
    for msg in casos:
        baixa = msg.lower()
        mod = next((m for m, chaves in MODULOS_REGRAS if any(c in baixa for c in chaves)), "Regras gerais")
        s.check(True, obtido="ok", aba="Banco de Dados", modulo=f"Regras · {mod}", tela="Postgres 17.10 + PostGIS local",
                tipo="Teste automatizado · regra de negócio", cenario=msg.strip(), precondicoes="Banco limpo com as 7 migrações aplicadas",
                passos="python scripts/supabase/testar_banco_local.py (supabase/tests/regras_test.sql)", entrada="-",
                esperado="ok", severidade=ALTA, evidencia=ev)
    falha = re.search(r"FALHOU: (.*)", saida)
    if falha or r.returncode:
        s.add(status="FAIL", obtido=(falha.group(1) if falha else saida[-500:]), aba="Banco de Dados", modulo="Regras",
              tela="Postgres local", tipo="Teste automatizado · regra de negócio", cenario="Primeira verificação que falhou",
              precondicoes="-", passos="testar_banco_local.py", entrada="-", esperado="ok", severidade=CRITICA, evidencia=ev,
              obs="As verificações seguintes do arquivo não rodam depois da primeira falha.")
    print(f"regras do banco: {len(casos)} verificações")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    EVIDENCIAS.mkdir(parents=True, exist_ok=True)
    s = Suite("automatizados", "A")
    for f in (analise_estatica, flutter_testes, deno_testes, python_testes, regras_banco):
        print(f"\n== {f.__name__}")
        try:
            f(s)
        except Exception as e:  # noqa: BLE001
            s.add(status="BLOCKED", obtido=f"{type(e).__name__}: {e}", aba="Regressão", modulo="Execução", tela=f.__name__,
                  tipo="Execução", cenario=f"Suíte {f.__name__}", precondicoes="-", passos="-", entrada="-",
                  esperado="Suíte executada", severidade=MEDIA)
    s.salvar()
    return 0


if __name__ == "__main__":
    sys.exit(main())
