"""
Gera documentacao/andamento.html: página de acompanhamento com as capturas reais das telas
(documentacao/telas/*.webp, embutidas na página) e a lista de etapas.

Uso: python scripts/docs/gerar_andamento.py
"""
from __future__ import annotations

import base64
import html
import re
import subprocess
from datetime import date
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
e = html.escape

OK, ESPERA, PROX = ("ok", "Concluído"), ("espera", "Aguardando você"), ("prox", "Próximo")
ETAPAS = [
    ("Fase 1 · Dados da ANP", [
        ("Limpeza das planilhas: 5,46 milhões de preços, anomalias marcadas e nunca apagadas", OK),
        ("Estudo de cobertura: onde a ANP não pesquisa preços", OK),
        ("Experimento do modelo de previsão com janelas de 2, 4 e 6 anos", OK),
    ]),
    ("Fase 2 · Backend Supabase", [
        ("Esquema com 19 tabelas, PostGIS e busca sem acento", OK),
        ("Regras de acesso: consulta pública, alteração só com login", OK),
        ("Consenso, revisão, pontos, bloqueio, avisos e estimativas", OK),
        ("Edge Functions: envio de preços, sincronização com a ANP e exclusão de conta", OK),
        ("Importador dos dados da ANP para o plano gratuito", OK),
        ("Testes das regras num Postgres 17 com PostGIS", OK),
        ("Rotinas pesadas medidas com 45 mil postos e 954 mil preços: de 2 s a 18 s; banco em cerca de 260 MB dos 500 MB", OK),
        ("Aplicado no seu projeto Supabase, com 45.823 postos, 1,65 milhão de preços e 135 mil estimativas", OK),
        ("Consulta pública e bloqueios conferidos no projeto real: 16 de 16 verificações", OK),
    ]),
    ("Fase 3 · App Flutter", [
        ("21 telas com layout para celular e tablet", OK),
        ("Cadastro, login, confirmação de e-mail e recuperação de senha", OK),
        ("Leitura do painel no aparelho, com a foto apagada em seguida", OK),
        ("Filtros, ordenação e cache no aparelho", OK),
        ("Avisos de preço em tempo real para favoritos", OK),
        ("Modo de demonstração com dados de exemplo", OK),
        ("Rodar em aparelho Android e iOS", ESPERA),
        ("Ajustar o leitor com fotos reais de painéis", PROX),
    ]),
    ("Fase 4 · Publicação", [
        ("Repositório Git local com o primeiro commit", OK),
        ("Testes automáticos no GitHub Actions", OK),
        ("Publicação automática do banco e das funções", OK),
        ("Verificador do .env e publicação com um comando, sem copiar a string de conexão", OK),
        ("Geração do APK pelo GitHub Actions", OK),
        ("Enviar o código ao seu GitHub e cadastrar os segredos", ESPERA),
    ]),
    ("Fase 5 · Evolução", [
        ("Carga automática das semanas novas da pesquisa da ANP", PROX),
        ("Geocodificar os 6.942 postos ativos sem coordenada", PROX),
        ("Avisos com o app fechado, via Firebase", PROX),
        ("Previsão de preço no app, quando o modelo superar a regra simples", PROX),
        ("SMTP próprio para os e-mails de cadastro", PROX),
        ("Publicação na Play Store e na App Store", PROX),
        ("Painel de moderação de envios e contas", PROX),
    ]),
]


def etapas() -> str:
    partes = []
    for fase, itens in ETAPAS:
        linhas = "".join(
            f'<tr><td>{e(t)}</td><td class="e"><span class="estado {c}">{e(r)}</span></td></tr>' for t, (c, r) in itens)
        partes.append(f'<h3>{e(fase)}</h3><div class="tabela"><table><thead><tr><th>Etapa</th><th>Situação</th></tr></thead>'
                      f'<tbody>{linhas}</tbody></table></div>')
    return '<div style="display: grid; gap: 14px">' + "".join(partes) + "</div>"


def imagem(m: re.Match) -> str:
    arq = RAIZ / "documentacao" / "telas" / f"{m.group(1)}.webp"
    return "data:image/webp;base64," + base64.b64encode(arq.read_bytes()).decode()


def main() -> None:
    tpl = (RAIZ / "scripts" / "docs" / "andamento_template.html").read_text(encoding="utf-8")
    try:
        commit = subprocess.run(["git", "-C", str(RAIZ), "rev-parse", "--short", "HEAD"],
                                capture_output=True, text=True, timeout=30).stdout.strip() or "sem commit"
    except (OSError, subprocess.SubprocessError):
        commit = "sem commit"
    saida = re.sub(r"\{\{IMG:([\w-]+)\}\}", imagem, tpl)
    saida = (saida.replace("{{ETAPAS}}", etapas()).replace("{{DATA}}", date.today().strftime("%d/%m/%Y"))
             .replace("{{COMMIT}}", commit))
    destino = RAIZ / "documentacao" / "andamento.html"
    destino.write_text(saida, encoding="utf-8")
    print(f"{destino} gerado ({destino.stat().st_size / 1024:.0f} KB), commit {commit}")


if __name__ == "__main__":
    main()
