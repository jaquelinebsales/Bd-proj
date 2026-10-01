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

    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Text(t, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        );
    Widget item(IconData i, Color c, String t, String s) =>
        ListTile(leading: Icon(i, color: c), title: Text(t), subtitle: Text(s));

    return Scaffold(
      appBar: AppBar(title: const Text('Sobre os dados e privacidade')),
      body: LarguraMaxima(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          titulo('De onde vêm os preços'),
          Card(
            child: Column(children: [
              item(Icons.groups_rounded, cs.primary, 'Comunidade',
                  'Fotos de painéis enviadas por usuários. Um preço é confirmado quando duas pessoas diferentes informam o mesmo valor em até 24 horas.'),
              item(Icons.account_balance_outlined, Tema.anp, 'Pesquisa da ANP',
                  'Levantamento semanal oficial da Agência Nacional do Petróleo. É uma amostra: cobre cerca de 20% dos postos e pouco mais de 400 cidades. Vale quando os envios da comunidade divergem.'),
              item(Icons.insights_outlined, Tema.estimativa, 'Estimativa',
                  'Quando o posto não tem nenhum preço, mostramos a mediana dos postos pesquisados mais próximos, com a margem de erro medida para aquela distância.'),
            ]),
          ),
          titulo('O que as cores significam'),
          Card(
            child: Column(children: [
              item(Icons.circle, Tema.recente, 'Atualizado recentemente', 'Até 24 horas.'),
              item(Icons.circle, Tema.antigo, 'Atualização antiga', 'De 2 a 7 dias.'),
              item(Icons.circle, Tema.semAtualizacao, 'Sem atualização recente', 'Mais de 7 dias, ou preço estimado.'),
            ]),
          ),
          titulo('Cadastro dos postos'),
          Text(
            'Nome, endereço, bandeira, localização e combustíveis vendidos vêm do cadastro oficial de revendedores da ANP, '
            'atualizado toda semana. As avaliações e comentários são 100% dos usuários.',
            style: tt.bodyLarge,
          ),
          titulo('Privacidade'),
          Card(
            child: Column(children: [
              item(Icons.no_photography_outlined, cs.primary, 'A foto do painel não sai do seu celular',
                  'O texto é lido no próprio aparelho e a foto é apagada em seguida. Guardamos só os valores que você confirmou e o texto reconhecido.'),
              item(Icons.place_outlined, cs.primary, 'Localização',
                  'Usada para mostrar postos próximos. Ao enviar preços, registramos a posição daquele momento para confirmar que você estava no posto.'),
              item(Icons.badge_outlined, cs.primary, 'Dados da conta',
                  'Nome, e-mail e foto de perfil opcional. Outras pessoas veem só o seu nome abreviado, por exemplo "Carla M.".'),
              item(Icons.delete_outline, cs.primary, 'Exclusão da conta',
                  'Você pode excluir a conta no perfil. Apagamos perfil, avaliações, favoritos e pontos; os preços enviados ficam no histórico sem o seu nome.'),
            ]),
          ),
          titulo('Termos de uso'),
          Text(
            'Envie apenas preços que você viu no painel do posto, estando no local. Envios falsos são contrariados pela '
            'comunidade, tiram pontos e podem pausar sua conta. Os preços exibidos são informativos: confira o valor na bomba '
            'antes de abastecer.',
            style: tt.bodyLarge,
          ),
          const SizedBox(height: 24),
          Center(child: Text('gasprice ${Config.versao}', style: tt.bodySmall)),
        ]),
      ),
    );
  }
}
