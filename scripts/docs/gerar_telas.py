"""
Gera documentacao/telas_do_app.html: todas as telas do app, em ordem de uso, com a rota e o que cada uma faz.

As imagens vêm de documentacao/telas/*.webp e documentacao/telas/escuro/*.webp (capturas do modo de demonstração,
com dados de exemplo) e ficam embutidas na página. Para refazer as capturas: scripts/docs/capturar_telas.py --build.

Uso: python scripts/docs/gerar_telas.py
"""
from __future__ import annotations

import base64
import html
import subprocess
from datetime import date
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
e = html.escape

# (arquivo, título, rota, descrição)
CELULAR = [
    ("Primeiros passos", "Entrar no app e achar um posto", [
        ("01-boas-vindas", "Boas-vindas", "/boas-vindas", "Primeira abertura. Explica o app e pede a localização. Dá para pular."),
        ("04-mapa", "Mapa", "/", "OpenFreeMap com um pino de preço por posto. Pino preenchido: verde até 24 h, âmbar de 2 a 7 dias. O ícone de mira marca posição aproximada."),
        ("04b-mapa-posto", "Posto no mapa", "/", "Toque no pino para ver o posto, a distância e o preço. O pino escolhido ganha um anel. Daqui dá para atualizar o preço ou abrir o posto."),
        ("04c-mapa-diesel", "Pinos de contorno", "/", "Preço de mais de 7 dias tem contorno vermelho; posto sem preço, contorno cinza e um traço. Estimativa usa contorno tracejado e o sinal ≈."),
        ("02-busca", "Busca", "/buscar", "Por nome, endereço ou cidade, sem acento. Cada posto mostra a origem do preço."),
        ("03-filtros", "Filtros", "/buscar", "Combustível, faixa de preço, distância, nota e data. Rodam no aparelho."),
        ("19b-favoritos-lista", "Favoritos", "/favoritos", "Postos salvos, com o preço do combustível escolhido e o sino de aviso. Sem login ficam no aparelho."),
    ]),
    ("Posto", "O que o app mostra de um posto", [
        ("05-posto", "Posto", "/posto/:id", "Preço por combustível, com origem (comunidade, ANP ou estimativa), idade e confirmações. Atalhos para rota e avaliação."),
        ("06-contribuicoes", "Contribuições", "/posto/:id", "Toque em um preço para ver quem confirmou, as variações e o dado oficial da ANP."),
        ("08-historico", "Histórico", "/posto/:id/historico", "Gráfico com a pesquisa da ANP e os envios da comunidade em linhas separadas."),
        ("07-posto-estimativa", "Posto sem local conhecido", "/posto/:id", "Posto sem pesquisa da ANP mostra uma estimativa com margem de erro. Sem local conhecido, não recebe envio de preço."),
        ("21-posto-aproximado", "Localização aproximada", "/posto/:id", "Posição só pela rua. O envio vale a até 1 km, e o botão Estou neste posto corrige a posição."),
        ("22-posicao-posto", "Estou neste posto", "/posto/:id/posicao", "Informa a posição de quem está no posto. Após a confirmação da localização, a pessoa ganha 5 pontos."),
        ("09-avaliacoes", "Avaliações", "/posto/:id/avaliacoes", "Distribuição das notas, avaliações recentes e as mais úteis."),
        ("10-avaliar", "Avaliar", "/posto/:id/avaliar", "De 0 a 5 estrelas e um comentário opcional. Pode ser editada ou apagada."),
    ]),
    ("Envio de preço", "Da foto do painel ao preço confirmado", [
        ("11-enviar-instrucoes", "Antes da foto", "/posto/:id/enviar", "Explica como fotografar o painel e que a foto não sai do celular. Exige estar no raio do posto."),
        ("12-enviar-revisao", "Revisão", "/posto/:id/enviar", "Valores lidos no aparelho. A pessoa corrige o que estiver errado e escolhe o que enviar."),
        ("13-enviar-concluido", "Envio concluído", "/posto/:id/enviar", "Agradecimento pelo envio e atalhos para voltar ao posto ou ver os pontos."),
    ]),
    ("Conta", "Cadastro, entrada e recuperação", [
        ("14-entrar", "Entrar", "/entrar", "E-mail e senha."),
        ("15-cadastro", "Criar conta", "/cadastro", "Só nome, e-mail e senha. Não pede CPF nem endereço."),
        ("29-verificar-email", "Confirme seu e-mail", "/verificar-email", "Depois do cadastro. O link por e-mail ativa a conta, e há botão para reenviar."),
        ("16-recuperar-senha", "Recuperar senha", "/recuperar-senha", "Envia um link de redefinição para o e-mail."),
        ("28-nova-senha", "Nova senha", "/nova-senha", "Abre pelo link do e-mail. Mínimo de 8 caracteres, com maiúscula, minúscula, número e caractere especial."),
    ]),
    ("Perfil e comunidade", "Pontos, ranking e avisos", [
        ("17-perfil-visitante", "Perfil sem login", "/perfil", "Convite para entrar ou criar conta."),
        ("23-perfil", "Perfil", "/perfil", "Pontos, posição no ranking, nível, envios e avaliações recentes."),
        ("24-editar-perfil", "Alterar dados", "/perfil/editar", "Nome, foto opcional e o interruptor dos avisos de preço."),
        ("25-alterar-senha", "Alterar senha", "/perfil/senha", "Pede a senha atual antes de aceitar a nova."),
        ("26-pontos", "Meus pontos", "/pontos", "Como os pontos funcionam e o extrato de cada movimento."),
        ("18-ranking", "Ranking", "/ranking", "Comunidade por pontos. Nomes sempre abreviados."),
        ("27-avisos", "Avisos de preço", "/notificacoes", "Preço novo e ícone de queda ou alta nos postos favoritos. Toque para ver o gráfico do histórico."),
        ("20-sobre", "Sobre", "/sobre", "Versão, fontes de dados e privacidade."),
    ]),
]
TABLET = [
    ("33-tablet-mapa", "Mapa", "Mapa em tela larga."),
    ("31-tablet-busca", "Busca", "Lista e detalhes lado a lado."),
    ("30-tablet-posto", "Posto", "Preços e informações em duas colunas."),
    ("32-tablet-cadastro", "Cadastro", "Formulário centralizado, sem esticar."),
]
# Tema escuro (documentacao/telas/escuro): o app segue o modo do celular, e o mapa troca para o estilo escuro
ESCURO = [
    ("04-mapa", "Mapa", "Mapa escuro do OpenFreeMap. Os pinos preenchidos mantêm as cores do tema claro."),
    ("04b-mapa-posto", "Posto no mapa", "O anel de seleção fica claro sobre o mapa escuro."),
    ("04c-mapa-diesel", "Pinos de contorno", "Contorno sobre o fundo grafite, nos tons claros do preço."),
    ("02-busca", "Busca", "Cartões grafite sobre o fundo quase preto."),
    ("05-posto", "Posto", "Bolinhas de idade e selo ANP em tons claros."),
    ("06-contribuicoes", "Contribuições", "Selo de confiança com texto claro e bolinha colorida."),
    ("08-historico", "Histórico", "ANP em azul tracejado; comunidade em linha neutra."),
    ("23-perfil", "Perfil", "Pontos, ranking e últimos envios."),
]


def imagem(nome: str, pasta: str = "") -> str:
    arq = RAIZ / "documentacao" / "telas" / pasta / f"{nome}.webp"
    return "data:image/webp;base64," + base64.b64encode(arq.read_bytes()).decode()


def commit() -> str:
    try:
        return subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=RAIZ, capture_output=True, text=True,
                              check=True).stdout.strip()
    except Exception:  # noqa: BLE001
        return "sem commit"


def secoes() -> str:
    partes = []
    for grupo, sub, telas in CELULAR:
        figuras = "".join(
            f'<figure><img src="{imagem(arq)}" alt="Tela {e(titulo)}" loading="lazy">'
            f'<figcaption><b>{e(titulo)}</b><code>{e(rota)}</code><span>{e(desc)}</span></figcaption></figure>'
            for arq, titulo, rota, desc in telas)
        partes.append(f'<section><div class="cab"><h2>{e(grupo)}</h2><p class="lead">{e(sub)}</p></div>'
                      f'<div class="telas">{figuras}</div></section>')
    tablets = "".join(
        f'<figure><img src="{imagem(arq)}" alt="Tela de {e(titulo)} no tablet" loading="lazy">'
        f'<figcaption><b>{e(titulo)}</b><span>{e(desc)}</span></figcaption></figure>' for arq, titulo, desc in TABLET)
    partes.append('<section><div class="cab"><h2>Tablet</h2><p class="lead">As mesmas telas, com layout para tela larga.</p></div>'
                  f'<div class="tablets">{tablets}</div></section>')
    escuras = "".join(
        f'<figure><img src="{imagem(arq, "escuro")}" alt="Tela {e(titulo)} no tema escuro" loading="lazy">'
        f'<figcaption><b>{e(titulo)}</b><span>{e(desc)}</span></figcaption></figure>' for arq, titulo, desc in ESCURO)
    partes.append('<section><div class="cab"><h2>Tema escuro</h2><p class="lead">O app segue o modo claro ou escuro do celular. '
                  'Paleta Asfalto: fundo quase preto, cartões grafite e a marca em azul-acinzentado claro.</p></div>'
                  f'<div class="telas">{escuras}</div>'
                  f'<div class="tablets"><figure><img src="{imagem("33-tablet-mapa", "escuro")}" alt="Mapa no tablet, tema escuro" '
                  'loading="lazy"><figcaption><b>Mapa no tablet</b><span>Mapa escuro com a lista de postos ao lado.</span>'
                  '</figcaption></figure></div></section>')
    return "".join(partes)


TEMPLATE = """<title>Telas do gasprice</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@500;600;700&family=Public+Sans:wght@400;500;600;700&display=swap">
<style>
/* Layout: catálogo de telas por fluxo de uso; cada tela com rota e função. Mesma identidade da página de andamento. */
:root {
  --bg: #f4f7f6; --surface: #ffffff; --surface-2: #eaf1ee; --ink: #12201a; --ink-2: #435049; --muted: #6b7a73;
  --rule: #d6e0db; --accent: #0f7a5c;
  --display: "Barlow Condensed", "Arial Narrow", "Roboto Condensed", sans-serif;
  --body: "Public Sans", "Segoe UI", system-ui, sans-serif;
  --r: 12px;
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    color-scheme: dark;
    --bg: #0d1311; --surface: #151d1a; --surface-2: #1b2622; --ink: #e8f1ec; --ink-2: #b3c2bb; --muted: #86958e;
    --rule: #28342f; --accent: #43c29a;
  }
}
:root[data-theme="dark"] {
  color-scheme: dark;
  --bg: #0d1311; --surface: #151d1a; --surface-2: #1b2622; --ink: #e8f1ec; --ink-2: #b3c2bb; --muted: #86958e;
  --rule: #28342f; --accent: #43c29a;
}
* { box-sizing: border-box; }
body { background: var(--bg); color: var(--ink); font: 15px/1.6 var(--body); padding-inline: clamp(16px, 4vw, 48px); padding-block: 32px 72px; }
main { max-width: 1180px; margin: 0 auto; display: grid; gap: 56px; }
h1, h2 { font-family: var(--display); font-weight: 600; letter-spacing: .01em; line-height: 1.05; margin: 0; text-wrap: balance; }
h1 { font-size: clamp(2.6rem, 6vw, 4rem); font-weight: 700; }
h2 { font-size: 2.1rem; }
p { margin: 0; max-width: 70ch; }
.eyebrow { font: 600 .74rem/1 var(--body); letter-spacing: .12em; text-transform: uppercase; color: var(--muted); }
.lead { font-size: 1.1rem; color: var(--ink-2); }
section { display: grid; gap: 20px; }
.cab { display: grid; gap: 8px; }
code { font: .82em ui-monospace, "Cascadia Code", Consolas, monospace; background: var(--surface-2); padding: .1em .4em; border-radius: 5px; width: fit-content; }
.telas { display: grid; grid-template-columns: repeat(auto-fill, minmax(190px, 1fr)); gap: 22px 18px; }
.telas figure, .tablets figure { margin: 0; display: grid; gap: 10px; align-content: start; }
.telas img { width: 100%; aspect-ratio: 520 / 1125; object-fit: cover; object-position: top; border-radius: 16px; border: 1px solid var(--rule); background: var(--surface); }
.tablets { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 20px; }
.tablets img { width: 100%; aspect-ratio: 1200 / 838; object-fit: cover; object-position: top; border-radius: 12px; border: 1px solid var(--rule); }
figcaption { font-size: .86rem; color: var(--ink-2); display: grid; gap: 4px; justify-items: start; }
figcaption b { color: var(--ink); font-weight: 600; font-size: .95rem; }
.nota { background: var(--surface); border: 1px solid var(--rule); border-radius: var(--r); padding: 14px 18px; color: var(--ink-2); font-size: .92rem; }
footer { font-size: .82rem; color: var(--muted); border-top: 1px solid var(--rule); padding-top: 18px; }
</style>

<main>
  <header class="cab">
    <span class="eyebrow">gasprice · telas do app</span>
    <h1>Todas as telas do gasprice</h1>
    <p class="lead">As 22 telas do app em {{TOTAL}} capturas, na ordem em que a pessoa as encontra, cada uma com a rota e o que faz. Algumas telas aparecem mais de uma vez, em estados diferentes. Para celular e tablet.</p>
    <p class="nota">As imagens vêm do modo de demonstração: os postos, preços e a conta de Carla M. são dados de exemplo, não reais. O mapa usa o OpenFreeMap, com dados do OpenStreetMap.</p>
  </header>
  {{SECOES}}
  <footer>Gerado em {{DATA}} a partir do commit {{COMMIT}}. Mapa: OpenFreeMap, © OpenMapTiles, dados © colaboradores do OpenStreetMap.</footer>
</main>
"""


def main() -> None:
    n_celular = sum(len(t) for _, _, t in CELULAR)
    saida = (TEMPLATE.replace("{{SECOES}}", secoes()).replace("{{TOTAL}}", str(n_celular))
             .replace("{{DATA}}", date.today().strftime("%d/%m/%Y")).replace("{{COMMIT}}", commit()))
    destino = RAIZ / "documentacao" / "telas_do_app.html"
    destino.write_text(saida, encoding="utf-8")
    print(f"{destino} gerado: {n_celular} telas de celular, {len(TABLET)} de tablet, {destino.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()
