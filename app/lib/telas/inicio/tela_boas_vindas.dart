import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../servicos/localizacao.dart';
import '../../util/responsivo.dart';

/// Primeira abertura: explica as fontes de preço e pede a localização.
class TelaBoasVindas extends StatefulWidget {
  const TelaBoasVindas({super.key});
  @override
  State<TelaBoasVindas> createState() => _TelaBoasVindasState();
}

class _TelaBoasVindasState extends State<TelaBoasVindas> {
  final _paginas = PageController();
  int _pagina = 0;

  static const _conteudo = [
    (Icons.local_gas_station_rounded, 'Preço de combustível perto de você',
        'Veja o preço da gasolina, do etanol, do diesel e do GNV nos postos do mapa, sem precisar criar conta.'),
    (Icons.photo_camera_outlined, 'Uma foto atualiza para todos',
        'Fotografe o painel do posto. O app lê os preços no seu celular, você confere e envia. A foto não sai do aparelho.'),
    (Icons.verified_outlined, 'Você sabe de onde vem cada preço',
        'Cada valor mostra se veio da pesquisa oficial da ANP, da comunidade ou de uma estimativa, e há quanto tempo.'),
  ];

  Future<void> _concluir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('viu_boas_vindas', true);
    await Localizacao.instancia.obter();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final ultima = _pagina == _conteudo.length - 1;
    return Scaffold(
      body: SafeArea(
        child: LarguraMaxima(
          maxima: 560,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _concluir, child: const Text('Pular')),
              ),
              Expanded(
                child: PageView(
                  controller: _paginas,
                  onPageChanged: (i) => setState(() => _pagina = i),
                  children: [
                    for (final (icone, titulo, texto) in _conteudo)
                      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        CircleAvatar(
                          radius: 56,
                          backgroundColor: cs.primaryContainer,
                          child: Icon(icone, size: 56, color: cs.onPrimaryContainer),
                        ),
                        const SizedBox(height: 32),
                        Text(titulo, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        Text(texto, style: tt.bodyLarge, textAlign: TextAlign.center),
                      ]),
                  ],
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < _conteudo.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(4),
                    width: i == _pagina ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _pagina ? cs.primary : cs.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ]),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: ultima
                    ? _concluir
                    : () => _paginas.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Text(ultima ? 'Permitir localização e começar' : 'Continuar'),
              ),
              if (ultima)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Sem localização, você ainda pode buscar postos por cidade ou endereço.',
                      style: tt.bodySmall, textAlign: TextAlign.center),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
