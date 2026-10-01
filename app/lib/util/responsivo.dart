import 'package:flutter/widgets.dart';

/// Pontos de quebra do layout: celular, tablet em retrato e tablet em paisagem.
enum Tamanho { compacto, medio, expandido }

Tamanho tamanhoDe(BuildContext context) {
  final largura = MediaQuery.sizeOf(context).width;
  if (largura >= 840) return Tamanho.expandido;
  if (largura >= 600) return Tamanho.medio;
  return Tamanho.compacto;
}

bool ehTablet(BuildContext context) => tamanhoDe(context) != Tamanho.compacto;

/// Limita a largura do conteúdo em telas grandes para manter a leitura confortável.
class LarguraMaxima extends StatelessWidget {
  final Widget child;
  final double maxima;
  const LarguraMaxima({super.key, required this.child, this.maxima = 720});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxima), child: child),
      );
}
