"""
Casos que só rodam num aparelho Android real (ou emulador do Android Studio): câmera, GPS, permissões,
links de e-mail, notificações, leitor de tela. Entram na matriz como NOT TESTED, com os passos para executar.

Uso: python scripts/auditoria/t_android.py
"""
from __future__ import annotations

import sys

from comum import ALTA, BAIXA, CRITICA, MEDIA, NOT_TESTED, Suite

MOTIVO = ("Não executado nesta auditoria: exige aparelho Android ou emulador (este computador não tem o Android SDK). "
          "Executar no Android Studio e preencher 'Resultado Obtido' e 'Status'.")

CASOS = [
    # (módulo, tela, tipo, cenário, pré-condições, passos, entrada, esperado, severidade)
    ("Instalação", "-", "Instalação", "APK de teste instala e abre sem fechar sozinho", "APK do GitHub Actions; Android 8 ou mais novo",
     "Instalar o app-release.apk; abrir", "-", "Abre a tela de boas-vindas em até 5 s", CRITICA),
    ("Instalação", "-", "Performance · inicialização", "Tempo de abertura a frio", "App fechado e fora da memória",
     "Fechar o app nas recentes; abrir cronometrando", "-", "Mapa visível em até 4 s em aparelho intermediário", MEDIA),
    ("Boas-vindas", "Boas-vindas", "Permissão", "Pedido de localização na primeira abertura", "Primeira abertura",
     "Tocar em Continuar até o pedido de localização; permitir", "Permitir durante o uso", "Mapa centraliza na posição do aparelho", ALTA),
    ("Boas-vindas", "Mapa", "Permissão · negativa", "Localização negada", "Primeira abertura",
     "Negar a localização", "Negar", "Mapa abre numa região padrão com aviso, sem travar; busca funciona", ALTA),
    ("Mapa", "Mapa", "Funcional · positivo", "Pinos de preço perto do aparelho", "Localização permitida, internet ligada",
     "Abrir o mapa; aproximar e afastar com os dedos", "-", "Pinos aparecem em até 5 s; movimento fluido", ALTA),
    ("Mapa", "Mapa", "Funcional · positivo", "Tocar num pino abre o cartão do posto", "Pinos visíveis", "Tocar num pino",
     "-", "Cartão com nome, preço e botões Atualizar preço e Ver posto", MEDIA),
    ("Posto", "Posto", "Integração · app externo", "Como chegar abre o Google Maps com a rota", "Google Maps instalado",
     "Abrir um posto; tocar em Como chegar", "-", "Google Maps abre com destino no posto", MEDIA),
    ("Envio por foto", "Enviar preços", "Permissão", "Pedido de permissão da câmera", "Logado, a até 300 m do posto",
     "Posto → Atualizar preço → Fotografar", "-", "Android pede a câmera; ao permitir, a câmera abre", CRITICA),
    ("Envio por foto", "Enviar preços", "Funcional · positivo", "Leitura de painel real com 4 combustíveis",
     "Logado, no posto, painel visível", "Fotografar o painel de frente; conferir os valores lidos",
     "foto real", "Os valores lidos batem com o painel; o usuário só confirma", CRITICA),
    ("Envio por foto", "Enviar preços", "Funcional · negativo", "Foto ruim (reflexo, de lado ou sem painel)", "Logado, no posto",
     "Fotografar uma parede ou o painel com reflexo", "foto ruim", "App avisa que não leu os preços e deixa digitar ou fotografar de novo", ALTA),
    ("Envio por foto", "Enviar preços", "Privacidade", "A foto não fica na galeria nem na pasta do app",
     "Envio feito", "Conferir a Galeria e Arquivos → Android/data/br.com.gasprice.gasprice", "-",
     "Nenhuma foto do painel guardada no aparelho", CRITICA),
    ("Envio por foto", "Enviar preços", "Regra de negócio · raio", "Envio longe do posto é recusado com a distância",
     "Logado, a mais de 300 m de um posto com posição exata", "Tentar enviar", "-", "Mensagem com a distância atual e o limite de 300 m", ALTA),
    ("Envio por foto", "Enviar preços", "Funcional · positivo", "Envio completo e confirmação por uma segunda pessoa",
     "Duas contas em dois aparelhos, no mesmo posto", "As duas enviam o mesmo preço", "mesmo valor",
     "Preço confirmado; as duas contas ganham pontos", CRITICA),
    ("Estou neste posto", "Estou neste posto", "Funcional · positivo", "Informar a posição de um posto aproximado",
     "Logado, dentro de um posto com aviso de localização aproximada", "Posto → Estou neste posto → Informar",
     "GPS com precisão até 100 m", "Mensagem de obrigado; posição aguardando outra pessoa", ALTA),
    ("Estou neste posto", "Estou neste posto", "Funcional · negativo", "GPS impreciso (dentro de prédio)", "Logado, em local fechado",
     "Tentar informar a posição", "-", "Aviso de GPS impreciso; nada é gravado", MEDIA),
    ("Conta", "Criar conta", "Integração · e-mail", "E-mail de confirmação chega e o link abre o app",
     "E-mail pessoal que não seja o do dono do projeto no Supabase", "Criar conta; abrir o e-mail no mesmo celular; tocar no link",
     "e-mail real", "E-mail chega em minutos; o link abre o app já logado", CRITICA),
    ("Conta", "Recuperar senha", "Integração · e-mail", "Link de recuperação abre a tela Nova senha", "Conta existente",
     "Recuperar senha; abrir o link no celular; criar a nova senha", "-", "App abre em Nova senha; a senha nova entra", ALTA),
    ("Conta", "Perfil", "Funcional · positivo", "Foto de perfil pela galeria", "Logado", "Alterar dados → foto → escolher imagem",
     "imagem de até 200 KB", "Foto aparece no perfil", BAIXA),
    ("Conta", "Perfil", "Funcional · positivo", "Excluir a conta pelo app", "Conta de teste descartável",
     "Perfil → Excluir conta → confirmar", "-", "Volta para visitante; o login antigo não entra mais", ALTA),
    ("Avisos de preço", "Notificações", "Permissão", "Pedido de permissão de notificação (Android 13+)", "Logado, Android 13 ou mais novo",
     "Ativar avisos de preço", "-", "Android pede a permissão de notificações", MEDIA),
    ("Avisos de preço", "Notificações", "Funcional · positivo", "Aviso com o app em segundo plano", "Posto favoritado; app em segundo plano",
     "Outra conta confirma um preço R$ 0,05 diferente", "-", "Notificação do sistema com o preço novo", MEDIA),
    ("Avisos de preço", "Notificações", "Funcional · limitação conhecida", "Aviso com o app fechado", "App fechado",
     "Mesma ação do caso anterior com o app fechado", "-", "Sem notificação (depende do Firebase); aviso aparece na lista ao abrir", BAIXA),
    ("Navegação", "-", "Funcional · navegação", "Botão voltar do Android em cada tela", "-",
     "Navegar Mapa → Posto → Histórico e voltar com o botão do sistema", "-", "Volta tela a tela; na raiz, sai do app", MEDIA),
    ("Navegação", "-", "Responsividade", "Girar a tela no celular e no tablet", "-", "Girar com o posto aberto", "-",
     "Layout se ajusta sem perder o que estava na tela", MEDIA),
    ("Acessibilidade", "-", "Acessibilidade · leitor de tela", "Navegação com o TalkBack", "TalkBack ligado",
     "Percorrer Mapa, Busca e Posto com gestos do TalkBack", "-", "Cada botão e preço é lido com nome claro", MEDIA),
    ("Acessibilidade", "-", "Acessibilidade · fonte", "Fonte do sistema no maior tamanho", "Configurações → Tamanho da fonte no máximo",
     "Abrir as telas principais", "-", "Textos legíveis sem cortes (comparar com a aba UI/Telas, fonte 200%)", MEDIA),
    ("Aparência", "-", "UI · tema", "Tema escuro do sistema", "Tema escuro ligado", "Abrir as telas principais", "-",
     "Cores legíveis em todas as telas", BAIXA),
    ("Confiabilidade", "-", "Falha de rede", "Abrir o app sem internet", "Modo avião", "Abrir o app", "-",
     "Mensagem de sem conexão e dados em cache, sem tela branca", ALTA),
    ("Confiabilidade", "-", "Falha de rede", "Internet cai durante o envio de preço", "Logado, no posto",
     "Revisar os preços; ligar o modo avião; tocar em Enviar", "-", "Mensagem de erro; nada fica pela metade; dá para tentar de novo", ALTA),
    ("Performance", "-", "Performance · bateria e dados", "Uso de dados e bateria em 10 minutos de mapa", "Wi-Fi desligado",
     "Navegar pelo mapa por 10 minutos", "-", "Consumo compatível com apps de mapa (registrar MB e % de bateria)", BAIXA),
]


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    s = Suite("android", "D")
    for mod, tela, tipo, cen, pre, passos, entrada, esp, sev in CASOS:
        s.add(status=NOT_TESTED, aba="Android (manual)", modulo=mod, tela=tela, tipo=tipo, cenario=cen, precondicoes=pre,
              passos=passos, entrada=entrada, esperado=esp, obtido="", severidade=sev, obs=MOTIVO)
    s.salvar()
    return 0


if __name__ == "__main__":
    sys.exit(main())
