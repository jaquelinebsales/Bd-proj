import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Volta para a página do posto. Aberta por um link direto, a tela não tem para onde voltar: aí abre o posto
/// (sem isso o app ficava com a tela vazia).
void voltarAoPosto(BuildContext context, int postoId, [Object? resultado]) {
  if (context.canPop()) {
    context.pop(resultado);
  } else {
    context.go('/posto/$postoId');
  }
}

/// Pontos de quebra do layout: celular, tablet em retrato e tablet em paisagem.
enum Tamanho { compacto, medio, expandido }

Tamanho tamanhoDe(BuildContext context) {
  final largura = MediaQuery.sizeOf(context).width;
  if (largura >= 840) return Tamanho.expandido;
  if (largura >= 600) return Tamanho.medio;
  return Tamanho.compacto;
}

bool ehTablet(BuildContext context) => tamanhoDe(context) != Tamanho.compacto;

/// Colunas das listas de cartões: uma no celular, duas no tablet em retrato e três em paisagem.
int colunasDeCartoes(BuildContext context) => switch (tamanhoDe(context)) {
      Tamanho.compacto => 1,
      Tamanho.medio => 2,
      Tamanho.expandido => 3,
    };

/// Largura máxima das listas de cartões: no tablet em paisagem elas ocupam a tela, sem faixas vazias nas laterais.
const larguraListas = 1400.0;

/// Lista de cartões em colunas. Cada linha tem a altura do cartão mais alto dela (o conteúdo decide, também com a
/// fonte do sistema ampliada), sem espaço sobrando dentro dos cartões.
class GradeDeCartoes extends StatelessWidget {
  final int colunas;
  final EdgeInsets padding;
  final int quantidade;
  final Widget Function(BuildContext, int) cartao;
  const GradeDeCartoes({
    super.key,
    required this.colunas,
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
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      itemCount: (quantidade / colunas).ceil(),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, linha) => _linha(colunas, [
        for (var c = 0; c < colunas && linha * colunas + c < quantidade; c++) cartao(context, linha * colunas + c),
      ]),
    );
  }
}

/// Uma linha de cartões com a altura do mais alto; colunas sem cartão ficam vazias (a última linha não estica)
Widget _linha(int colunas, List<Widget> cartoes, {double espaco = 8}) => IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var c = 0; c < colunas; c++) ...[
          if (c > 0) SizedBox(width: espaco),
          Expanded(child: c < cartoes.length ? cartoes[c] : const SizedBox.shrink()),
        ],
      ]),
    );

/// Os mesmos cartões em linhas de [colunas], para usar dentro de uma lista que já rola.
class LinhasDeCartoes extends StatelessWidget {
  final int colunas;
  final List<Widget> cartoes;
  final double espaco;
  const LinhasDeCartoes({super.key, required this.colunas, required this.cartoes, this.espaco = 8});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < cartoes.length; i += colunas) ...[
          if (i > 0) SizedBox(height: espaco),
          _linha(colunas, cartoes.sublist(i, (i + colunas).clamp(0, cartoes.length)), espaco: espaco),
        ],
      ]);
}

/// Página que rola em duas colunas no tablet em paisagem e numa só (a esquerda e depois a direita) no celular e
/// no tablet em retrato. Assim a tela larga não fica com uma coluna estreita no meio e faixas vazias dos lados.
class ColunasAdaptaveis extends StatelessWidget {
  final List<Widget> esquerda;
  final List<Widget> direita;
  final EdgeInsets padding;
  final int flexEsquerda;
  final int flexDireita;
  final double maximaUmaColuna;
  const ColunasAdaptaveis({
    super.key,
    required this.esquerda,
    required this.direita,
    this.padding = const EdgeInsets.all(16),
    this.flexEsquerda = 1,
    this.flexDireita = 1,
    this.maximaUmaColuna = 720,
  });

  @override
  Widget build(BuildContext context) {
    if (tamanhoDe(context) != Tamanho.expandido) {
      return LarguraMaxima(
        maxima: maximaUmaColuna,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          children: [...esquerda, ...direita],
        ),
      );
    }
    return LarguraMaxima(
      maxima: larguraListas,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: padding, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: flexEsquerda, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: esquerda)),
          const SizedBox(width: 24),
          Expanded(flex: flexDireita, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: direita)),
        ]),
      ]),
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
