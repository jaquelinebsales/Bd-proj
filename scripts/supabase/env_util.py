"""
Leitura e verificação do arquivo .env do gasprice.

Regra do módulo: nunca exibir valores. Só diz se cada chave está vazia, com o texto de
exemplo ou preenchida, e mascara qualquer segredo que apareça numa mensagem de erro.
"""
from __future__ import annotations

import json
import re
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit

RAIZ = Path(__file__).resolve().parents[2]
ARQUIVO_ENV = RAIZ / ".env"
API_SUPABASE = "https://api.supabase.com"

# Textos de exemplo do .env.example. Um valor real não termina em "..." nem contém estes trechos.
_EXEMPLO = re.compile(r"SEU-PROJETO|SEU_PROJECT|COLE_AQUI|SENHA-DO-BANCO|\[YOUR-PASSWORD\]|REGIAO|\.\.\.$", re.IGNORECASE)
# Senhas escolhidas pelo usuário podem terminar em "..." ou ter qualquer caractere: sem detecção de exemplo.
_SEM_DETECCAO_DE_EXEMPLO = {"SUPABASE_DB_PASSWORD", "CRON_SECRET"}

SEGREDOS = (
    "SUPABASE_SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_DB_PASSWORD",
    "DATABASE_URL", "SUPABASE_ACCESS_TOKEN", "CRON_SECRET", "GITHUB_TOKEN",
)


class ErroEnv(Exception):
    """Problema de configuração, com mensagem pronta para o usuário."""


def carregar_env(caminho: Path | None = None) -> dict[str, str]:
    arq = caminho or ARQUIVO_ENV
    if not arq.exists():
        raise ErroEnv("Arquivo .env não encontrado na raiz do projeto. Copie .env.example para .env, preencha e salve.")
    env: dict[str, str] = {}
    for linha in arq.read_text(encoding="utf-8-sig").splitlines():
        t = linha.strip()
        if not t or t.startswith("#") or "=" not in t:
            continue
        chave, valor = t.split("=", 1)
        valor = valor.strip()
        if len(valor) >= 2 and valor[0] == valor[-1] and valor[0] in "\"'":
            valor = valor[1:-1]
        env[chave.strip()] = valor
    return env


def estado(chave: str, valor: str | None) -> str:
    """'vazio', 'exemplo' (texto do .env.example ainda não trocado) ou 'preenchido'."""
    v = (valor or "").strip()
    if not v:
        return "vazio"
    if chave in _SEM_DETECCAO_DE_EXEMPLO:
        return "preenchido"
    return "exemplo" if _EXEMPLO.search(v) else "preenchido"


def preenchido(env: dict[str, str], chave: str) -> bool:
    return estado(chave, env.get(chave)) == "preenchido"


def ref_do_projeto(env: dict[str, str]) -> str | None:
    """Referência do projeto: do SUPABASE_PROJECT_REF ou do começo da SUPABASE_URL."""
    if preenchido(env, "SUPABASE_PROJECT_REF"):
        return env["SUPABASE_PROJECT_REF"].strip()
    if preenchido(env, "SUPABASE_URL"):
        host = urlsplit(env["SUPABASE_URL"].strip()).hostname or ""
        m = re.fullmatch(r"([a-z]{20})\.supabase\.(?:co|red)", host)
        if m:
            return m.group(1)
    return None


def interpretar_url_banco(url: str) -> dict[str, str]:
    """Separa usuário, senha, host, porta e banco. Levanta ErroEnv se a URL não servir."""
    m = re.fullmatch(r"postgres(?:ql)?://([^:@/]+):(.*)@([^@/:]+)(?::(\d+))?/([^?#]+)(?:\?.*)?", url.strip())
    if not m:
        raise ErroEnv("A DATABASE_URL não está no formato postgresql://usuario:senha@host:5432/postgres.")
    usuario, senha, host, porta, banco = m.groups()
    if re.search(r"[/?#\[\]]", senha) or re.search(r"%(?![0-9A-Fa-f]{2})", senha):
        raise ErroEnv(
            "A senha dentro da DATABASE_URL tem caracteres especiais que quebram a leitura da URL. "
            "Apague a DATABASE_URL, preencha só SUPABASE_DB_PASSWORD e o script monta a string certa."
        )
    return {"usuario": unquote(usuario), "senha": unquote(senha), "host": host, "porta": porta or "5432", "banco": banco}


def consultar_pooler(ref: str, token: str, abrir=urllib.request.urlopen) -> list[dict]:
    """Pergunta à API do Supabase o endereço do pooler do banco (não precisa da senha)."""
    req = urllib.request.Request(
        f"{API_SUPABASE}/v1/projects/{ref}/config/database/pooler",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/json", "User-Agent": "gasprice-scripts/1.0"},
    )
    try:
        with abrir(req, timeout=30) as r:
            return json.loads(r.read() or b"[]")
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise ErroEnv("O token de acesso (SUPABASE_ACCESS_TOKEN) foi recusado. Gere outro em supabase.com/dashboard/account/tokens.")
        if e.code in (403, 404):
            raise ErroEnv("O token não tem acesso a este projeto. Confira se ele é da mesma conta que criou o projeto.")
        raise ErroEnv(f"A API do Supabase respondeu {e.code}.")
    except (urllib.error.URLError, TimeoutError, OSError):
        raise ErroEnv("Sem conexão com a API do Supabase (api.supabase.com).")


def resolver_database_url(env: dict[str, str], consultar=consultar_pooler) -> tuple[str, str]:
    """
    Devolve (url, origem). Usa a DATABASE_URL do .env quando ela está preenchida. Senão monta
    a URL do Session pooler com a senha do banco e o endereço que a API do Supabase informa.
    """
    if preenchido(env, "DATABASE_URL"):
        interpretar_url_banco(env["DATABASE_URL"])
        return env["DATABASE_URL"].strip(), "DATABASE_URL do .env"

    faltando = []
    senha = env.get("SUPABASE_DB_PASSWORD", "").strip()
    token = env.get("SUPABASE_ACCESS_TOKEN", "").strip()
    ref = ref_do_projeto(env)
    if not senha:
        faltando.append("SUPABASE_DB_PASSWORD")
    if not preenchido(env, "SUPABASE_ACCESS_TOKEN"):
        faltando.append("SUPABASE_ACCESS_TOKEN")
    if not ref:
        faltando.append("SUPABASE_URL")
    if faltando:
        raise ErroEnv("Sem a DATABASE_URL, preciso de: " + ", ".join(faltando) + ".")

    itens = consultar(ref, token)
    principal = next((i for i in itens if i.get("database_type") == "PRIMARY"), itens[0] if itens else None)
    if not principal or not principal.get("db_host") or not principal.get("db_user"):
        raise ErroEnv("A API do Supabase não devolveu o endereço do banco deste projeto.")
    banco = principal.get("db_name") or "postgres"
    url = f"postgresql://{quote(principal['db_user'], safe='.')}:{quote(senha, safe='')}@{principal['db_host']}:5432/{banco}"
    return url, "montada com o endereço informado pela API do Supabase"


def mascarar(texto: str, env: dict[str, str]) -> str:
    """Troca qualquer segredo do .env que apareça no texto por ***."""
    candidatos: set[str] = set()
    for k in SEGREDOS:
        v = (env.get(k) or "").strip()
        if len(v) >= 6:
            candidatos.update({v, quote(v, safe="")})
    if preenchido(env, "DATABASE_URL"):
        try:
            senha = interpretar_url_banco(env["DATABASE_URL"])["senha"]
            if len(senha) >= 4:
                candidatos.update({senha, quote(senha, safe="")})
        except ErroEnv:
            pass
    for c in sorted(candidatos, key=len, reverse=True):
        texto = texto.replace(c, "***")
    return texto
