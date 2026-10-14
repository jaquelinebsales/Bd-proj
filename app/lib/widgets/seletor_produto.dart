import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../servicos/preferencias.dart';

/// Dropdown compacto para escolher um ou mais combustíveis. Menu fica aberto até clicar novamente.
/// Toque num item para selecionar/desmarcar. Pelo menos um combustível fica sempre selecionado.
class SeletorProduto extends StatefulWidget {
  const SeletorProduto({super.key});

  @override
  State<SeletorProduto> createState() => _SeletorProdutoState();
}

class _SeletorProdutoState extends State<SeletorProduto> {
  bool _menuAberto = false;

  void _alternarItem(int id) {
    final set = Set<int>.from(Preferencias.produto.value);
    if (set.contains(id)) {
      if (set.length > 1) set.remove(id);
    } else {
      set.add(id);
    }
    Preferencias.produto.value = set;
  }

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

        return GestureDetector(
          onTap: () {
            if (_menuAberto) {
              setState(() => _menuAberto = false);
            } else {
              _abrirMenu(context, selecionados, cs);
            }
          },
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
                    Icon(
                      _menuAberto ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      color: multi ? cs.onPrimaryContainer : cs.onSecondaryContainer,
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _abrirMenu(BuildContext context, Set<int> selecionados, ColorScheme cs) async {
    setState(() => _menuAberto = true);
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final tamanho = renderBox.size;

    await showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + tamanho.height + 8,
        offset.dx + tamanho.width,
        0,
      ),
      items: [
        for (final p in Produto.todos)
          PopupMenuItem(
            onTap: () => _alternarItem(p.id),
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
    );
    if (mounted) setState(() => _menuAberto = false);
  }
}
