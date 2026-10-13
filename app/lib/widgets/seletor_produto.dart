import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicos/preferencias.dart';

/// Dropdown compacto para escolher o combustível exibido. Estilo de pill com ícone, como o seletor de raio.
class SeletorProduto extends StatelessWidget {
  const SeletorProduto({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: Preferencias.produto,
      builder: (context, atual, _) {
        final nome = Produto.porId(atual).nome;
        return PopupMenuButton<int>(
          tooltip: 'Combustível',
          initialValue: atual,
          onSelected: (v) => Preferencias.produto.value = v,
          itemBuilder: (_) => [
            for (final p in Produto.todos)
              PopupMenuItem(
                value: p.id,
                child: Row(children: [
                  if (p.id == atual)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.check, size: 18, color: cs.primary),
                    )
                  else
                    const SizedBox(width: 26),
                  Text(p.nome),
                ]),
              ),
          ],
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Center(
              widthFactor: 1,
              child: Material(
                elevation: 2,
                color: cs.secondaryContainer,
                shape: StadiumBorder(side: BorderSide(color: cs.outlineVariant)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.local_gas_station, size: 18, color: cs.onSecondaryContainer),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        nome,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.onSecondaryContainer),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, color: cs.onSecondaryContainer),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
