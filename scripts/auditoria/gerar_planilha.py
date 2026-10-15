"""
Monta documentacao/auditoria/auditoria_gasprice.xlsx a partir dos resultados gravados pelos testes
(documentacao/auditoria/resultados/*.json). Nenhum resultado é escrito à mão: a planilha só organiza.

Abas: Dashboard, uma por área de teste, Android (manual) e Bugs encontrados.
O Dashboard usa fórmulas (CONT.SE) sobre as abas; o Excel recalcula ao abrir.

Uso: python scripts/auditoria/gerar_planilha.py
"""
from __future__ import annotations

import json
import re
import subprocess
from collections import Counter
from datetime import date
from pathlib import Path

from openpyxl import Workbook
from openpyxl.chart import BarChart, Reference
from openpyxl.formatting.rule import CellIsRule, DataBarRule, FormulaRule
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.table import Table, TableStyleInfo

RAIZ = Path(__file__).resolve().parents[2]
PASTA = RAIZ / "documentacao" / "auditoria"
# Retrato da auditoria de 06/10/2026, antes das correções (arquivos *_antes). O reteste depois das correções
# está em remoto.json, automatizados.json e telas.json e aparece no Dashboard e na aba Bugs encontrados.
SUITES = ["remoto_antes", "automatizados_antes", "telas_antes", "e2e", "android", "android_emulador"]
# Suítes novas: uma falha ainda sem bug catalogado entra na planilha marcada "a triar" em vez de travar a geração
SUITES_A_TRIAR = {"android_emulador"}
RETESTE = {"remoto": "Supabase real", "automatizados": "Testes locais (banco, app, funções, scripts)", "telas": "Telas em 7 tamanhos e fontes"}
# Testes que mudaram de nome no reteste porque a checagem ficou mais precisa
RENOMEADOS = {
    "Coordenadas caem perto da UF cadastrada (menos de 1.000 km do centro dos postos da UF)":
        "Coordenadas da ANP caem dentro do contorno do próprio estado (malha do IBGE, 15 km de tolerância)",
}
TOKEN = re.compile(r"eyJ[\w-]{6,}(?:\.[\w-]*){0,2}")  # trechos de tokens de sessão dos usuários de teste

# aba do registro -> (nome da aba no Excel, prefixo do ID). O Excel não aceita "/" em nome de aba.
ABAS = {
    "Funcionais": ("Testes Funcionais", "FUN"),
    "UI/Telas": ("UI-Telas", "UI"),
    "Autenticação": ("Autenticação", "AUT"),
    "Backend/API": ("Backend-API", "API"),
    "Banco de Dados": ("Banco de Dados", "BD"),
    "Edge Functions": ("Edge Functions", "EF"),
    "Segurança": ("Segurança", "SEG"),
    "Integração": ("Integração", "INT"),
    "Performance": ("Performance", "PERF"),
    "Regressão": ("Regressão", "REG"),
    "Android (manual)": ("Android (manual)", "AND"),
    "Android (emulador)": ("Android (emulador)", "EMU"),
}
STATUS = {"PASS": "🟢 PASS", "FAIL": "🔴 FAIL", "BLOCKED": "🟡 BLOCKED", "NOT TESTED": "⚪ NOT TESTED"}
COLUNAS = ["ID", "Módulo", "Tela/Componente", "Tipo de Teste", "Cenário", "Pré-condições", "Passos", "Dados de Entrada",
           "Resultado Esperado", "Resultado Obtido", "Status", "Severidade", "Evidência", "Bug/Issue", "Observações"]
LARGURAS = [10, 20, 24, 22, 46, 30, 38, 26, 36, 52, 15, 11, 26, 11, 40]

# ------------------------------------------------------------------ bugs
# Cada bug lista padrões (regex) do cenário dos testes que o comprovam. Toda falha precisa cair em um bug.
BUGS = [
    dict(id="BUG-01", sev="Alta", modulo="Envio de preços (Edge Function enviar-precos)",
         titulo="Envios simultâneos furam a regra de 6 horas e multiplicam pontos e confiabilidade",
         descricao="A função confere o limite de 6 h e o limite diário e só depois grava, sem trava nem transação. "
                   "Requisições iguais disparadas juntas passam todas. Quando o consenso se forma, cada item duplicado "
                   "ganha pontos e confiabilidade.",
         impacto="Um usuário mal-intencionado ganha dezenas de pontos e sobe a confiabilidade com uma única ação, "
                 "contornando o teto pensado para a regra. Distorce ranking e o peso das contribuições.",
         reproduzir="Disparar 6 POST iguais em enviar-precos ao mesmo tempo; outro usuário confirma o mesmo preço.",
         correcao="Mover a checagem e a gravação para uma função SQL única com pg_advisory_xact_lock(usuario, posto, produto) "
                  "ou índice único parcial; e dar pontos uma vez por usuário por consenso, não por item.",
         padroes=[r"envios simultâneos do mesmo item", r"duplicados por concorrência"]),
    dict(id="BUG-02", sev="Alta", modulo="Importação do cadastro da ANP",
         titulo="Coordenada padrão da API da ANP gravada como posição exata",
         descricao="Mais de 140 postos ativos de 21 UFs estão no mesmo ponto (-22,7780; -43,3371, Rio de Janeiro), e há "
                   "postos a mais de 1.000 km da própria UF. O importador aceita esses valores como posição exata.",
         impacto="Esses postos aparecem no lugar errado do mapa, recebem estimativa calculada com vizinhos errados, e o "
                 "envio de preço fica liberado para quem está no Rio e bloqueado para quem está no posto de verdade.",
         reproduzir="Ver os testes de integridade da aba Banco de Dados (coordenada repetida entre UFs e distância da UF).",
         correcao="No importar_postos_anp, tratar como sem coordenada (precisao 'nenhuma') ponto repetido entre UFs e ponto "
                  "fora do município pela malha do IBGE; corrigir os postos atuais com a mesma regra.",
         padroes=[r"compartilhada por postos de UFs", r"Coordenadas caem perto da UF"]),
    dict(id="BUG-03", sev="Alta", modulo="Dados da ANP",
         titulo="Preços oficiais da ANP desatualizados (última coleta em 30/06/2026)",
         descricao="A pesquisa semanal da ANP só entra no banco quando alguém recarrega a planilha. Não há carga automática.",
         impacto="Todo preço oficial aparece com mais de 3 meses (ponto vermelho), as estimativas usam preços velhos e a "
                 "ANP perde o papel de desempate.",
         reproduzir="select max(data_coleta) from precos_anp",
         correcao="Agendar a carga semanal da pesquisa da ANP (Edge Function ou GitHub Actions) e recalcular os preços.",
         padroes=[r"Pesquisa da ANP no banco está atualizada"]),
    dict(id="BUG-04", sev="Média", modulo="Autenticação (Supabase Auth)",
         titulo="Política de senha existe só na tela do app",
         descricao="O app exige 8 caracteres com letras e números, mas o servidor aceita 'abc123' e 'abcdefgh'.",
         impacto="Qualquer chamada direta à API (ou outro cliente) cria contas com senha fraca.",
         reproduzir="PUT /auth/v1/user {password: 'abc123'} com um token válido.",
         correcao="No painel do Supabase: Authentication → Policies → tamanho mínimo 8 e exigir letras e números.",
         padroes=[r"Servidor recusa senha com"]),
    dict(id="BUG-05", sev="Média", modulo="Banco · privacidade (RLS)",
         titulo="Identificador de quem avaliou e de quem votou é público",
         descricao="As tabelas avaliacoes e avaliacao_votos liberam todas as colunas para leitura pública, inclusive "
                   "usuario_id. O app não precisa disso: usa a função avaliacoes_posto, que abrevia o nome.",
         impacto="Qualquer pessoa liga avaliações e votos de um mesmo usuário e monta o histórico dele.",
         reproduzir="GET /rest/v1/avaliacoes?select=usuario_id com a chave publicável.",
         correcao="Revogar SELECT de usuario_id para anon e authenticated (permissão por coluna) ou expor só via função/visão.",
         padroes=[r"identificador \(UUID\) de quem avaliou", r"quem votou em cada avaliação"]),
    dict(id="BUG-06", sev="Média", modulo="App · layout",
         titulo="Estouro de layout em celular pequeno (320×568) e com fonte de 130%",
         descricao="Favoritos estoura 96 px embaixo e Avaliar 20 px à direita em 320×568; Busca estoura com fonte 130% em 360×800.",
         impacto="Faixas amarelas e pretas de erro e conteúdo cortado em celulares pequenos e para quem aumenta a fonte.",
         reproduzir="flutter test test_auditoria --dart-define=DEMO=true; ver as imagens em evidencias/telas.",
         correcao="Usar rolagem (SingleChildScrollView/ListView) e Flexible/Wrap nas linhas afetadas.",
         padroes=[r"em Celular pequeno 320×568", r"com fonte 130%"]),
    dict(id="BUG-07", sev="Baixa", modulo="App · acessibilidade",
         titulo="Estouro de layout com fonte do sistema em 200%",
         descricao="Mapa, Busca, Favoritos, Boas-vindas, Histórico, Entrar e Posto com estimativa estouram com fonte 200%.",
         impacto="Pessoas com baixa visão que usam a fonte máxima do Android veem conteúdo cortado.",
         reproduzir="Mesmo teste de telas, tamanho 'Celular 360×800 com fonte 200%'.",
         correcao="Permitir quebra de linha nos chips e botões, rolagem nas telas fixas e limitar a escala só onde for indispensável.",
         padroes=[r"com fonte 200%"]),
    dict(id="BUG-08", sev="Baixa", modulo="Regras · servidor",
         titulo="Autora consegue votar na própria avaliação pela API",
         descricao="A regra existe só no app (o botão some). A política de inserção em avaliacao_votos não impede.",
         impacto="Usuário infla o contador de 'útil' da própria avaliação chamando a API.",
         reproduzir="POST /rest/v1/avaliacao_votos com o id da própria avaliação.",
         correcao="Na política 'vota', acrescentar: not exists (select 1 from avaliacoes a where a.id = avaliacao_id and a.usuario_id = auth.uid()).",
         padroes=[r"votar na própria avaliação"]),
    dict(id="BUG-09", sev="Baixa", modulo="Documentação das regras",
         titulo="Regra do catálogo contradiz a ordem de prioridade do preço exibido",
         descricao="O catálogo diz que o envio nunca altera o preço exibido; a ordem de prioridade (item 2) e o código mostram "
                   "o envio recente como 'aguardando confirmação'.",
         impacto="Quem lê as regras espera um comportamento diferente do app.",
         reproduzir="Comparar a RN do envio por foto com o item 2 da ordem de prioridade.",
         correcao="Reescrever a RN: 'O envio aparece como aguardando confirmação e só vira preço confirmado com o consenso.'",
         padroes=[r"Texto da regra bate"]),
    dict(id="BUG-10", sev="Baixa", modulo="Infraestrutura · desempenho",
         titulo="Latência alta e picos de resposta (projeto em us-west-2, usuários no Brasil)",
         descricao="Cada chamada leva de 0,4 a 0,8 s só de ida e volta; há picos acima de 1,5 s e, sob carga, de vários segundos. "
                   "Consultas com parâmetros extremos chegam perto do limite de 3 s do Supabase para visitantes.",
         impacto="Mapa e busca mais lentos que o necessário; em horários de pico, respostas de vários segundos.",
         reproduzir="Ver a aba Performance.",
         correcao="Criar o projeto em sa-east-1 (São Paulo) antes do lançamento; limitar raio e quantidade nas funções públicas.",
         padroes=[r"chamadas seguidas", r"requisições simultâneas", r"Latitude impossível", r"responde a 5 chamadas"]),
    dict(id="BUG-11", sev="Média", modulo="Cobertura de preços",
         titulo="Combustível sem preço exibido embora haja referência a até 200 km",
         descricao="A regra da estimativa diz que esses postos deveriam ter preço estimado.",
         impacto="Posto aparece sem preço para aquele combustível.",
         reproduzir="Teste de integridade 'Combustível vendido por posto com coordenada, sem preço exibido...'.",
         correcao="Rodar recalcular_estimativas depois de cada sincronização do cadastro (hoje só às segundas).",
         padroes=[r"Combustível vendido por posto com coordenada"]),
]


# Situação da correção de cada bug (atualizar aqui quando mudar)
SITUACAO = {
    "BUG-01": "Corrigido e no ar (função registrar_envio com trava por usuário; pontos uma vez por pessoa).",
    "BUG-02": "Corrigido e no ar (contorno dos estados do IBGE e pontos padrão; 184 postos corrigidos).",
    "BUG-03": "Corrigido e no ar: 14 semanas carregadas (coleta até 02/10/2026); carga semanal no GitHub Actions.",
    "BUG-04": "Aguardando você: política de senha no painel do Supabase (8 caracteres, com maiúscula, minúscula, número e símbolo).",
    "BUG-05": "Corrigido e no ar (coluna de autor fora da leitura pública; cada um vê só os próprios votos).",
    "BUG-06": "Corrigido e verificado: 304 testes de telas passando. Chega ao celular no próximo APK.",
    "BUG-07": "Corrigido e verificado: 304 testes de telas passando. Chega ao celular no próximo APK.",
    "BUG-08": "Corrigido e no ar (política de voto do banco).",
    "BUG-09": "Corrigido: catálogo de regras reescrito e republicado.",
    "BUG-10": "Decisão sua: criar o projeto em sa-east-1 antes do lançamento.",
}
for _b in BUGS:
    _b["situacao"] = SITUACAO.get(_b["id"], "")


def carregar() -> list[dict]:
    testes = []
    for nome in SUITES:
        arq = PASTA / "resultados" / f"{nome}.json"
        if not arq.exists():
            continue
        dados = json.loads(arq.read_text(encoding="utf-8"))
        for t in dados:
            for campo in ("obtido", "entrada"):
                t[campo] = TOKEN.sub("eyJ…(token omitido)", t[campo] or "")
        arq.write_text(json.dumps(dados, ensure_ascii=False, indent=1), encoding="utf-8")
        for t in dados:
            t = dict(t)
            t["_suite"] = nome
            if nome == "telas_antes":
                t["evidencia"] = (t.get("evidencia") or "").replace("evidencias/telas/", "evidencias/telas_antes/")
            if not t.get("evidencia"):
                t["evidencia"] = {"remoto_antes": "resultados/remoto_antes.json", "e2e": "resultados/e2e.json"}.get(
                    nome, f"resultados/{nome}.json")
            testes.append(t)
    return testes


def carregar_reteste() -> tuple[dict[str, Counter], dict[str, str]]:
    """Contagem por suíte do reteste e o status de cada cenário depois das correções."""
    contagem, status = {}, {}
    for nome in RETESTE:
        arq = PASTA / "resultados" / f"{nome}.json"
        if not arq.exists():
            continue
        dados = json.loads(arq.read_text(encoding="utf-8"))
        contagem[nome] = Counter(t["status"] for t in dados)
        for t in dados:
            status[t["cenario"]] = t["status"]
    return contagem, status


def ligar_reteste(bugs_testes: dict[str, list[dict]], status: dict[str, str]) -> None:
    for b in BUGS:
        lista = bugs_testes.get(b["id"], [])
        achados = [status.get(RENOMEADOS.get(t["cenario"], t["cenario"])) for t in lista]
        validos = [s for s in achados if s]
        if not validos:
            b["reteste"] = "Não retestado"
        else:
            ok = sum(s == "PASS" for s in validos)
            b["reteste"] = f"{ok} de {len(validos)} passaram no reteste" + ("" if ok == len(validos) else f"; {len(validos) - ok} ainda falha(m)")


def preservar_android(testes: list[dict], destino: Path) -> int:
    """Mantém o que a pessoa já preencheu na aba Android (manual): resultado obtido, status e evidência."""
    if not destino.exists():
        return 0
    from openpyxl import load_workbook
    try:
        ws = load_workbook(destino, read_only=True)["Android (manual)"]
    except (KeyError, OSError):
        return 0
    por_cenario = {}
    for linha in ws.iter_rows(min_row=5, values_only=True):
        if linha and linha[4]:
            por_cenario[linha[4]] = (linha[9], linha[10], linha[12])
    volta = {v: k for k, v in STATUS.items()}
    n = 0
    for t in testes:
        if t["aba"] != "Android (manual)" or t["cenario"] not in por_cenario:
            continue
        obtido, status, evidencia = por_cenario[t["cenario"]]
        if obtido or (status and volta.get(status, "NOT TESTED") != "NOT TESTED"):
            t["obtido"] = obtido or ""
            t["status"] = volta.get(status, t["status"])
            t["evidencia"] = evidencia or t["evidencia"]
            n += 1
    return n


def ligar_bugs(testes: list[dict]) -> list[str]:
    sem_bug = []
    for b in BUGS:
        b["testes"] = []
    for t in testes:
        if t["status"] != "FAIL":
            continue
        for b in BUGS:
            if any(re.search(p, t["cenario"], re.I) for p in b["padroes"]):
                t["bug"] = b["id"]
                break
        else:
            if t.get("_suite") in SUITES_A_TRIAR:
                t["obs"] = ("A triar: falha nova, ainda sem bug catalogado. " + (t.get("obs") or "")).strip()
                print(f"  a triar: {t['cenario']}")
            else:
                sem_bug.append(t["cenario"])
    return sem_bug


fino = Side(style="thin", color="D5DDD9")
BORDA = Border(left=fino, right=fino, top=fino, bottom=fino)
CAB_FILL = PatternFill("solid", fgColor="134E3A")
FONTE = "Arial"


def estilo_cabecalho(ws, linha: int, ncol: int) -> None:
    for c in range(1, ncol + 1):
        cel = ws.cell(row=linha, column=c)
        cel.font = Font(name=FONTE, bold=True, color="FFFFFF", size=10)
        cel.fill = CAB_FILL
        cel.alignment = Alignment(vertical="center", horizontal="center", wrap_text=True)
        cel.border = BORDA


def cores_status(ws, intervalo: str) -> None:
    for txt, cor, fonte in (("PASS", "DFF3E7", "1A6B3C"), ("FAIL", "FBE0DE", "A3231A"), ("BLOCKED", "FBF0CF", "8A6300"),
                            ("NOT TESTED", "ECEFF1", "56646E")):
        ws.conditional_formatting.add(intervalo, FormulaRule(formula=[f'ISNUMBER(SEARCH("{txt}",{intervalo.split(":")[0]}))'],
                                                             fill=PatternFill("solid", fgColor=cor), font=Font(name=FONTE, color=fonte, bold=True)))


def aba_testes(wb, nome: str, linhas: list[dict]) -> None:
    ws = wb.create_sheet(nome)
    manual = nome == "Android (manual)"
    topo = 4 if manual else 1
    if manual:
        ws["A1"] = "Testes para executar no Android Studio (emulador ou aparelho)"
        ws["A1"].font = Font(name=FONTE, size=13, bold=True, color="134E3A")
        ws["A2"] = ("Como preencher: rode o caso, escreva o que aconteceu em 'Resultado Obtido' (coluna J) e troque o Status "
                    "(coluna K) para 🟢 PASS, 🔴 FAIL ou 🟡 BLOCKED. As células a preencher estão em amarelo. O Dashboard se atualiza sozinho.")
        ws["A2"].font = Font(name=FONTE, size=9, color="435049")
        ws.merge_cells("A2:O2")
    for j, v in enumerate(COLUNAS, 1):
        ws.cell(row=topo, column=j, value=v)
    estilo_cabecalho(ws, topo, len(COLUNAS))
    for i, t in enumerate(linhas):
        valores = [t["_id"], t["modulo"], t["tela"], t["tipo"], t["cenario"], t["precondicoes"], t["passos"], t["entrada"],
                   t["esperado"], t["obtido"], STATUS[t["status"]], t["severidade"], t["evidencia"], t.get("bug") or "", t["obs"]]
        for j, v in enumerate(valores, 1):
            ws.cell(row=topo + 1 + i, column=j, value=v)
    for i, w in enumerate(LARGURAS, 1):
        ws.column_dimensions[get_column_letter(i)].width = w
    for row in ws.iter_rows(min_row=topo + 1, max_row=ws.max_row):
        for cel in row:
            cel.font = Font(name=FONTE, size=9)
            cel.alignment = Alignment(vertical="top", wrap_text=True)
            cel.border = BORDA
        ev = row[12]
        if ev.value and not str(ev.value).startswith("-"):
            ev.hyperlink = str(ev.value)
            ev.font = Font(name=FONTE, size=9, color="0F6A8C", underline="single")
        bug = row[13]
        if bug.value:
            bug.hyperlink = f"#'Bugs encontrados'!A{int(str(bug.value)[-2:]) + 1}"
            bug.font = Font(name=FONTE, size=9, color="A3231A", bold=True, underline="single")
    ws.freeze_panes = f"F{topo + 1}"
    ws.auto_filter.ref = f"A{topo}:{get_column_letter(len(COLUNAS))}{ws.max_row}"
    ws.row_dimensions[topo].height = 30
    if manual:
        for r in range(topo + 1, ws.max_row + 1):
            for col in ("J", "K"):
                ws[f"{col}{r}"].fill = PatternFill("solid", fgColor="FFF6CC")
        # Lista de status permitidos na coluna K
        from openpyxl.worksheet.datavalidation import DataValidation
        dv = DataValidation(type="list", formula1='"' + ",".join(STATUS.values()) + '"', allow_blank=False)
        ws.add_data_validation(dv)
        dv.add(f"K{topo + 1}:K{ws.max_row}")
    cores_status(ws, f"K{topo + 1}:K{ws.max_row}")


def aba_bugs(wb) -> None:
    ws = wb.create_sheet("Bugs encontrados")
    cab = ["ID", "Título", "Severidade", "Módulo", "Descrição", "Impacto", "Como reproduzir", "Correção sugerida",
           "Testes que falharam", "Prioridade", "Situação da correção", "Reteste depois da correção"]
    ws.append(cab)
    estilo_cabecalho(ws, 1, len(cab))
    for n, b in enumerate(BUGS, 1):
        b["prioridade"] = n
    for b in BUGS:
        ws.append([b["id"], b["titulo"], b["sev"], b["modulo"], b["descricao"], b["impacto"], b["reproduzir"], b["correcao"],
                   f"{len(b['testes'])}: " + ", ".join(b["testes"][:12]) + (" …" if len(b["testes"]) > 12 else ""), b["prioridade"], b["situacao"],
                   b.get("reteste", "Não retestado")])
    for i, w in enumerate([9, 40, 11, 24, 50, 44, 40, 50, 30, 10, 44, 30], 1):
        ws.column_dimensions[get_column_letter(i)].width = w
    for row in ws.iter_rows(min_row=2, max_row=ws.max_row):
        for cel in row:
            cel.font = Font(name=FONTE, size=9)
            cel.alignment = Alignment(vertical="top", wrap_text=True)
            cel.border = BORDA
        row[0].font = Font(name=FONTE, size=9, bold=True)
    for sev, cor in (("Crítica", "F4C7C3"), ("Alta", "FBE0DE"), ("Média", "FBF0CF"), ("Baixa", "ECEFF1")):
        ws.conditional_formatting.add(f"C2:C{ws.max_row}", CellIsRule(operator="equal", formula=[f'"{sev}"'],
                                                                     fill=PatternFill("solid", fgColor=cor)))
    ws.freeze_panes = "C2"
    ws.auto_filter.ref = f"A1:L{ws.max_row}"
    for r in range(2, ws.max_row + 1):
        cel = ws.cell(row=r, column=12)
        texto = str(cel.value or "")
        if texto.startswith(("Não", "0 de")) or "ainda falha" in texto:
            cel.fill = PatternFill("solid", fgColor="FBF0CF" if not texto.startswith("0 de") else "FBE0DE")
        else:
            cel.fill = PatternFill("solid", fgColor="DFF3E7")


def dashboard(wb, abas: list[str], commit: str, total_testes: int, reteste: dict | None = None) -> None:
    ws = wb["Dashboard"]
    ws.sheet_view.showGridLines = False
    ws["B2"] = "Auditoria do gasprice"
    ws["B2"].font = Font(name=FONTE, size=20, bold=True, color="134E3A")
    ws["B3"] = (f"Executada em {date.today():%d/%m/%Y} sobre o commit {commit}, contra o Supabase real (projeto gasprice), "
                "o Postgres local, o app em modo demonstração e o app web no Edge. Os resultados são os de antes das correções; "
                "a coluna 'Situação da correção' da aba Bugs encontrados mostra o que já foi corrigido.")
    ws["B3"].font = Font(name=FONTE, size=10, color="435049")

    # Tabela por módulo (base de tudo): fórmulas CONT.SE sobre cada aba
    lin0 = 14
    cab = ["Módulo (aba)", "Total", "🟢 PASS", "🔴 FAIL", "🟡 BLOCKED", "⚪ NOT TESTED", "% aprovação", "% executado"]
    for j, v in enumerate(cab):
        ws.cell(row=lin0, column=2 + j, value=v)
    estilo_cabecalho(ws, lin0, 9)
    ws.cell(row=lin0, column=1).fill = PatternFill(fill_type=None)
    for i, nome in enumerate(abas):
        r = lin0 + 1 + i
        q = f"'{nome}'"
        inicio = 5 if nome == "Android (manual)" else 2
        col = f"{q}!$K${inicio}:$K$5000"
        ws.cell(row=r, column=2, value=nome)
        ws.cell(row=r, column=3, value=f"=COUNTA({q}!$A${inicio}:$A$5000)")
        for k, st in enumerate(("PASS", "FAIL", "BLOCKED", "NOT TESTED")):
            ws.cell(row=r, column=4 + k, value=f'=COUNTIF({col},"*{st}")')
        ws.cell(row=r, column=8, value=f"=IFERROR(D{r}/(D{r}+E{r}),0)")
        ws.cell(row=r, column=9, value=f"=IFERROR((D{r}+E{r})/C{r},0)")
    rt = lin0 + 1 + len(abas)
    ws.cell(row=rt, column=2, value="Total")
    for c in range(3, 8):
        L = get_column_letter(c)
        ws.cell(row=rt, column=c, value=f"=SUM({L}{lin0 + 1}:{L}{rt - 1})")
    ws.cell(row=rt, column=8, value=f"=IFERROR(D{rt}/(D{rt}+E{rt}),0)")
    ws.cell(row=rt, column=9, value=f"=IFERROR((D{rt}+E{rt})/C{rt},0)")
    for r in range(lin0 + 1, rt + 1):
        for c in range(2, 10):
            cel = ws.cell(row=r, column=c)
            cel.font = Font(name=FONTE, size=10, bold=(r == rt))
            cel.border = BORDA
            if c >= 8:
                cel.number_format = "0.0%"
            elif c >= 3:
                cel.number_format = "#,##0"
                cel.alignment = Alignment(horizontal="center")
        if r == rt:
            for c in range(2, 10):
                ws.cell(row=r, column=c).fill = PatternFill("solid", fgColor="EAF1EE")
    ws.conditional_formatting.add(f"H{lin0 + 1}:H{rt - 1}", DataBarRule(start_type="num", start_value=0, end_type="num", end_value=1, color="2E9E63"))
    ws.conditional_formatting.add(f"I{lin0 + 1}:I{rt - 1}", DataBarRule(start_type="num", start_value=0, end_type="num", end_value=1, color="5B8DB8"))

    # Cartões de resumo, ligados à linha Total
    cartoes = [("Total de testes", f"=C{rt}", "#,##0", "134E3A"), ("🟢 PASS", f"=D{rt}", "#,##0", "1A6B3C"),
               ("🔴 FAIL", f"=E{rt}", "#,##0", "A3231A"), ("🟡 BLOCKED", f"=F{rt}", "#,##0", "8A6300"),
               ("⚪ NOT TESTED", f"=G{rt}", "#,##0", "56646E"), ("% aprovação (PASS ÷ executados)", f"=H{rt}", "0.0%", "1A6B3C"),
               ("% cobertura (executados ÷ total)", f"=I{rt}", "0.0%", "0F5A86")]
    for k, (rot, f, fmt, cor) in enumerate(cartoes):
        c = 2 + k
        ws.cell(row=5, column=c, value=rot).font = Font(name=FONTE, size=9, bold=True, color="435049")
        ws.cell(row=5, column=c).alignment = Alignment(wrap_text=True, vertical="bottom")
        v = ws.cell(row=6, column=c, value=f)
        v.font = Font(name=FONTE, size=22, bold=True, color=cor)
        v.number_format = fmt
        for r in (5, 6):
            ws.cell(row=r, column=c).fill = PatternFill("solid", fgColor="F2F6F4")
            ws.cell(row=r, column=c).border = BORDA
    ws.row_dimensions[5].height = 30
    ws.row_dimensions[6].height = 36

    # Bugs por severidade
    ws["B8"] = "Bugs por severidade"
    ws["B8"].font = Font(name=FONTE, size=12, bold=True, color="134E3A")
    for k, (sev, cor) in enumerate((("Crítica", "7A1810"), ("Alta", "A3231A"), ("Média", "8A6300"), ("Baixa", "56646E"))):
        c = 2 + k
        ws.cell(row=9, column=c, value=sev).font = Font(name=FONTE, size=9, bold=True, color="435049")
        cel = ws.cell(row=10, column=c, value=f"=COUNTIF('Bugs encontrados'!$C$2:$C$200,\"{sev}\")")
        cel.font = Font(name=FONTE, size=18, bold=True, color=cor)
        for r in (9, 10):
            ws.cell(row=r, column=c).fill = PatternFill("solid", fgColor="F2F6F4")
            ws.cell(row=r, column=c).border = BORDA
    ws.cell(row=9, column=6, value="Total de bugs").font = Font(name=FONTE, size=9, bold=True, color="435049")
    tb = ws.cell(row=10, column=6, value="=SUM(B10:E10)")
    tb.font = Font(name=FONTE, size=18, bold=True, color="134E3A")
    for r in (9, 10):
        ws.cell(row=r, column=6).fill = PatternFill("solid", fgColor="F2F6F4")
        ws.cell(row=r, column=6).border = BORDA
    ws["B12"] = "Progresso por módulo"
    ws["B12"].font = Font(name=FONTE, size=12, bold=True, color="134E3A")

    nota = rt + 2
    ws.cell(row=nota, column=2, value=(
        "Como ler: % aprovação = PASS ÷ (PASS + FAIL). % executado = (PASS + FAIL) ÷ total da aba; BLOCKED e NOT TESTED contam "
        "como não executados. Os números vêm das abas por fórmula: ao preencher a aba Android (manual), o painel se atualiza."
    )).font = Font(name=FONTE, size=9, color="435049")
    ws.cell(row=nota + 1, column=2, value=(
        f"Fontes: {total_testes} registros gravados pelos scripts em scripts/auditoria (resultados/*.json). "
        "Evidências: pasta evidencias (imagens) e logs (saída completa de cada suíte)."
    )).font = Font(name=FONTE, size=9, color="435049")

    # Reteste depois das correções: valores gravados pelos scripts (resultados/remoto.json, automatizados.json, telas.json)
    if reteste:
        r0 = nota + 3
        ws.cell(row=r0, column=2, value="Reteste depois das correções").font = Font(name=FONTE, size=12, bold=True, color="134E3A")
        cab_r = ["Suíte", "Testes", "🟢 PASS", "🔴 FAIL", "🟡 BLOCKED", "⚪ NOT TESTED"]
        for j, v in enumerate(cab_r):
            ws.cell(row=r0 + 1, column=2 + j, value=v)
        estilo_cabecalho(ws, r0 + 1, 7)
        ws.cell(row=r0 + 1, column=1).fill = PatternFill(fill_type=None)
        for i, (nome, c) in enumerate(reteste.items()):
            r = r0 + 2 + i
            valores = [RETESTE[nome], sum(c.values()), c["PASS"], c["FAIL"], c["BLOCKED"], c["NOT TESTED"]]
            for j, v in enumerate(valores):
                cel = ws.cell(row=r, column=2 + j, value=v)
                cel.font = Font(name=FONTE, size=10)
                cel.border = BORDA
                if j:
                    cel.alignment = Alignment(horizontal="center")
        ws.cell(row=r0 + 2 + len(reteste), column=2, value=(
            "Valores gravados pelos scripts no reteste, depois das correções (arquivos resultados/remoto.json, "
            "automatizados.json e telas.json). A coluna 'Reteste depois da correção' da aba Bugs encontrados mostra cada bug."
        )).font = Font(name=FONTE, size=9, color="435049")
        ws.cell(row=r0 + 3 + len(reteste), column=2, value=(
            "Achado novo no reteste (BUG-11, Média): com o servidor gratuito ocupado, a consulta do mapa passou do limite de 3 s "
            "uma vez (HTTP 500). Correção: o app repete sozinho, uma vez, a leitura que falhar por tempo esgotado."
        )).font = Font(name=FONTE, size=9, color="A3231A")

    graf = BarChart()
    graf.type = "bar"
    graf.grouping = "stacked"
    graf.overlap = 100
    graf.title = "Testes por módulo e status"
    graf.y_axis.title = "testes"
    dados = Reference(ws, min_col=4, max_col=7, min_row=lin0, max_row=rt - 1)
    cats = Reference(ws, min_col=2, min_row=lin0 + 1, max_row=rt - 1)
    graf.add_data(dados, titles_from_data=True)
    graf.set_categories(cats)
    for serie, cor in zip(graf.series, ("2E9E63", "D2453A", "E0A82E", "AEB8BF")):
        serie.graphicalProperties.solidFill = cor
        serie.graphicalProperties.line.solidFill = cor
    graf.height, graf.width = 11, 18
    ws.add_chart(graf, f"K{lin0}")

    for c, w in zip("ABCDEFGHI", (2, 30, 12, 12, 12, 13, 14, 16, 16)):
        ws.column_dimensions[c].width = w


def main() -> int:
    testes = carregar()
    destino = PASTA / "auditoria_gasprice.xlsx"
    preservados = preservar_android(testes, destino)
    if preservados:
        print(f"{preservados} caso(s) da aba Android preenchidos à mão foram mantidos")
    sem_bug = ligar_bugs(testes)
    if sem_bug:
        print("FALHAS SEM BUG ASSOCIADO:", *sem_bug, sep="\n  ")
        return 1
    por_aba: dict[str, list[dict]] = {}
    for t in testes:
        nome, pref = ABAS[t["aba"]]
        lista = por_aba.setdefault(nome, [])
        t["_id"] = f"{pref}-{len(lista) + 1:03d}"
        lista.append(t)
        if t.get("bug"):
            next(b for b in BUGS if b["id"] == t["bug"])["testes"].append(t["_id"])
    # Só entram bugs comprovados por pelo menos um teste que falhou; numeração pela prioridade (severidade)
    ordem_sev = {"Crítica": 0, "Alta": 1, "Média": 2, "Baixa": 3}
    ativos = sorted((b for b in BUGS if b["testes"]), key=lambda b: (ordem_sev[b["sev"]], BUGS.index(b)))
    novo = {b["id"]: f"BUG-{n:02d}" for n, b in enumerate(ativos, 1)}
    for t in testes:
        if t.get("bug"):
            t["bug"] = novo[t["bug"]]
    for b in ativos:
        b["id"] = novo[b["id"]]
    BUGS[:] = ativos
    bugs_testes: dict[str, list[dict]] = {}
    for t in testes:
        if t.get("bug"):
            bugs_testes.setdefault(t["bug"], []).append(t)
    contagem_reteste, status_reteste = carregar_reteste()
    ligar_reteste(bugs_testes, status_reteste)
    try:
        commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=RAIZ, capture_output=True, text=True).stdout.strip()
    except OSError:
        commit = "?"
    commit = commit or "?"

    wb = Workbook()
    wb.active.title = "Dashboard"
    ordem = [v[0] for v in ABAS.values() if v[0] in por_aba]
    dashboard(wb, ordem, commit, len(testes), contagem_reteste)
    for nome in ordem:
        aba_testes(wb, nome, por_aba[nome])
    aba_bugs(wb)
    wb.calculation.fullCalcOnLoad = True
    try:
        wb.save(destino)
    except PermissionError:
        print(f"Não consegui gravar {destino.name}: o arquivo está aberto no Excel. Feche-o e rode de novo.")
        return 1

    # Conferência: os mesmos números calculados em Python (o que as fórmulas devem mostrar no Excel)
    resumo = {}
    for nome in ordem:
        c = Counter(t["status"] for t in por_aba[nome])
        resumo[nome] = (len(por_aba[nome]), c["PASS"], c["FAIL"], c["BLOCKED"], c["NOT TESTED"])
    tot = [sum(v[i] for v in resumo.values()) for i in range(5)]
    (PASTA / "resultados" / "_resumo.json").write_text(json.dumps({"por_aba": resumo, "total": tot,
                                                                     "bugs": {b["id"]: (b["sev"], len(b["testes"])) for b in BUGS}},
                                                                    ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{destino}")
    for nome, v in resumo.items():
        print(f"  {nome:<20} total {v[0]:>4}  pass {v[1]:>4}  fail {v[2]:>3}  bloq {v[3]:>2}  não {v[4]:>3}")
    print(f"  TOTAL {tot}; aprovação {tot[1] / (tot[1] + tot[2]):.1%}; executado {(tot[1] + tot[2]) / tot[0]:.1%}")
    for b in BUGS:
        print(f"  {b['id']} {b['sev']:<6} {len(b['testes'])} teste(s)  {b['titulo'][:70]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
