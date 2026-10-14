import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicos/preferencias.dart';

/// Dropdown compacto para escolher um ou mais combustíveis. Toque num item para selecionar/desmarcar.
/// Pelo menos um combustível fica sempre selecionado.
class SeletorProduto extends StatelessWidget {
  const SeletorProduto({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Set<int>>(
      valueListenable: Preferencias.produto,
      builder: (context, selecionados, _) {
        final multi = selecionados.length > 1;
        final rotulo = multi
            ? '${selecionados.length} combustíveis'
            : Produto.porId(selecionados.isEmpty ? 1 : selecionados.first).nome;
        return PopupMenuButton<int>(
          tooltip: 'Combustível',
          onSelected: (v) {
            final set = Set<int>.from(Preferencias.produto.value);
            if (set.contains(v)) {
              if (set.length > 1) set.remove(v);
            } else {
              set.add(v);
            }
            Preferencias.produto.value = set;
          },
          itemBuilder: (_) => [
            for (final p in Produto.todos)
              PopupMenuItem(
                value: p.id,
                child: Row(children: [
                  Icon(
                    selecionados.contains(p.id) ? Icons.circle : Icons.circle_outlined,
                    size: 14,
                    color: selecionados.contains(p.id) ? cs.primary : cs.outlineVariant,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    p.nome,
                    style: TextStyle(
                      color: selecionados.contains(p.id) ? cs.primary : cs.onSurface,
                      fontWeight: selecionados.contains(p.id) ? FontWeight.w600 : null,
                    ),
                  ),
                ]),
              ),
          ],
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Center(
              widthFactor: 1,
              child: Material(
                elevation: 2,
                color: multi ? cs.primaryContainer : cs.secondaryContainer,
                shape: StadiumBorder(side: BorderSide(color: cs.outlineVariant)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.local_gas_station, size: 18,
                        color: multi ? cs.onPrimaryContainer : cs.onSecondaryContainer),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        rotulo,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: multi ? cs.onPrimaryContainer : cs.onSecondaryContainer,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.arrow_drop_down,
                        color: multi ? cs.onPrimaryContainer : cs.onSecondaryContainer),
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
