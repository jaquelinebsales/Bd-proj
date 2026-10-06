"""
Base da auditoria: leitura do .env, chamadas HTTP ao Supabase e registro de cada teste.

Cada teste executado vira um registro em documentacao/auditoria/resultados/<suite>.json.
A planilha (gerar_planilha.py) é montada só a partir desses registros: nada é escrito à mão
como resultado. Testes que não puderam rodar entram como NOT TESTED ou BLOCKED, com o motivo.

Nenhum segredo é gravado nos registros: as respostas passam pela máscara do env_util.
"""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from urllib.parse import quote

RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(RAIZ / "scripts" / "supabase"))
import env_util as eu  # noqa: E402

SAIDA = RAIZ / "documentacao" / "auditoria"
RESULTADOS = SAIDA / "resultados"
EVIDENCIAS = SAIDA / "evidencias"

PASS, FAIL, BLOCKED, NOT_TESTED = "PASS", "FAIL", "BLOCKED", "NOT TESTED"
CRITICA, ALTA, MEDIA, BAIXA = "Crítica", "Alta", "Média", "Baixa"

ENV = eu.carregar_env()
URL = ENV["SUPABASE_URL"].strip().rstrip("/")
PUB = ENV["SUPABASE_PUBLISHABLE_KEY"].strip()
SECRETA = ENV.get("SUPABASE_SECRET_KEY", "").strip()


def mascarar(texto: str) -> str:
    t = eu.mascarar(str(texto), ENV)
    for v in (PUB, SECRETA):
        if v:
            t = t.replace(v, "***")
    return TOKEN.sub("eyJ…(token omitido)", t)


import re  # noqa: E402

TOKEN = re.compile(r"eyJ[\w-]{6,}(?:\.[\w-]*){0,2}")


@dataclass
class Teste:
    id: str
    aba: str
    modulo: str
    tela: str
    tipo: str
    cenario: str
    precondicoes: str
    passos: str
    entrada: str
    esperado: str
    obtido: str = ""
    status: str = NOT_TESTED
    severidade: str = MEDIA
    evidencia: str = ""
    bug: str = ""
    obs: str = ""
    duracao_ms: int | None = None
    executado_em: str = field(default_factory=lambda: datetime.now().isoformat(timespec="seconds"))


class Suite:
    """Acumula os testes de um arquivo e grava o JSON no fim (também se o script quebrar no meio)."""

    def __init__(self, nome: str, prefixo: str):
        self.nome, self.prefixo, self.testes, self._n = nome, prefixo, [], 0
        RESULTADOS.mkdir(parents=True, exist_ok=True)

    def novo_id(self) -> str:
        self._n += 1
        return f"{self.prefixo}-{self._n:03d}"

    def add(self, **kw) -> Teste:
        kw.setdefault("id", self.novo_id())
        t = Teste(**kw)
        t.obtido = mascarar(t.obtido)[:1500]
        t.entrada = mascarar(t.entrada)[:800]
        self.testes.append(t)
        marca = {"PASS": "ok    ", "FAIL": "FALHOU", "BLOCKED": "BLOQ  ", "NOT TESTED": "NÃO   "}[t.status]
        print(f"{marca} {t.id} {t.cenario[:110]}")
        return t

    def check(self, ok: bool, *, obtido: str, **kw) -> Teste:
        return self.add(status=PASS if ok else FAIL, obtido=obtido, **kw)

    def salvar(self) -> None:
        arq = RESULTADOS / f"{self.nome}.json"
        arq.write_text(json.dumps([asdict(t) for t in self.testes], ensure_ascii=False, indent=1), encoding="utf-8")
        falhas = sum(t.status == FAIL for t in self.testes)
        print(f"\n{self.nome}: {len(self.testes)} testes, {falhas} falhas -> {arq}")


# ------------------------------------------------------------------ HTTP
@dataclass
class Resp:
    status: int
    corpo: object
    texto: str
    ms: int
    cabecalhos: dict


def http(metodo: str, caminho: str, corpo=None, *, token: str | None = None, chave: str | None = None,
         cabecalhos: dict | None = None, timeout: int = 60, bruto: bytes | None = None) -> Resp:
    """Chamada ao projeto. chave = apikey (padrão: publicável). token = JWT do usuário (Authorization)."""
    ch = chave or PUB
    cab = {"apikey": ch, "Content-Type": "application/json", "User-Agent": "gasprice-auditoria/1.0"}
    if token:
        cab["Authorization"] = f"Bearer {token}"
    elif ch.startswith("eyJ"):
        cab["Authorization"] = f"Bearer {ch}"
    cab.update(cabecalhos or {})
    dados = bruto if bruto is not None else (None if corpo is None else json.dumps(corpo).encode())
    req = urllib.request.Request(URL + caminho, method=metodo, headers=cab, data=dados)
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            texto = r.read().decode("utf-8", "replace")
            st, hd = r.status, dict(r.headers)
    except urllib.error.HTTPError as e:
        texto = e.read().decode("utf-8", "replace")
        st, hd = e.code, dict(e.headers)
    except Exception as e:  # noqa: BLE001  (rede, timeout)
        return Resp(0, None, f"{type(e).__name__}: {e}", int((time.perf_counter() - t0) * 1000), {})
    ms = int((time.perf_counter() - t0) * 1000)
    try:
        corpo_json = json.loads(texto) if texto else None
    except ValueError:
        corpo_json = None
    return Resp(st, corpo_json, texto, ms, hd)


def resumo(r: Resp, n: int = 300) -> str:
    return f"HTTP {r.status} em {r.ms} ms: {mascarar(r.texto)[:n]}"


# ------------------------------------------------------------------ banco (somente leitura, pelo pooler)
def conectar_banco():
    """Conexão com o Postgres do projeto pelo Session pooler. Usada só para consultas de leitura e para limpar
    os dados criados pela própria auditoria."""
    import psycopg
    ref = eu.ref_do_projeto(ENV)
    senha = quote(ENV["SUPABASE_DB_PASSWORD"], safe="")
    ultimo = None
    for host in ("aws-0-us-west-2.pooler.supabase.com", "aws-1-us-west-2.pooler.supabase.com"):
        try:
            return psycopg.connect(f"postgresql://postgres.{ref}:{senha}@{host}:5432/postgres", connect_timeout=15,
                                   autocommit=True)
        except Exception as e:  # noqa: BLE001
            ultimo = e
    raise RuntimeError(mascarar(str(ultimo)))
