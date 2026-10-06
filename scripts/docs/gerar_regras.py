"""
Gera documentacao/regras_de_negocio.html a partir de scripts/docs/regras_template.html.

Monta o diagrama do caminho de um preço, o diagrama de entidades e relacionamentos,
o catálogo de regras e a tabela de parâmetros (lida da migração, para nunca divergir do banco).

Uso: python scripts/docs/gerar_regras.py
"""
from __future__ import annotations

import html
import re
from datetime import date
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
e = html.escape

# ------------------------------------------------------------------ caminho de um preço
def fluxo() -> str:
    s = ['<svg viewBox="0 0 1160 312" role="img" aria-label="Caminho de um preço: a foto é lida e apagada no celular; '
         'só valores e posição vão ao servidor, que valida; o banco confirma com duas pessoas em 24 horas.">',
         '<defs>'
         '<marker id="f-ponta" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="9" markerHeight="9" '
         'markerUnits="userSpaceOnUse" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="currentColor"/></marker>'
         '<marker id="f-ponta-d" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="10" markerHeight="10" '
         'markerUnits="userSpaceOnUse" orient="auto"><path class="rotulo-destaque" d="M0,0 L10,5 L0,10 z"/></marker>'
         '</defs>']
    for x, w, nome in [(10, 530, "NO CELULAR"), (552, 250, "NO SERVIDOR · EDGE FUNCTION"), (812, 342, "NO BANCO · REGRAS SQL")]:
        s.append(f'<rect class="lane" x="{x}" y="36" width="{w}" height="250" rx="12"/>')
        s.append(f'<text class="lane-nome" x="{x + 14}" y="58">{e(nome)}</text>')
    s.append('<line class="fronteira" x1="546" y1="86" x2="546" y2="292"/>')
    s.append('<text class="rotulo-destaque" x="546" y="306" text-anchor="middle">a foto nunca passa desta linha</text>')

    def no(x, y, w, h, titulo, texto, chave=False):
        cls = "no-chave" if chave else "no"
        cx = x + w / 2
        s.append(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="10"/>')
        s.append(f'<text class="no-titulo" x="{cx}" y="{y + h / 2 - 4}" text-anchor="middle">{e(titulo)}</text>')
        s.append(f'<text class="no-texto" x="{cx}" y="{y + h / 2 + 13}" text-anchor="middle">{e(texto)}</text>')

    def seta(pontos, rotulo=None, rx=None, ry=None, ancora="middle", destaque=False):
        d = " ".join(f"{x},{y}" for x, y in pontos)
        cls, marca = ("seta-destaque", "f-ponta-d") if destaque else ("seta", "f-ponta")
        s.append(f'<polyline class="{cls}" points="{d}" marker-end="url(#{marca})"/>')
        if rotulo:
            rc = "rotulo-destaque" if destaque else "rotulo"
            s.append(f'<text class="{rc}" x="{rx}" y="{ry}" text-anchor="{ancora}">{e(rotulo)}</text>')

    y, h = 86, 64
    no(24, y, 128, h, "Foto do painel", "câmera do celular")
    no(192, y, 154, h, "Leitura no aparelho", "ML Kit, sem internet")
    no(388, y, 134, h, "Revisão", "corrige e escolhe")
    no(578, y, 200, h, "Validação", "login, raio, faixa, limites")
    no(836, y, 140, h, "Consenso", "2 pessoas, 24 h")
    no(1012, y, 136, h, "Preço confirmado", "exibido + pontos", chave=True)
    m = y + h / 2
    seta([(152, m), (190, m)], "foto local", 171, 78)
    seta([(346, m), (386, m)], "valores lidos", 366, 78)
    seta([(522, m), (576, m)], "só valores + posição", 550, 78, destaque=True)
    seta([(778, m), (834, m)], "proposta", 807, 78)
    seta([(976, m), (1010, m)], "confirma", 993, 78)

    yb, hb = 204, 56
    no(192, yb, 154, hb, "Foto apagada", "logo após a leitura")
    no(578, yb, 200, hb, "Recusado com motivo", "mensagem explica o porquê")
    no(836, yb, 140, hb, "Não confirmado", "histórico após 24 h")
    no(1012, yb, 136, hb, "Vale a ANP", "envios divergem")
    seta([(269, y + h), (269, yb - 2)], "apaga", 277, 182, "start")
    seta([(678, y + h), (678, yb - 2)], "não passa", 686, 182, "start")
    seta([(872, y + h), (872, yb - 2)], "24 h", 880, 182, "start")
    seta([(950, y + h), (950, 190), (1080, 190), (1080, yb - 2)], "divergem", 1015, 184)
    s.append("</svg>")
    return "".join(s)


# ------------------------------------------------------------------ como a estimativa é calculada
def estimativa() -> str:
    """Esquema do cálculo: 5 vizinhos mais próximos dentro de 200 km, mediana, margem pela distância."""
    import math
    cx, cy, r = 300, 200, 180          # centro do posto sem preço e raio de 200 km em pixels
    km_por_px = 200 / r
    # (ângulo em graus, distância em pixels, preço, quem é), espalhados para os rótulos não se sobreporem
    polares = [
        (-120, 31, 6.09, "viz"), (170, 62, 6.19, "viz"), (30, 88, 6.05, "viz"),
        (-140, 110, 6.29, "viz"), (-15, 132, 6.14, "viz"),
        (100, 150, 5.89, "corte"), (150, 165, 6.49, "corte"), (-30, 215, 5.79, "fora"),
    ]
    pontos = [(round(cx + d * math.cos(math.radians(a)), 1), round(cy + d * math.sin(math.radians(a)), 1), pr, t)
              for a, d, pr, t in polares]
    dist = lambda p: math.hypot(p[0] - cx, p[1] - cy)
    viz = sorted([p for p in pontos if p[3] == "viz"], key=dist)
    precos = sorted(p[2] for p in viz)
    mediana = precos[len(precos) // 2]
    d_min = round(dist(viz[0]) * km_por_px)
    margem = 0.25 if d_min < 25 else 0.29 if d_min < 50 else 0.30 if d_min < 100 else 0.39
    br = lambda v: f"{v:.2f}".replace(".", ",")

    s = ['<svg viewBox="0 0 1160 450" role="img" aria-label="Como a estimativa é calculada: os 5 postos pesquisados '
         'mais próximos dentro de 200 km dão a mediana dos preços, e a distância do mais próximo define o erro médio.">',
         '<defs><marker id="e-ponta" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="9" markerHeight="9" '
         'markerUnits="userSpaceOnUse" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="currentColor"/></marker></defs>',
         f'<circle class="raio" cx="{cx}" cy="{cy}" r="{r}"/>',
         f'<text class="rotulo-destaque" x="{cx}" y="{cy - r - 8}" text-anchor="middle">limite de 200 km</text>']
    for p in viz:
        s.append(f'<line class="liga" x1="{cx}" y1="{cy}" x2="{p[0]}" y2="{p[1]}"/>')
    for x, y, preco, tipo in pontos:
        if tipo == "viz":
            s.append(f'<circle class="ponto" cx="{x}" cy="{y}" r="8"/>')
            s.append(f'<text class="preco-viz" x="{x + 13}" y="{y + 4}">{br(preco)}</text>')
        else:
            s.append(f'<circle class="ponto-fora" cx="{x}" cy="{y}" r="7"/>')
            motivo = "não usado" if tipo == "corte" else "a mais de 200 km"
            s.append(f'<text class="preco-fora" x="{x + 12}" y="{y + 4}">{br(preco)} · {motivo}</text>')
    s.append(f'<circle class="alvo" cx="{cx}" cy="{cy}" r="11"/>')
    v0 = viz[0]
    s.append(f'<text class="rotulo-destaque" x="{(cx + v0[0]) / 2 - 14}" y="{(cy + v0[1]) / 2 - 6}" text-anchor="end">{d_min} km</text>')
    # legenda do mapa
    s.append('<circle class="alvo" cx="30" cy="424" r="7"/><text class="rotulo" x="44" y="428">posto sem preço</text>')
    s.append('<circle class="ponto" cx="190" cy="424" r="6"/><text class="rotulo" x="202" y="428">um dos 5 mais próximos</text>')
    s.append('<circle class="ponto-fora" cx="380" cy="424" r="6"/><text class="rotulo" x="392" y="428">pesquisado, mas não usado</text>')

    # coluna do cálculo
    x0, w, h = 690, 440, 62
    etapas = [
        ("1. Vizinhos", "os 5 postos pesquisados mais próximos com o mesmo combustível"),
        ("2. Corte", "quem está a mais de 200 km sai"),
        ("3. Mediana", " · ".join(br(v) for v in precos) + f"  →  {br(mediana)}"),
        ("4. Margem", f"vizinho mais próximo a {d_min} km  →  erro médio R$ {br(margem)}"),
    ]
    y = 34
    for i, (t, txt) in enumerate(etapas):
        cls = "mediana" if i == 2 else "no"
        s.append(f'<rect class="{cls}" x="{x0}" y="{y}" width="{w}" height="{h}" rx="10"/>')
        s.append(f'<text class="no-titulo" x="{x0 + 16}" y="{y + 26}">{e(t)}</text>')
        s.append(f'<text class="no-texto" x="{x0 + 16}" y="{y + 46}">{e(txt)}</text>')
        if i < len(etapas) - 1:
            s.append(f'<line class="seta" x1="{x0 + w / 2}" y1="{y + h}" x2="{x0 + w / 2}" y2="{y + h + 18}" marker-end="url(#e-ponta)"/>')
        y += h + 18
    s.append(f'<rect class="no-chave" x="{x0}" y="{y + 4}" width="{w}" height="70" rx="10"/>')
    s.append(f'<text class="no-titulo" x="{x0 + 16}" y="{y + 32}" style="font-size:20px">≈ R$ {br(mediana)}</text>')
    s.append(f'<text class="no-texto" x="{x0 + 16}" y="{y + 54}">o que o app mostra: estimativa, erro médio R$ {br(margem)}, referência a {d_min} km</text>')
    s.append(f'<line class="seta" x1="{x0 + w / 2}" y1="{y - 18}" x2="{x0 + w / 2}" y2="{y + 2}" marker-end="url(#e-ponta)"/>')
    s.append("</svg>")
    return "".join(s)


# ------------------------------------------------------------------ entidades e relacionamentos
LARG = 200
X = {1: 20, 2: 250, 3: 480, 4: 710, 5: 940}

ENTIDADES = {
    # nome: (coluna, y, campos [(texto, chave)], destaque, etiqueta)
    "posto_produtos":    (1, 20, [("posto_id", "FK"), ("produto_id", "FK"), ("bicos", "")], False, None),
    "precos_anp":        (2, 20, [("posto_id", "FK"), ("produto_id", "FK"), ("data_coleta", "PK"), ("preco", ""), ("anomalia", "")], False, None),
    "precos_estimados":  (3, 20, [("posto_id", "FK"), ("produto_id", "FK"), ("preco", ""), ("margem", ""), ("distancia_km", "")], False, None),
    "precos_atuais":     (4, 20, [("posto_id", "FK"), ("produto_id", "FK"), ("preco · fonte · situacao", ""), ("confirmacoes", ""), ("ultimo_confiavel", "")], False, None),
    "precos_comunidade": (5, 20, [("posto_id", "FK"), ("produto_id", "FK"), ("dia", "PK"), ("preco", ""), ("confirmado", "")], False, None),
    "produtos":          (1, 190, [("id", "PK"), ("codigo", ""), ("nome", ""), ("preco_min · preco_max", "")], False, None),
    "previsoes":         (2, 190, [("uf · municipio", "PK"), ("produto_id", "FK"), ("semana", "PK"), ("preco_previsto", "")], False, None),
    "postos":            (3, 190, [("id", "PK"), ("cnpj", "ÚNICO"), ("razao_social · bandeira", ""), ("localizacao (PostGIS)", ""), ("precisao_localizacao", ""), ("municipio_pesquisado_anp", "")], True, None),
    "sincronizacoes_anp": (4, 190, [("uf", "PK"), ("executado_em", ""), ("registros", "")], False, None),
    "parametros":        (5, 190, [("chave", "PK"), ("valor", ""), ("descricao", "")], False, None),
    "envios":            (1, 370, [("id", "PK"), ("usuario_id", "FK"), ("posto_id", "FK"), ("posicao · distancia_m", ""), ("ocr_texto", "")], False, "SEM FOTO"),
    "avaliacoes":        (2, 370, [("id", "PK"), ("posto_id", "FK"), ("usuario_id", "FK"), ("nota 0–5 · comentario", "")], False, None),
    "favoritos":         (3, 370, [("usuario_id", "FK"), ("posto_id", "FK"), ("notificar", "")], False, None),
    "notificacoes":      (4, 370, [("usuario_id", "FK"), ("posto_id", "FK"), ("produto_id", "FK"), ("preco_anterior → novo", ""), ("lida", "")], False, None),
    "correcoes_posicao": (5, 370, [("usuario_id", "FK"), ("posto_id", "FK"), ("posicao", ""), ("precisao_gps_m", ""), ("criado_em", "")], False, None),
    "envio_itens":       (1, 540, [("id", "PK"), ("envio_id", "FK"), ("produto_id", "FK"), ("preco · preco_lido", ""), ("status · em_revisao", "")], False, None),
    "avaliacao_votos":   (2, 540, [("avaliacao_id", "FK"), ("usuario_id", "FK")], False, None),
    "perfis":            (3, 540, [("id", "PK · FK"), ("nome", ""), ("pontos", ""), ("confiabilidade", ""), ("bloqueado_ate · banido", "")], True, None),
    "auth.users":        (4, 540, [("id", "PK"), ("email", ""), ("senha: hash no Auth", "")], False, None),
    "pontos_movimentos": (5, 540, [("usuario_id", "FK"), ("envio_item_id", "FK"), ("pontos", ""), ("tipo", "")], False, None),
}


def altura(n: int) -> int:
    return 26 + 16 * n + 8


def caixa_de(nome: str):
    col, y, campos, _, _ = ENTIDADES[nome]
    x = X[col]
    return x, y, LARG, altura(len(campos))


def topo(nome, dx=0):
    x, y, w, _ = caixa_de(nome)
    return x + w / 2 + dx, y


def base(nome, dx=0):
    x, y, w, h = caixa_de(nome)
    return x + w / 2 + dx, y + h


def esq(nome, y):
    x, _, _, _ = caixa_de(nome)
    return x, y


def dir_(nome, y):
    x, _, w, _ = caixa_de(nome)
    return x + w, y


def er() -> str:
    s = ['<svg viewBox="0 0 1160 700" role="img" aria-label="Diagrama de entidades e relacionamentos: postos se liga às '
         'tabelas de preço, envios, avaliações, favoritos e avisos; perfis se liga a envios, avaliações, favoritos, '
         'avisos, votos e pontos; envios têm itens por combustível.">',
         '<defs>'
         '<marker id="er-muitos" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="12" markerHeight="12" '
         'markerUnits="userSpaceOnUse" orient="auto"><path d="M0,5 L10,0 M0,5 L10,5 M0,5 L10,10" '
         'stroke="currentColor" stroke-width="1.2" fill="none"/></marker>'
         '<marker id="er-um" viewBox="0 0 10 10" refX="0" refY="5" markerWidth="12" markerHeight="12" '
         'markerUnits="userSpaceOnUse" orient="auto"><path d="M6,0 L6,10" stroke="currentColor" stroke-width="1.2" fill="none"/></marker>'
         '<marker id="er-um-fim" viewBox="0 0 10 10" refX="10" refY="5" markerWidth="12" markerHeight="12" '
         'markerUnits="userSpaceOnUse" orient="auto"><path d="M4,0 L4,10" stroke="currentColor" stroke-width="1.2" fill="none"/></marker>'
         '</defs>']

    def rel(a, b, fim="er-muitos"):
        s.append(f'<line class="rel" x1="{a[0]}" y1="{a[1]}" x2="{b[0]}" y2="{b[1]}" marker-start="url(#er-um)" marker-end="url(#{fim})"/>')

    # Relacionamentos (desenhados antes das caixas, que ficam por cima)
    for dx, filho in zip((-60, -30, 0, 30, 60), ("posto_produtos", "precos_anp", "precos_estimados", "precos_atuais", "precos_comunidade")):
        rel(topo("postos", dx), base(filho))
    for dx, filho, fdx in zip((-50, -25, 0, 25), ("envios", "avaliacoes", "favoritos", "notificacoes"), (0, 0, 0, 0)):
        rel(base("postos", dx), topo(filho, fdx))
    for dx, filho, fdx in zip((-50, -25, 0, 25), ("envios", "avaliacoes", "favoritos", "notificacoes"), (50, 30, 0, 0)):
        rel(topo("perfis", dx), base(filho, fdx))
    rel(base("postos", 50), topo("correcoes_posicao"))
    rel(base("envios", -20), topo("envio_itens", -20))
    rel(base("avaliacoes", -30), topo("avaliacao_votos", -30))
    rel(esq("perfis", 573), dir_("avaliacao_votos", 573))
    rel(dir_("perfis", 581), esq("auth.users", 581), fim="er-um-fim")
    rel(dir_("produtos", 239), esq("previsoes", 239))

    # Pontos: dois conectores em cotovelo, por baixo da última fileira, para não atravessar caixas
    def cotovelo(pontos):
        d = " ".join(f"{x},{y}" for x, y in pontos)
        s.append(f'<polyline class="rel" points="{d}" marker-start="url(#er-um)" marker-end="url(#er-muitos)"/>')

    fundo = max(caixa_de(n)[1] + caixa_de(n)[3] for n in ("envio_itens", "perfis"))
    pxm, pym = base("pontos_movimentos")
    ex, ey = base("envio_itens", 40)
    cotovelo([(ex, ey), (ex, fundo + 34), (pxm - 40, fundo + 34), (pxm - 40, pym)])
    gx, gy = base("perfis")
    cotovelo([(gx, gy), (gx, fundo + 16), (pxm + 40, fundo + 16), (pxm + 40, pym)])

    for nome, (col, y, campos, destaque, etiqueta) in ENTIDADES.items():
        x = X[col]
        h = altura(len(campos))
        s.append(f'<g class="{"ent-destaque" if destaque else ""}">')
        s.append(f'<rect class="ent-caixa" x="{x}" y="{y}" width="{LARG}" height="{h}" rx="8"/>')
        s.append(f'<path class="ent-topo" d="M{x + 1},{y + 26} V{y + 8} a7,7 0 0 1 7,-7 H{x + LARG - 8} a7,7 0 0 1 7,7 V{y + 26} Z"/>')
        s.append(f'<text class="ent-nome" x="{x + 10}" y="{y + 18}">{e(nome)}</text>')
        if etiqueta:
            s.append(f'<text class="ent-tag" x="{x + LARG - 10}" y="{y + 18}" text-anchor="end">{e(etiqueta)}</text>')
        for i, (campo, chave) in enumerate(campos):
            ty = y + 26 + 16 * i + 13
            s.append(f'<text class="ent-campo" x="{x + 10}" y="{ty}">{e(campo)}</text>')
            if chave:
                s.append(f'<text class="ent-chave" x="{x + LARG - 10}" y="{ty}" text-anchor="end">{e(chave)}</text>')
        s.append("</g>")
    s.append("</svg>")
    return "".join(s)


# ------------------------------------------------------------------ catálogo de regras
C, S, B, A = "celular", "servidor", "banco", "agendado"
REGRAS = [
    ("Conta e acesso", [
        ("Consultar mapa, busca, filtros, preços, histórico, avaliações e ranking não exige conta.", [C, B], ""),
        ("Enviar preços, avaliar, votar em avaliações e guardar favoritos na conta exigem login.", [S, B], ""),
        ("O cadastro pede só nome, e-mail e senha. Não pede CPF, data de nascimento nem endereço.", [C], ""),
        ("A senha precisa ter pelo menos 8 caracteres, com letras e números.", [C, S], "8+"),
        ("O e-mail precisa ser confirmado pelo link antes do primeiro envio de preço.", [S], ""),
        ("Sem login, os favoritos ficam no aparelho. Ao entrar, eles vão para a conta.", [C], ""),
    ]),
    ("Envio por foto", [
        ("O envio começa pela foto do painel. O texto é lido no aparelho, sem internet.", [C], ""),
        ("A foto é apagada logo após a leitura e nunca é enviada nem guardada.", [C], ""),
        ("O usuário revisa os valores lidos, corrige o que estiver errado e escolhe o que enviar.", [C], ""),
        ("Em posto com posição exata, o envio só é aceito com o aparelho a até 300 metros do posto.", [C, S], "300 m"),
        ("Cada preço precisa estar na faixa do combustível.", [C, S], "R$ 2,00 a 15,00 · etanol e GNV R$ 1,50 a 12,00"),
        ("Cada usuário faz no máximo 20 envios em 24 horas.", [S], "20 por 24 h"),
        ("O mesmo usuário só reenvia o mesmo combustível do mesmo posto depois de 6 horas.", [S], "6 h"),
        ("O envio é uma proposta: aparece como aguardando confirmação e só vira preço confirmado com o consenso.", [S, B], ""),
        ("Limite diário, intervalo de 6 horas e gravação acontecem juntos, um envio por vez para cada usuário.", [S, B], ""),
    ]),
    ("Localização dos postos", [
        ("Cada posto tem uma precisão de localização: exata, rua, CEP de rua, CEP da cidade, município ou nenhuma.", [B], ""),
        ("Posição exata vem da coordenada da ANP, do número do endereço ou de confirmação pela comunidade.", [B], ""),
        ("Em posto com posição aproximada (rua ou CEP de rua), o envio de preço é aceito a até 1 km do ponto no mapa.", [C, S], "1 km"),
        ("Posto com posição aproximada aparece no mapa com um marcador de localização aproximada.", [C], ""),
        ("Posto com CEP da cidade, município ou sem localização não aparece no mapa e não aceita envio de preço.", [C, S, B], ""),
        ("O botão Estou neste posto corrige a posição, sem limite de distância. Exige GPS com precisão de até 100 metros.", [C, S], "100 m"),
        ("A posição informada só vale como exata quando 2 usuários diferentes informam pontos a até 150 metros um do outro.", [B], "2 pessoas · 150 m"),
        ("A posição informada espera por confirmação por 30 dias. Cada confirmação rende 5 pontos.", [B], "30 dias · +5"),
        ("Cada usuário informa no máximo 10 posições de posto em 24 horas, a até 100 km da posição aproximada.", [S, B], "10 por 24 h · 100 km"),
    ]),
    ("Consenso e revisão", [
        ("O preço é confirmado quando 2 usuários diferentes informam valores com diferença de até R$ 0,02 em 24 horas.", [B], "2 pessoas · R$ 0,02 · 24 h"),
        ("Um envio que difere mais de 20% do preço de referência entra em revisão e precisa de 3 usuários.", [S, B], "20% · 3 pessoas"),
        ("Envio em revisão não aparece como preço antes de ser confirmado.", [B], ""),
        ("Usuário com confiabilidade abaixo de 0,20 tem os envios sempre em revisão e não conta para o consenso.", [S, B], "0,20"),
        ("Quando um consenso se forma, os envios pendentes que discordam dele viram contestados.", [B], ""),
        ("Sem confirmação em 24 horas, o envio entra no histórico como não confirmado.", [A], "de hora em hora"),
    ]),
    ("Preço exibido", [
        ("A escolha da fonte segue a ordem de prioridade da seção acima.", [B], ""),
        ("Um preço confirmado só é trocado por outro consenso, nunca por um envio isolado.", [B], ""),
        ("Preços da ANP marcados como anomalia nunca aparecem como preço exibido.", [B], ""),
        ("A cor do preço indica a idade: verde até 24 h, amarelo de 2 a 7 dias, vermelho acima de 7 dias ou estimativa.", [C], "24 h · 7 dias"),
        ("Todo preço mostra a origem: comunidade com o número de confirmações, pesquisa ANP com a semana ou estimativa com a margem.", [C], ""),
        ("A estimativa usa a mediana dos 5 postos pesquisados mais próximos, até 200 km, entre os que têm preço da ANP nos 60 dias anteriores à coleta mais recente.", [A], "5 vizinhos · 200 km · 60 dias"),
        ("A margem exibida é o erro médio medido para a faixa de distância até o vizinho mais próximo. Não é um limite.", [A, C], "R$ 0,25 · 0,29 · 0,30 · 0,39"),
        ("Postos sem coordenada não recebem estimativa e não servem de referência.", [A], "15% dos postos ativos"),
        ("A estimativa é recalculada toda segunda-feira, na carga inicial e sempre que a pesquisa da ANP for recarregada.", [A], "toda segunda-feira"),
    ]),
    ("Pontos e confiabilidade", [
        ("Cada envio confirmado vale 10 pontos, uma vez por pessoa em cada consenso.", [B], "+10"),
        ("O primeiro envio de um consenso, em posto sem confirmação nas últimas 24 horas, ganha 5 pontos de bônus.", [B], "+5"),
        ("Em cidades sem coleta da ANP nos últimos 12 meses, pontos e bônus valem o dobro.", [B], "×2"),
        ("Envio contestado perde 5 pontos. O saldo nunca fica negativo.", [B], "−5"),
        ("Cada usuário ganha no máximo 200 pontos por dia.", [B], "200 por dia"),
        ("A confiabilidade começa em 0,50, sobe 0,05 por envio confirmado e cai 0,10 por contestado.", [B], "0,50 · +0,05 · −0,10"),
        ("Três envios contestados em 7 dias pausam novos envios por 7 dias.", [S, B], "3 em 7 dias"),
        ("O nível no perfil vem da confiabilidade: Em observação, Iniciante, Confiável e Referência.", [C], "0,30 · 0,60 · 0,80"),
    ]),
    ("Avaliações, favoritos e avisos", [
        ("A nota vai de 0 a 5 estrelas, uma por pessoa e posto, e pode ser editada ou apagada.", [B], "0 a 5"),
        ("O comentário é opcional e tem de 3 a 500 caracteres.", [C, B], "3 a 500"),
        ("A nota média e o total de avaliações são calculados no servidor.", [B], ""),
        ("A ordem por mais úteis usa os votos de outras pessoas. Ninguém vota na própria avaliação, nem pela API.", [C, B], ""),
        ("Quem escreveu cada avaliação e quem votou não são públicos: o app mostra só o nome abreviado.", [B], ""),
        ("Quem favoritou o posto é avisado quando um preço confirmado ou oficial muda R$ 0,05 ou mais em relação ao último preço confiável.", [B], "R$ 0,05"),
        ("O aviso pode ser desligado por posto ou para a conta inteira.", [C, B], ""),
        ("Para outras pessoas, o nome aparece sempre abreviado, como Carla M.", [B], ""),
    ]),
    ("Dados da ANP", [
        ("O cadastro de postos vem da API de Revendedores da ANP, uma UF de cada vez. O CNPJ identifica o posto.", [A, S], "domingo de madrugada"),
        ("Uma posição corrigida manualmente não é sobrescrita pela sincronização.", [B], ""),
        ("A coordenada da ANP só vale se cair no estado do posto (contorno do IBGE) e não for um ponto padrão repetido em vários estados. Senão, o posto fica com localização desconhecida.", [B], "15 km"),
        ("Posto que sai do cadastro da ANP fica inativo, e o histórico dele é mantido.", [B], ""),
        ("O banco guarda os preços da ANP desde julho de 2024. A série completa fica num arquivo privado do Storage.", [S], "plano gratuito"),
        ("Preços da ANP que destoam ficam marcados como anomalia e nunca são apagados.", [B], ""),
        ("As cidades com coleta da ANP são recalculadas toda semana, para definir onde os pontos dobram.", [A], "toda segunda-feira"),
    ]),
    ("Conta e privacidade", [
        ("Excluir a conta apaga perfil, avaliações, favoritos, pontos e avisos. Os preços enviados ficam no histórico, sem vínculo com a pessoa.", [S, B], ""),
        ("A foto de perfil é opcional, tem até 200 KB e é pública.", [C, B], "200 KB"),
        ("O app usa só a chave publicável do Supabase. As chaves secretas ficam no servidor e no GitHub Actions.", [C, S], ""),
    ]),
]
NOMES_ONDE = {C: "CELULAR", S: "SERVIDOR", B: "BANCO", A: "AGENDADO"}


def regras() -> str:
    partes, n = [], 0
    for grupo, lista in REGRAS:
        linhas = []
        for texto, onde, valor in lista:
            n += 1
            chips = "".join(f'<span class="o-{o}">{NOMES_ONDE[o]}</span>' for o in onde)
            linhas.append(f'<tr data-onde="{" ".join(onde)}"><td class="id">RN-{n:02d}</td><td>{e(texto)}</td>'
                          f'<td class="onde">{chips}</td><td class="valor">{e(valor)}</td></tr>')
        partes.append(f'<div class="grupo"><h3>{e(grupo)}</h3><div class="tabela"><table>'
                      f'<thead><tr><th>ID</th><th>Regra</th><th>Onde</th><th>Valor</th></tr></thead>'
                      f'<tbody>{"".join(linhas)}</tbody></table></div></div>')
    return "".join(partes)


def ler_parametros() -> list[tuple[str, str, str]]:
    """Todos os parâmetros inseridos por qualquer migração, na ordem em que foram criados."""
    itens = []
    for arq in sorted((RAIZ / "supabase" / "migrations").glob("*.sql")):
        sql = arq.read_text(encoding="utf-8")
        for bloco in re.findall(r"insert into public\.parametros[^;]*;", sql):
            itens += re.findall(r"\('(\w+)',\s*([-\d.]+),\s*'([^']*)'\)", bloco)
    return itens


def parametros() -> str:
    itens = ler_parametros()
    linhas = "".join(f"<tr><td><code>{e(k)}</code></td><td class=\"valor\">{e(v.replace('.', ','))}</td><td>{e(d)}</td></tr>"
                     for k, v, d in itens)
    return ('<div class="tabela"><table><thead><tr><th>Chave</th><th>Valor</th><th>O que controla</th></tr></thead>'
            f"<tbody>{linhas}</tbody></table></div>")


def main() -> None:
    tpl = (RAIZ / "scripts" / "docs" / "regras_template.html").read_text(encoding="utf-8")
    saida = (tpl.replace("{{FLUXO}}", fluxo()).replace("{{ESTIMATIVA}}", estimativa()).replace("{{ER}}", er()).replace("{{REGRAS}}", regras())
             .replace("{{PARAMETROS}}", parametros()).replace("{{DATA}}", date.today().strftime("%d/%m/%Y")))
    destino = RAIZ / "documentacao" / "regras_de_negocio.html"
    destino.write_text(saida, encoding="utf-8")
    total = sum(len(l) for _, l in REGRAS)
    print(f"{destino} gerado: {total} regras, {destino.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()

