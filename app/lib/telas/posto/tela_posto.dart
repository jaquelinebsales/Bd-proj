import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../servicos/favoritos.dart';
import '../../servicos/localizacao.dart';
import '../../servicos/preferencias.dart';
import '../../util/formatos.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';
import '../../widgets/grafico_historico.dart';
import 'contribuicoes_sheet.dart';

/// Detalhes do posto: preços com origem, histórico, avaliações e dados cadastrais da ANP.
class TelaPosto extends StatefulWidget {
  final int postoId;
  const TelaPosto({super.key, required this.postoId});
  @override
  State<TelaPosto> createState() => _TelaPostoState();
}

class _TelaPostoState extends State<TelaPosto> {
  late Future<PostoDetalhe> _detalhe = Api.instancia.detalhe(widget.postoId);

  Future<void> _recarregar() async {
    setState(() => _detalhe = Api.instancia.detalhe(widget.postoId, forcar: true));
    await _detalhe;
  }

  Future<void> _favoritar() async {
    try {
      await Favoritos.instancia.alternar(widget.postoId);
      if (mounted) {
        mostrarMensagem(
          context,
          Favoritos.instancia.contem(widget.postoId)
              ? 'Posto salvo nos favoritos.'
              : 'Posto removido dos favoritos.',
        );
      }
    } catch (e) {
      if (mounted) mostrarMensagem(context, e);
    }
  }

  /// Posição exata vai por coordenada. Posição aproximada ou desconhecida vai pelo endereço,
  /// que o Google Maps localiza melhor do que o ponto aproximado do app.
  Future<void> _rotas(PostoResumo p) async {
    final Uri url;
    if (p.precisao == PrecisaoLocalizacao.exata && p.lat != null) {
      url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lon}');
    } else {
      final consulta = [p.endereco, p.bairro, p.municipio, p.uf, 'Brasil'].where((e) => e != null && e.isNotEmpty).join(', ');
      url = Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': consulta});
    }
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) && mounted) {
      mostrarMensagem(context, 'Não foi possível abrir o aplicativo de mapas.');
    }
  }

  Future<void> _informarPosicao() async {
    if (!await exigirLogin(context, 'Para informar a posição de um posto, entre na sua conta.')) return;
    if (!mounted) return;
    final informou = await context.push<bool>('/posto/${widget.postoId}/posicao');
    if (informou == true) _recarregar();
  }

  Future<void> _atualizarPrecos(PostoDetalhe d) async {
    if (!d.resumo.precisao.aceitaEnvio) {
      final informar = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Ainda não sabemos onde este posto fica'),
          content: const Text('Para enviar preços, precisamos da posição do posto. Se você está nele agora, toque em '
              '"Estou neste posto". Quando outra pessoa também confirmar, o envio de preço fica liberado.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Agora não')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Estou neste posto'),
            ),
          ],
        ),
      );
      if (informar == true) await _informarPosicao();
      return;
    }
    if (!await exigirLogin(context, 'Para enviar preços, entre na sua conta.')) return;
    if (!mounted) return;
    final enviou = await context.push<bool>('/posto/${widget.postoId}/enviar');
    if (enviou == true) _recarregar();
  }

  Future<void> _avaliar() async {
    if (!await exigirLogin(context, 'Para avaliar postos, entre na sua conta.')) return;
    if (!mounted) return;
    final salvou = await context.push<bool>('/posto/${widget.postoId}/avaliar');
    if (salvou == true) _recarregar();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: FutureBuilder<PostoDetalhe>(
          future: _detalhe,
          builder: (context, snap) {
            if (snap.hasError) {
              return Scaffold(appBar: AppBar(), body: EstadoErro(snap.error!, _recarregar));
            }
            if (!snap.hasData) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
            return _conteudo(snap.data!);
          },
        ),
      );

  Widget _conteudo(PostoDetalhe d) {
    final p = d.resumo.comDistancia(Localizacao.instancia.distanciaKm(d.resumo.lat, d.resumo.lon));
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final expandido = tamanhoDe(context) == Tamanho.expandido;

    final cabecalho = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(p.nome, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        if (p.bandeira != null)
          Chip(
            label: Text(p.bandeira!),
            visualDensity: VisualDensity.compact,
            side: BorderSide.none,
            backgroundColor: cs.secondaryContainer,
          ),
      ]),
      const SizedBox(height: 6),
      InkWell(
        onTap: () => context.push('/posto/${p.id}/avaliacoes'),
        child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          NotaCompacta(p.notaMedia, p.totalAvaliacoes),
          if (p.distanciaKm != null) Text('· ${distancia(p.distanciaKm)}', style: tt.bodyLarge),
        ]),
      ),
      const SizedBox(height: 4),
      Text([p.endereco, p.bairro, p.cidade].where((e) => e != null && e.isNotEmpty).join(' — '),
          style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: () => _rotas(p), icon: const Icon(Icons.directions), label: const Text('Como chegar')),
        OutlinedButton.icon(onPressed: _avaliar, icon: const Icon(Icons.rate_review_outlined), label: Text(d.minhaAvaliacao == null ? 'Avaliar' : 'Editar avaliação')),
      ]),
    ]);

    final precos = Secao(
      titulo: 'Preços',
      subtitulo: 'Valor mais provável por combustível, combinando ANP e comunidade',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final (i, id) in d.produtosExibidos.indexed) ...[
              if (i > 0) const Divider(height: 1),
              LinhaPreco(
                produtoId: id,
                preco: p.preco(id),
                aguardando: d.enviosAguardando[id] ?? 0,
                aoTocar: () => mostrarContribuicoes(context, d, id),
              ),
            ],
            if (d.produtosExibidos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('A ANP não informou os combustíveis deste posto. Envie uma foto do painel para começar.'),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Row(children: [
            Icon(Icons.info_outline, size: 16, color: cs.outline),
            const SizedBox(width: 6),
            Expanded(child: Text('Toque em um preço para ver quem enviou e o dado oficial.', style: tt.bodySmall?.copyWith(color: cs.outline))),
          ]),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _atualizarPrecos(d),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Atualizar preços com uma foto'),
        ),
        if (!p.municipioPesquisadoAnp)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('A ANP não pesquisa preços nesta cidade. Envios confirmados aqui valem pontos em dobro.',
                style: tt.bodySmall?.copyWith(color: cs.primary), textAlign: TextAlign.center),
          ),
      ]),
    );

    final produtoHistorico = d.produtosExibidos.contains(Preferencias.produto.value)
        ? Preferencias.produto.value
        : (d.produtosExibidos.isEmpty ? 1 : d.produtosExibidos.first);
    final historico = Secao(
      titulo: 'Histórico de preços',
      subtitulo: Produto.porId(produtoHistorico).nome,
      acao: TextButton(
        onPressed: () => context.push('/posto/${p.id}/historico?produto=$produtoHistorico'),
        child: const Text('Ver completo'),
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<List<PontoHistorico>>(
            future: Api.instancia.historico(p.id, produtoHistorico, 90),
            builder: (context, s) => s.hasData
                ? GraficoHistorico(pontos: s.data!, compacto: true)
                : const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          ),
        ),
      ),
    );

    final avaliacoes = Secao(
      titulo: 'Avaliações',
      acao: TextButton(onPressed: () => context.push('/posto/${p.id}/avaliacoes'), child: const Text('Ver todas')),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ResumoNotas(media: p.notaMedia, total: p.totalAvaliacoes, distribuicao: d.distribuicaoNotas),
        ),
      ),
    );

    final dados = Secao(
      titulo: 'Dados do posto',
      subtitulo: 'Cadastro oficial da ANP. As avaliações são 100% dos usuários.',
      child: Card(
        child: Column(children: [
          ListTile(title: const Text('Razão social'), subtitle: Text(d.razaoSocial)),
          ListTile(title: const Text('CNPJ'), subtitle: Text(_cnpj(d.cnpj))),
          ListTile(
            title: const Text('Endereço'),
            subtitle: Text([p.endereco, d.complemento, p.bairro, p.cidade, if (d.cep != null) 'CEP ${d.cep}']
                .where((e) => e != null && e.isNotEmpty)
                .join(', ')),
          ),
          ListTile(
            title: const Text('Localização no mapa'),
            subtitle: Text(p.precisao != PrecisaoLocalizacao.exata
                ? p.precisao.rotulo
                : (d.localizacaoValidada ? 'Confirmada por usuários' : 'Informada pela ANP, ainda não validada')),
          ),
          if (d.sincronizadoEm != null)
            ListTile(title: const Text('Cadastro atualizado em'), subtitle: Text(data(d.sincronizadoEm!))),
        ]),
      ),
    );

    final aviso = p.precisao == PrecisaoLocalizacao.exata
        ? null
        : Card(
            color: cs.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.location_searching, color: cs.onTertiaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(p.precisao.rotulo,
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.onTertiaryContainer)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  p.precisao.aproximada
                      ? 'O ponto deste posto no mapa pode estar a algumas centenas de metros do lugar certo. '
                          'Se você está nele, toque em "Estou neste posto". Quando duas pessoas confirmarem, '
                          'ele passa a aparecer com a posição exata.'
                      : 'Ainda não sabemos onde este posto fica, então ele não aparece no mapa e não recebe envio de preço. '
                          'Se você está nele, toque em "Estou neste posto". Quando duas pessoas confirmarem, o envio de preço fica liberado.',
                  style: tt.bodyMedium?.copyWith(color: cs.onTertiaryContainer),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: d.posicaoInformada ? null : _informarPosicao,
                  icon: const Icon(Icons.my_location),
                  label: Text(d.posicaoInformada ? 'Posição informada, aguardando outra pessoa' : 'Estou neste posto'),
                ),
              ]),
            ),
          );

    final coluna1 = [cabecalho, if (aviso != null) ...[const SizedBox(height: 16), aviso], const SizedBox(height: 24), precos];
    final coluna2 = [historico, const SizedBox(height: 24), avaliacoes, const SizedBox(height: 24), dados];

    return RefreshIndicator(
      onRefresh: _recarregar,
      child: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 140,
          actions: [
            ListenableBuilder(
              listenable: Favoritos.instancia,
              builder: (context, _) {
                final fav = Favoritos.instancia.contem(p.id);
                return IconButton.filledTonal(
                  tooltip: fav ? 'Remover dos favoritos' : 'Salvar nos favoritos',
                  onPressed: _favoritar,
                  icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? Colors.redAccent : null),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.45)!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Icon(Icons.local_gas_station_rounded, size: 72, color: Colors.white.withValues(alpha: 0.25)),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
          sliver: SliverToBoxAdapter(
            child: LarguraMaxima(
              maxima: expandido ? 1200 : 720,
              child: expandido
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: coluna1)),
                      const SizedBox(width: 32),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: coluna2)),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      ...coluna1,
                      const SizedBox(height: 24),
                      ...coluna2,
                    ]),
            ),
          ),
        ),
      ]),
    );
  }

  String _cnpj(String c) => c.length == 14
      ? '${c.substring(0, 2)}.${c.substring(2, 5)}.${c.substring(5, 8)}/${c.substring(8, 12)}-${c.substring(12)}'
      : c;
}

/// Média, total e distribuição das notas (0 a 5 estrelas).
class ResumoNotas extends StatelessWidget {
  final double? media;
  final int total;
  final Map<int, int> distribuicao;
  const ResumoNotas({super.key, this.media, required this.total, required this.distribuicao});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final maior = distribuicao.values.fold<int>(1, (a, b) => b > a ? b : a);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Text(media == null ? '–' : media!.toStringAsFixed(1).replaceAll('.', ','),
            style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
        Estrelas(media ?? 0),
        const SizedBox(height: 4),
        Text('$total avaliações', style: tt.bodySmall),
      ]),
      const SizedBox(width: 20),
      Expanded(
        child: Column(children: [
          for (var n = 5; n >= 0; n--)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 14, child: Text('$n', style: tt.bodySmall)),
                const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (distribuicao[n] ?? 0) / maior,
                      minHeight: 8,
                      backgroundColor: cs.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(width: 28, child: Text('${distribuicao[n] ?? 0}', style: tt.bodySmall, textAlign: TextAlign.end)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}
