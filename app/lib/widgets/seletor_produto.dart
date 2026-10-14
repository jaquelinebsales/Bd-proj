import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../modelos/modelos.dart';
import '../servicos/preferencias.dart';

/// Dropdown compacto para escolher um ou mais combustíveis. A lista abre abaixo do botão e continua
/// aberta enquanto o usuário marca itens; fecha ao tocar no botão de novo ou fora da lista.
/// Pelo menos um combustível fica sempre selecionado.
class SeletorProduto extends StatefulWidget {
  const SeletorProduto({super.key});

  @override
  State<SeletorProduto> createState() => _SeletorProdutoState();
}

class _SeletorProdutoState extends State<SeletorProduto> {
  final _portal = OverlayPortalController();
  final _ancora = LayerLink();

  void _alternarMenu() => _portal.isShowing ? _portal.hide() : _portal.show();

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
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (_) => _menu(cs),
      child: CompositedTransformTarget(
        link: _ancora,
        child: ValueListenableBuilder<Set<int>>(
          valueListenable: Preferencias.produto,
          builder: (context, selecionados, _) {
            final multi = selecionados.length > 1;
            final fg = multi ? cs.onPrimaryContainer : cs.onSecondaryContainer;
            final rotulo = multi
                ? '${selecionados.length} combustíveis'
                : Produto.porId(selecionados.isEmpty ? 1 : selecionados.first).nome;
            return Semantics(
              button: true,
              label: 'Combustível: $rotulo',
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Center(
                  widthFactor: 1,
                  child: Material(
                    elevation: 2,
                    color: multi ? cs.primaryContainer : cs.secondaryContainer,
                    shape: StadiumBorder(side: BorderSide(color: cs.outlineVariant)),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: _alternarMenu,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.local_gas_station, size: 18, color: fg),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              rotulo,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: fg),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _menu(ColorScheme cs) {
    return Stack(children: [
      // Toque fora da lista fecha
      Positioned.fill(
        child: PointerInterceptor(
          intercepting: kIsWeb,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _portal.hide,
            child: const SizedBox.expand(),
          ),
        ),
      ),
      CompositedTransformFollower(
        link: _ancora,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 6),
        child: Align(
          alignment: Alignment.topLeft,
          child: PointerInterceptor(
            intercepting: kIsWeb,
            child: Material(
              elevation: 8,
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: IntrinsicWidth(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 200),
                  child: ValueListenableBuilder<Set<int>>(
                    valueListenable: Preferencias.produto,
                    builder: (context, selecionados, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final p in Produto.todos)
                          InkWell(
                            onTap: () => _alternarItem(p.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
