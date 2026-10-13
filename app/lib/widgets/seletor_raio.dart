import 'package:flutter/material.dart';

import '../servicos/preferencias.dart';

String textoRaio(double? km) => km == null ? 'Qualquer' : '${km.toStringAsFixed(0)} km';

/// Dropdown compacto para limitar os postos a uma distância do usuário.
class SeletorRaio extends StatelessWidget {
  const SeletorRaio({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double?>(
      valueListenable: Preferencias.raioKm,
      builder: (context, raio, _) => PopupMenuButton<double>(
        tooltip: 'Distância dos postos',
        initialValue: raio ?? 0,
        onSelected: (v) => Preferencias.raioKm.value = v == 0 ? null : v,
        itemBuilder: (_) => [
          for (final v in [0.0, ...Preferencias.raios])
            PopupMenuItem(
              value: v,
              child: Row(children: [
                if ((raio ?? 0) == v)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.check, size: 18, color: cs.primary),
                  )
                else
                  const SizedBox(width: 26),
                Text(v == 0 ? 'Qualquer distância' : 'Até ${v.toStringAsFixed(0)} km'),
              ]),
            ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Center(
            widthFactor: 1,
            child: Material(
              elevation: 2,
              color: raio == null ? cs.surface : cs.secondaryContainer,
              shape: StadiumBorder(side: BorderSide(color: cs.outlineVariant)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.radar, size: 18, color: raio == null ? cs.onSurfaceVariant : cs.onSecondaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    textoRaio(raio),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: raio == null ? cs.onSurface : cs.onSecondaryContainer,
                        ),
                  ),
                  Icon(Icons.arrow_drop_down, color: raio == null ? cs.onSurfaceVariant : cs.onSecondaryContainer),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
