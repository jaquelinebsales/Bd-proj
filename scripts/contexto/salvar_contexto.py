"""
Salva a conversa com o Claude Code na pasta contexto/ antes de cada compactação.

Chamado pelo gancho PreCompact (.claude/settings.local.json), que envia um JSON pela entrada padrão
com transcript_path, session_id e trigger. Também pode ser rodado à mão:
  python scripts/contexto/salvar_contexto.py --transcript CAMINHO.jsonl

Gera contexto/AAAA-MM-DD_HHMM_<gatilho>_<sessão>.md só com as mensagens de texto do usuário e do Claude.
Saídas de ferramentas ficam de fora: elas são grandes e podem conter dados que não devem ir para o Git.
Usa só a biblioteca padrão do Python.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
DESTINO = RAIZ / "contexto"
LEMBRETES = re.compile(r"<system-reminder>.*?</system-reminder>|<local-command-[a-z]+>.*?</local-command-[a-z]+>"
                       r"|<command-[a-z]+>.*?</command-[a-z]+>|<ide_[a-z_]+>.*?</ide_[a-z_]+>", re.S)


def texto_da_mensagem(conteudo) -> str:
    if isinstance(conteudo, str):
        return conteudo
    partes = []
    for bloco in conteudo or []:
        if isinstance(bloco, dict) and bloco.get("type") == "text":
            partes.append(bloco.get("text", ""))
    return "\n\n".join(partes)


def converter(transcript: Path) -> tuple[str, int]:
    linhas, n = [], 0
    for bruta in transcript.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            item = json.loads(bruta)
        except ValueError:
            continue
        tipo = item.get("type")
        if tipo not in ("user", "assistant") or item.get("isMeta"):
            continue
        msg = item.get("message") or {}
        texto = LEMBRETES.sub("", texto_da_mensagem(msg.get("content"))).strip()
        if not texto:
            continue
        quando = (item.get("timestamp") or "")[:16].replace("T", " ")
        if item.get("isCompactSummary"):
            autor = "Resumo da compactação anterior"
        else:
            autor = "Usuário" if tipo == "user" else "Claude"
        linhas.append(f"### {autor} · {quando}\n\n{texto}\n")
        n += 1
    return "\n".join(linhas), n


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--transcript")
    ap.add_argument("--gatilho", default="manual")
    args = ap.parse_args()

    dados = {}
    if not args.transcript and sys.stdin is not None and not sys.stdin.isatty():
        try:
            bruto = sys.stdin.buffer.read().decode("utf-8-sig", errors="replace").strip().lstrip("﻿")
            dados = json.loads(bruto or "{}")
        except ValueError:
            dados = {}
    caminho = args.transcript or dados.get("transcript_path")
    if not caminho or not Path(caminho).exists():
        print("salvar_contexto: transcrição não encontrada", file=sys.stderr)
        return 0   # nunca bloqueia a compactação
    gatilho = dados.get("trigger") or args.gatilho
    sessao = (dados.get("session_id") or Path(caminho).stem)[:8]

    corpo, n = converter(Path(caminho))
    DESTINO.mkdir(exist_ok=True)
    agora = datetime.now()
    arquivo = DESTINO / f"{agora:%Y-%m-%d_%H%M}_{gatilho}_{sessao}.md"
    cabecalho = (f"# Conversa salva antes da compactação\n\n"
                 f"- Sessão: `{sessao}`\n- Gatilho: {gatilho}\n- Salva em: {agora:%d/%m/%Y %H:%M}\n"
                 f"- Mensagens: {n}\n\n"
                 "Só as mensagens de texto. As saídas de ferramentas e as chaves ficam de fora.\n\n---\n\n")
    arquivo.write_text(cabecalho + corpo, encoding="utf-8")
    print(json.dumps({"systemMessage": f"Conversa salva em contexto/{arquivo.name} ({n} mensagens)"}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
