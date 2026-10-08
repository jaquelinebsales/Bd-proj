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
        ("Esquema com 22 tabelas, PostGIS e busca sem acento", OK),
        ("Regras de acesso: consulta pública, alteração só com login", OK),
        ("Consenso, revisão, pontos, bloqueio, avisos e estimativas", OK),
        ("Edge Functions: envio de preços, correção de posição, sincronização com a ANP e exclusão de conta", OK),
        ("Precisão da localização dos postos: envio a 1 km em posição aproximada e confirmação por 2 usuários", OK),
        ("Importador dos dados da ANP para o plano gratuito", OK),
        ("Testes das regras num Postgres 17 com PostGIS", OK),
        ("Rotinas pesadas medidas com 45 mil postos e 954 mil preços: de 2 s a 18 s; banco em cerca de 260 MB dos 500 MB", OK),
        ("Aplicado no seu projeto Supabase, com 45.823 postos, 1,65 milhão de preços e 135 mil estimativas", OK),
        ("Consulta pública e bloqueios conferidos no projeto real: 23 de 23 verificações", OK),
    ]),
    ("Fase 3 · App Flutter", [
        ("22 telas com layout para celular e tablet", OK),
        ("Postos com localização aproximada: marcador no mapa, aviso e botão Estou neste posto", OK),
        ("Cadastro, login, confirmação de e-mail e recuperação de senha", OK),
        ("Leitura do painel no aparelho, com a foto apagada em seguida", OK),
        ("Filtros, ordenação e cache no aparelho", OK),
        ("Avisos de preço em tempo real para favoritos", OK),
        ("Modo de demonstração com dados de exemplo", OK),
        ("Mapa do OpenFreeMap (MapLibre) no lugar do Google Maps: sem chave e sem cartão, com versão clara e escura", OK),
        ("Paleta Asfalto nos temas claro e escuro, com pinos de contorno para preço velho, estimativa e sem preço", OK),
        ("Documento com todas as telas (documentacao/telas_do_app.html)", OK),
        ("APK de teste gerado pelo GitHub Actions", OK),
        ("Rodar em aparelho Android e iOS", ESPERA),
        ("Ajustar o leitor com fotos reais de painéis", PROX),
    ]),
    ("Fase 4 · Publicação", [
        ("Repositório Git local com o primeiro commit", OK),
        ("Testes automáticos no GitHub Actions", OK),
        ("Publicação automática do banco e das funções", OK),
        ("Verificador do .env e publicação com um comando, sem copiar a string de conexão", OK),
        ("Geração do APK pelo GitHub Actions", OK),
        ("Código no GitHub, segredos cadastrados e testes e publicação do Supabase passando", OK),
    ]),
    ("Fase 5 · Evolução", [
        ("Auditoria completa: 873 testes, 10 bugs encontrados", OK),
        ("Correções da auditoria: 9 feitas e retestadas, 1 depende do painel do Supabase, 1 é decisão de região", OK),
        ("Reteste no Supabase real depois das correções: 344 aprovados, 4 falhas (senha, latência e BUG-11)", OK),
        ("Carga automática das semanas novas da pesquisa da ANP", OK),
        ("Teste de localização dos postos sem coordenada com 200 postos de amostra", OK),
        ("Nova regra de envio para posições aproximadas, no app e no servidor", OK),
        ("Localizar os 6.942 postos sem coordenada e carregar o resultado no banco", PROX),
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


NOME_NIVEL = {
    "numero": "Número da casa",
    "rua": "Rua",
    "cep_rua": "CEP de rua",
    "cep_cidade": "CEP da cidade inteira",
    "municipio": "Centro do município",
    "nada": "Não localizado",
}


def br(n: float, casas: int = 0) -> str:
    return f"{n:,.{casas}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def geocodificacao() -> tuple[str, str]:
    """Seção do teste de localização, montada a partir de dados/geocodificacao/amostra_resultados.json."""
    import json
    arq = RAIZ / "dados" / "geocodificacao" / "amostra_resultados.json"
    if not arq.exists():
        return "O teste ainda não foi rodado.", ""
    d = json.loads(arq.read_text(encoding="utf-8"))
    n = d["amostra"]
    total = sum(x["postos"] for x in d["panorama_por_uf"])
    cep_cidade = sum(x["cep_da_cidade"] for x in d["panorama_por_uf"])
    com_numero = sum(x["endereco_com_numero"] for x in d["panorama_por_uf"])
    cob = d["cobertura_sem_coordenada"]
    erro = d["erro_com_coordenada"]
    top = ", ".join(f"{x['uf']} {br(x['postos'])}" for x in d["panorama_por_uf"][:5])

    lead = (f"São {br(total)} postos ativos sem coordenada no cadastro da ANP. Testei o método em duas amostras de {n} postos: "
            f"uma de postos sem coordenada, para ver até onde cada camada chega, e outra de postos que já têm a coordenada da ANP, "
            f"para medir a distância entre o ponto encontrado e o ponto da ANP.")

    numeros = (
        '<div class="numeros">'
        f'<div class="numero"><b>{br(total)}</b><span>postos ativos sem coordenada. Maiores: {e(top)}</span></div>'
        f'<div class="numero"><b>{round(100 * cep_cidade / total)}%</b><span>têm CEP da cidade inteira, terminado em 000: '
        f'são postos de cidades pequenas</span></div>'
        f'<div class="numero"><b>{round(100 * com_numero / total)}%</b><span>têm número no endereço</span></div>'
        f'<div class="numero"><b>{cob.get("numero", 0) + cob.get("rua", 0)}%</b><span>da amostra foram achados pelo menos na rua</span></div>'
        '</div>'
    )

    linhas_cob = "".join(
        f'<tr><td>{e(NOME_NIVEL[k])}</td><td class="n">{cob.get(k, 0)}</td><td class="n">{br(total * cob.get(k, 0) / n)}</td></tr>'
        for k in ("numero", "rua", "cep_rua", "cep_cidade", "municipio", "nada") if cob.get(k, 0))
    tab_cob = ('<h3>Até onde cada camada chega</h3><div class="tabela"><table><thead><tr><th>Melhor nível alcançado</th>'
               f'<th>Postos na amostra de {n}</th><th>Projeção para os {br(total)}</th></tr></thead><tbody>{linhas_cob}</tbody></table></div>')

    def pct(v):
        return "–" if v is None else f"{v}%"

    linhas_erro = "".join(
        f'<tr><td>{e(NOME_NIVEL[k])}</td><td class="n">{v["casos"]}</td><td class="n">{br(v["mediana_km"], 2)} km</td>'
        f'<td class="n">{pct(v["ate_300m"])}</td><td class="n">{pct(v["ate_1km"])}</td><td class="n">{br(v["p90_km"], 1)} km</td></tr>'
        for k, v in erro.items())
    tab_erro = ('<h3>Quão perto da posição real</h3><div class="tabela"><table><thead><tr><th>Nível</th><th>Casos</th>'
                '<th>Distância mediana</th><th>Até 300 m</th><th>Até 1 km</th><th>9 em 10 ficam a menos de</th></tr></thead>'
                f'<tbody>{linhas_erro}</tbody></table></div>')

    conclusoes = (
        '<div class="duas">'
        '<div class="cartao"><h3>O que o teste mostrou</h3><ul>'
        '<li>A rua resolve a maior parte, mas metade dos pontos cai a mais de meio quilômetro do posto. Para ruas e rodovias longas, o erro passa de 5 km.</li>'
        '<li>Número da casa quase não existe no OpenStreetMap para essas cidades. Quando existe, acerta: 3 em 4 casos ficam a menos de 300 m.</li>'
        '<li>O CEP da cidade inteira aponta para o centro urbano e erra menos que o centro geométrico do município, que pode cair na zona rural.</li>'
        '<li>Em Brasília, endereços por quadra e setor se repetem entre regiões e levam a resultados errados. O DF precisa de tratamento à parte.</li>'
        '<li>As coordenadas da ANP também não são validadas. Parte da distância medida pode ser erro da própria ANP.</li>'
        '</ul></div>'
        '<div class="cartao"><h3>O que o app faz agora</h3><ul>'
        '<li><b>Posição exata</b> (coordenada da ANP, número da casa ou confirmada pela comunidade): pino normal no mapa e envio de preço no raio de 300 m.</li>'
        '<li><b>Rua ou CEP de rua:</b> pino com marcador de localização aproximada. Envio de preço aceito num raio de 1 km.</li>'
        '<li><b>Só CEP da cidade, município ou nada:</b> o posto aparece na busca, mas não no mapa e não recebe envio de preço.</li>'
        '<li><b>Estou neste posto:</b> botão que só corrige a posição, sem limite de distância. Quando duas pessoas diferentes informam pontos a até 150 m um do outro, a posição vira exata e rende 5 pontos a cada uma.</li>'
        '<li><b>Próximo teste:</b> procurar os postos de combustível já mapeados no OpenStreetMap perto da rua encontrada. Pode dar posição exata para parte dos casos de rua.</li>'
        '</ul></div></div>'
    )
    nota = (f'<p style="color: var(--ink-2); font-size: .9rem">Teste rodado em {e(d["gerado_em"][:10].split("-")[2])}/'
            f'{e(d["gerado_em"][5:7])}/{e(d["gerado_em"][:4])}, só lendo o banco: nenhuma posição foi gravada. '
            'Serviços: Nominatim, do OpenStreetMap, com uma consulta por segundo, e BrasilAPI para o CEP. Todo ponto encontrado '
            'precisou cair dentro do município do posto, conferido pela malha do IBGE. A projeção supõe que a amostra represente o total.</p>')
    return lead, numeros + tab_cob + tab_erro + conclusoes + nota


# ------------------------------------------------------------------ auditoria
# Situação: ("ok", texto) corrigido e verificado; ("espera", texto) depende de você; ("prox", texto) decisão ou etapa futura.
CORRIGIDO, CONFIRMADO, NO_PUSH, VOCE, DECISAO = (("ok", "Corrigido"), ("ok", "Corrigido e confirmado"), ("espera", "Publica no push"),
                                                ("espera", "Aguardando você"), ("prox", "Decisão sua"))
BUGS = [
    ("BUG-01", "Alta", "Envios simultâneos furavam a regra de 6 horas: uma única ação rendeu +70 pontos e +0,15 de confiabilidade.",
     "Limite diário, regra de 6 h e gravação passaram para uma única função do banco, com trava por usuário. Pontos e confiabilidade "
     "agora contam uma vez por pessoa em cada consenso.", CONFIRMADO,
     "Reteste no Supabase real: 6 envios simultâneos gravam 1 item; a confirmação rende os pontos de uma ação só."),
    ("BUG-02", "Alta", "Cerca de 180 postos com coordenada errada da ANP: 148 de 21 estados no mesmo ponto do Rio e outros a centenas de km do estado.",
     "A coordenada da ANP só vale dentro do contorno do estado do posto (malha do IBGE, 15 km de tolerância) e fora dos pontos padrão. "
     "Os postos atingidos voltam a 'localização desconhecida' até a comunidade confirmar.", CONFIRMADO,
     "Reteste no Supabase real: 184 postos corrigidos; nenhum fora do próprio estado; Noronha e o oeste do Amazonas continuam válidos."),
    ("BUG-03", "Alta", "Preços da ANP parados em 30/06/2026, sem carga automática.",
     "Carga semanal pela planilha 'revendas_lpc' da ANP, com marcação de anomalias. As 14 semanas que faltavam já foram carregadas "
     "(224 mil preços, coleta mais recente 02/10/2026). Agendamento no GitHub Actions às segundas e quintas.", CONFIRMADO,
     "Reteste: coleta mais recente 02/10/2026. O agendamento já está no GitHub."),
    ("BUG-04", "Média", "O servidor aceitava senhas 'abc123' e 'abcdefgh', que o app recusa.",
     "No painel do Supabase: Authentication, política de senha com mínimo de 8 caracteres, com maiúscula, minúscula, número e símbolo.", VOCE,
     "Reteste: o servidor ainda aceita; falta a mudança no painel."),
    ("BUG-05", "Média", "Qualquer pessoa lia o identificador de quem escreveu cada avaliação e de quem votou.",
     "A coluna de autor deixou de ser pública e cada pessoa vê só os próprios votos. O app continua usando o nome abreviado.",
     CONFIRMADO, "Reteste no Supabase real: visitante recebe 'permissão negada' e não vê votos."),
    ("BUG-06", "Média", "Telas estouravam em celular pequeno (Favoritos e Avaliar em 320 px) e na Busca com fonte de 130%.",
     "Estado vazio com rolagem, estrelas que encolhem, lista de cartões com altura do conteúdo.", CORRIGIDO,
     "304 testes de telas passando. Chega ao celular no próximo APK."),
    ("BUG-07", "Baixa", "Sete telas estouravam com a fonte do sistema em 200%.",
     "Quebra de linha no rodapé de Entrar e Criar conta, legenda e períodos do histórico, preço e selo do posto; pinos do mapa com teto de fonte.",
     CORRIGIDO, "Mesmos 304 testes de telas. Chega ao celular no próximo APK."),
    ("BUG-08", "Baixa", "A autora conseguia votar na própria avaliação chamando a API.",
     "A política de voto do banco passou a recusar o voto na própria avaliação.", CONFIRMADO,
     "Reteste no Supabase real: voto na própria avaliação recusado."),
    ("BUG-09", "Baixa", "A página de regras dizia que um envio nunca altera o preço exibido, mas ele aparece como 'aguardando confirmação'.",
     "Regra reescrita e catálogo atualizado com as regras novas das correções (65 regras).", CONFIRMADO, "Reteste: regra e comportamento iguais."),
    ("BUG-10", "Baixa", "Latência alta: o projeto está nos EUA (us-west-2) e os usuários no Brasil, com picos de até 5 s.",
     "Criar o projeto em São Paulo (sa-east-1) antes do lançamento e migrar os dados.", DECISAO, "Exige um projeto novo no Supabase."),
    ("BUG-11", "Média", "Achado no reteste: com o servidor gratuito ocupado, a consulta do mapa pode passar do limite de 3 s e o app mostra erro.",
     "O app repete sozinho, uma vez, a leitura que falhar por tempo esgotado (só leituras, para nunca gravar duas vezes).", NO_PUSH,
     "3 testes novos no app. Ao vivo, depende também do BUG-10."),
]


def auditoria() -> str:
    linhas = "".join(
        f'<tr><td><b>{e(i)}</b><br><span class="sev">{e(s)}</span></td><td>{e(antes)}</td><td>{e(corr)}</td>'
        f'<td class="e"><span class="estado {c}">{e(r)}</span><br><span class="nota-sit">{e(nota)}</span></td></tr>'
        for i, s, antes, corr, (c, r), nota in BUGS)
    return ('<div class="tabela"><table class="auditoria"><thead><tr><th>Bug</th><th>O que acontecia</th><th>Correção</th>'
            f'<th>Situação</th></tr></thead><tbody>{linhas}</tbody></table></div>')


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
    geo_lead, geo = geocodificacao()
    saida = saida.replace("{{GEO_LEAD}}", e(geo_lead)).replace("{{GEOCODIFICACAO}}", geo)
    saida = (saida.replace("{{ETAPAS}}", etapas()).replace("{{AUDITORIA}}", auditoria())
             .replace("{{DATA}}", date.today().strftime("%d/%m/%Y"))
             .replace("{{COMMIT}}", commit))
    destino = RAIZ / "documentacao" / "andamento.html"
    destino.write_text(saida, encoding="utf-8")
    print(f"{destino} gerado ({destino.stat().st_size / 1024:.0f} KB), commit {commit}")


if __name__ == "__main__":
    main()
