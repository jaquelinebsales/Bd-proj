import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicos/preferencias.dart';

/// Chips horizontais para escolher o combustível exibido.
class SeletorProduto extends StatelessWidget {
  final bool sobreMapa;
  const SeletorProduto({super.key, this.sobreMapa = false});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: Preferencias.produto,
        builder: (context, atual, _) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final p in Produto.todos)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(p.nome),
                  selected: p.id == atual,
                  onSelected: (_) => Preferencias.produto.value = p.id,
                  elevation: sobreMapa ? 2 : 0,
                  backgroundColor: sobreMapa ? Theme.of(context).colorScheme.surface : null,
                ),
              ),
          ]),
        ),
      );
}
