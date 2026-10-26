import 'package:flutter/material.dart';

import '../../config.dart';
import '../../tema.dart';
import '../../util/responsivo.dart';

/// Origem dos dados, significado das cores, privacidade e termos de uso.
class TelaSobre extends StatelessWidget {
  const TelaSobre({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final cores = Tema.cores(context);

    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Text(t, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        );
    Widget item(IconData i, Color c, String t, String s) =>
        ListTile(leading: Icon(i, color: c), title: Text(t), subtitle: Text(s));

    return Scaffold(
      appBar: AppBar(title: const Text('Sobre os dados e privacidade')),
      body: ColunasAdaptaveis(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        esquerda: [
          titulo('De onde vêm os preços'),
          Card(
            child: Column(children: [
              item(Icons.groups_rounded, cs.primary, 'Comunidade',
                  'Fotos de painéis enviadas por usuários. Um preço é confirmado quando duas pessoas diferentes informam o mesmo valor em até 24 horas.'),
              item(Icons.account_balance_outlined, cores.anp, 'Pesquisa da ANP',
                  'Levantamento semanal da Agência Nacional do Petróleo. O valor da pesquisa aparece quando os envios da comunidade são divergentes ou quando o posto ainda não tem envio recente.'),
              item(Icons.insights_outlined, cores.estimativa, 'Estimativa',
                  'Quando o posto ainda não tem preço informado, o valor é calculado a partir dos postos pesquisados mais próximos.'),
            ]),
          ),
          titulo('O que as cores significam'),
          Card(
            child: Column(children: [
              item(Icons.circle, cores.recente, 'Atualizado recentemente', 'Até 24 horas. No mapa, pino verde.'),
              item(Icons.circle, cores.antigo, 'Atualização antiga', 'De 2 a 7 dias. No mapa, pino âmbar.'),
              item(Icons.circle, cores.semAtualizacao, 'Sem atualização recente',
                  'Mais de 7 dias, ou preço estimado. No mapa, pino com contorno vermelho.'),
              item(Icons.circle_outlined, cores.estimativa, 'Estimativa no mapa',
                  'Pino com contorno tracejado e o sinal ≈ antes do preço.'),
              item(Icons.circle_outlined, cores.semPreco, 'Posto sem preço', 'Pino com contorno cinza e um traço no lugar do preço.'),
            ]),
          ),
        ],
        direita: [
          titulo('Cadastro dos postos'),
          Text(
            'Nome, endereço, bandeira, localização e combustíveis vendidos vêm do cadastro oficial de revendedores da ANP, '
            'atualizado toda semana. As avaliações e comentários são 100% dos usuários.',
            style: tt.bodyLarge,
          ),
          titulo('Privacidade'),
          Card(
            child: Column(children: [
              item(Icons.photo_camera_outlined, cs.primary, 'Foto do painel',
                  'A foto é lida no seu celular e apagada logo depois: ela nunca é enviada. Vão para o servidor os '
                  'preços que você conferiu e o texto reconhecido no painel, usado para corrigir erros de leitura.'),
              item(Icons.place_outlined, cs.primary, 'Localização',
                  'Usada para mostrar postos próximos. Ao enviar preços, registramos a posição daquele momento para confirmar que você estava no posto.'),
              item(Icons.badge_outlined, cs.primary, 'Dados da conta',
                  'Nome e e-mail. Sobrenome, gênero, data de nascimento e foto de perfil são opcionais. Outras pessoas '
                  'veem só o seu nome abreviado, por exemplo "Carla M.".'),
              item(Icons.delete_outline, cs.primary, 'Exclusão da conta',
                  'Você pode excluir a conta no perfil. Apagamos perfil, avaliações, favoritos e pontos; os preços enviados ficam no histórico sem o seu nome.'),
            ]),
          ),
          titulo('Termos de uso'),
          Text(
            'Envie apenas preços que você viu no painel do posto, estando no local. Envios falsos são contrariados pela '
            'comunidade, tiram pontos e podem pausar sua conta. O valor cobrado é sempre o da bomba no momento do abastecimento.',
            style: tt.bodyLarge,
          ),
          const SizedBox(height: 24),
          Center(child: Text('gasprice ${Config.versao}', style: tt.bodySmall)),
        ],
      ),
    );
  }
}
