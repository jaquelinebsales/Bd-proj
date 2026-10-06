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

/// Lista de cartões que respeita a fonte do sistema. Numa coluna (celular) cada cartão tem a altura do
/// próprio conteúdo; em duas colunas (tablet) a grade usa a altura base ampliada pela escala da fonte.
class GradeDeCartoes extends StatelessWidget {
  final int colunas;
  final double alturaBase;
  final EdgeInsets padding;
  final int quantidade;
  final Widget Function(BuildContext, int) cartao;
  const GradeDeCartoes({
    super.key,
    required this.colunas,
    required this.alturaBase,
    required this.padding,
    required this.quantidade,
    required this.cartao,
  });

  @override
  Widget build(BuildContext context) {
    if (colunas == 1) {
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        itemCount: quantidade,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: cartao,
      );
    }
    final escala = MediaQuery.textScalerOf(context).scale(100) / 100;
    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: colunas,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: escala <= 1 ? alturaBase : alturaBase * escala * 1.15,
      ),
      itemCount: quantidade,
      itemBuilder: cartao,
    );
  }
}

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
