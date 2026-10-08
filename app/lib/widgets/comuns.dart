import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../modelos/modelos.dart';
import '../servicos/api.dart';
import '../servicos/sessao.dart';
import '../tema.dart';
import '../util/formatos.dart';

class Estrelas extends StatelessWidget {
  final double nota;
  final double tamanho;
  const Estrelas(this.nota, {super.key, this.tamanho = 16});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              nota >= i ? Icons.star_rounded : (nota >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
              size: tamanho,
              color: const Color(0xFFE0A100),
            ),
        ],
      );
}

class NotaCompacta extends StatelessWidget {
  final double? nota;
  final int total;
  const NotaCompacta(this.nota, this.total, {super.key});

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodyMedium;
    if (nota == null || total == 0) {
      return Text('Sem avaliações', style: estilo?.copyWith(color: Theme.of(context).colorScheme.outline));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 18, color: Color(0xFFE0A100)),
      const SizedBox(width: 2),
      Text(nota!.toStringAsFixed(1).replaceAll('.', ','), style: estilo?.copyWith(fontWeight: FontWeight.w700)),
      Text(' ($total)', style: estilo?.copyWith(color: Theme.of(context).colorScheme.outline)),
    ]);
  }
}

class PontoFrescor extends StatelessWidget {
  final Frescor frescor;
  const PontoFrescor(this.frescor, {super.key});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: textoFrescor(frescor),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: corFrescor(frescor, Tema.cores(context)), shape: BoxShape.circle),
        ),
      );
}

/// Selo da origem, só com ícone: ANP, comunidade (confirmado ou aguardando) ou estimativa.
/// Os detalhes (quantas pessoas confirmaram, semana da pesquisa, erro médio) ficam no painel que abre ao tocar no preço.
class SeloFonte extends StatelessWidget {
  final PrecoAtual preco;
  const SeloFonte(this.preco, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cores = Tema.cores(context);
    final confirmado = preco.situacao == SituacaoPreco.confirmado;
    final (icone, cor, descricao) = switch (preco.fonte) {
      FontePreco.anp => (Icons.account_balance_outlined, cores.anp, 'Pesquisa ANP'),
      FontePreco.estimativa => (Icons.insights_outlined, cores.estimativa, 'Estimativa'),
      FontePreco.comunidade => confirmado
          ? (Icons.groups_rounded, cs.primary, 'Confirmado pela comunidade')
          // Não confirmado: cinza do texto secundário (o tom de contorno ficava abaixo de 4,5:1 no selo)
          : (Icons.person_outline, cs.onSurfaceVariant, 'Aguardando confirmação'),
    };
    return Tooltip(
      message: descricao,
      child: Semantics(
        label: descricao,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: ExcludeSemantics(child: Icon(icone, size: 16, color: cor)),
        ),
      ),
    );
  }
}

/// Linha de preço de um combustível (tela do posto e favoritos).
class LinhaPreco extends StatelessWidget {
  final int produtoId;
  final PrecoAtual? preco;
  final int aguardando; // não aparece na linha: a contagem fica no painel de contribuições
  final VoidCallback? aoTocar;
  const LinhaPreco({super.key, required this.produtoId, this.preco, this.aguardando = 0, this.aoTocar});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = preco;
    // Nome à esquerda; preço encostado à direita, com a idade (bolinha) e a origem (ícone) embaixo.
    // Os detalhes ficam no painel que abre ao tocar.
    return InkWell(
      onTap: aoTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Expanded(child: Text(Produto.porId(produtoId).nome, style: tt.titleMedium)),
          const SizedBox(width: 12),
          if (p == null)
            Text('Sem preço', style: tt.bodyMedium?.copyWith(color: cs.outline))
          else
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                p.fonte == FontePreco.estimativa ? '≈ ${preco_(p.preco)}' : preco_(p.preco),
                style: tt.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: p.fonte == FontePreco.estimativa ? cs.onSurfaceVariant : null,
                ),
              ),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                PontoFrescor(p.frescor()),
                const SizedBox(width: 6),
                SeloFonte(p),
              ]),
            ]),
        ]),
      ),
    );
  }
}

String preco_(double v) => preco(v);

/// Cartão de posto para listas (busca, favoritos, lista do mapa no tablet).
class CartaoPosto extends StatelessWidget {
  final PostoResumo posto;
  final int produtoId;
  final VoidCallback aoTocar;
  final Widget? acao;
  final bool selecionado;
  const CartaoPosto({
    super.key,
    required this.posto,
    required this.produtoId,
    required this.aoTocar,
    this.acao,
    this.selecionado = false,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = posto.preco(produtoId);
    return Card(
      color: selecionado ? cs.secondaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(posto.nome, style: tt.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  NotaCompacta(posto.notaMedia, posto.totalAvaliacoes),
                  if (posto.distanciaKm != null) Text(distancia(posto.distanciaKm), style: tt.bodyMedium),
                  if (posto.precisao != PrecisaoLocalizacao.exata)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.location_searching, size: 14, color: cs.tertiary),
                      const SizedBox(width: 3),
                      Text(posto.precisao.aproximada ? 'Local aproximado' : 'Local desconhecido',
                          style: tt.bodySmall?.copyWith(color: cs.tertiary, fontWeight: FontWeight.w600)),
                    ]),
                  if (posto.bandeira != null) Text(posto.bandeira!, style: tt.bodySmall?.copyWith(color: cs.outline)),
                ]),
                const SizedBox(height: 4),
                Text(
                  [posto.endereco, posto.bairro, posto.cidade].where((e) => e != null && e.isNotEmpty).join(' · '),
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (p == null)
                Text('Sem preço', style: tt.bodyMedium?.copyWith(color: cs.outline))
              else ...[
                Text(p.fonte == FontePreco.estimativa ? '≈ ${preco(p.preco)}' : preco(p.preco),
                    style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  PontoFrescor(p.frescor()),
                  const SizedBox(width: 6),
                  SeloFonte(p),
                ]),
              ],
              ?acao,
            ]),
          ]),
        ),
      ),
    );
  }
}

class EstadoVazio extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String? texto;
  final Widget? acao;
  const EstadoVazio({super.key, required this.icone, required this.titulo, this.texto, this.acao});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    // Rola quando não cabe (tela baixa ou fonte ampliada) e fica centralizado quando sobra espaço
    return LayoutBuilder(
      builder: (context, limites) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: limites.maxHeight.isFinite ? limites.maxHeight : 0),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icone, size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(titulo, style: tt.titleLarge, textAlign: TextAlign.center),
                if (texto != null) ...[
                  const SizedBox(height: 8),
                  Text(texto!, style: tt.bodyMedium, textAlign: TextAlign.center),
                ],
                if (acao != null) ...[const SizedBox(height: 20), acao!],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class EstadoErro extends StatelessWidget {
  final Object erro;
  final VoidCallback tentarDeNovo;
  const EstadoErro(this.erro, this.tentarDeNovo, {super.key});
  @override
  Widget build(BuildContext context) => EstadoVazio(
        icone: Icons.cloud_off_rounded,
        titulo: 'Não foi possível carregar',
        texto: erro is ErroApp ? erro.toString() : 'Verifique sua internet e tente de novo.',
        acao: OutlinedButton.icon(onPressed: tentarDeNovo, icon: const Icon(Icons.refresh), label: const Text('Tentar de novo')),
      );
}

void mostrarMensagem(BuildContext context, Object mensagem) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(mensagem.toString())));
}

/// Pede login quando o usuário tenta alterar ou acrescentar dados. Retorna true se já estiver logado.
Future<bool> exigirLogin(BuildContext context, String motivo) async {
  if (Sessao.instancia.logado) return true;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Entre para continuar', style: Theme.of(c).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(motivo),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              context.push('/entrar');
            },
            child: const Text('Entrar'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(c);
              context.push('/cadastro');
            },
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Criar conta'),
          ),
        ]),
      ),
    ),
  );
  return false;
}

/// Seção com título usada nas telas de detalhe.
class Secao extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final Widget? acao;
  final Widget child;
  const Secao({super.key, required this.titulo, this.subtitulo, this.acao, required this.child});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(titulo, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
        ?acao,
      ]),
      if (subtitulo != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitulo!, style: tt.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      const SizedBox(height: 12),
      child,
    ]);
  }
}
