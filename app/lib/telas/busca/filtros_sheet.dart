import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicos/filtros.dart';
import '../../util/formatos.dart';

Future<Filtros?> mostrarFiltros(BuildContext context, Filtros atuais) => showModalBottomSheet<Filtros>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FiltrosSheet(atuais),
    );

class _FiltrosSheet extends StatefulWidget {
  final Filtros inicial;
  const _FiltrosSheet(this.inicial);
  @override
  State<_FiltrosSheet> createState() => _FiltrosSheetState();
}

class _FiltrosSheetState extends State<_FiltrosSheet> {
  late Filtros f = widget.inicial;
  late RangeValues _faixa = RangeValues(f.precoMin ?? 3, f.precoMax ?? 9);
  late bool _usarFaixa = f.precoMin != null || f.precoMax != null;
  static const _distancias = [2.0, 5.0, 10.0, 20.0];

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    Widget titulo(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(t, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, rolagem) => Column(children: [
        Expanded(
          child: ListView(controller: rolagem, padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
            Text('Filtros', style: tt.headlineSmall),
            titulo('Combustível'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in Produto.todos)
                ChoiceChip(
                  label: Text(p.nome),
                  selected: f.produtoId == p.id,
                  onSelected: (_) => setState(() => f = f.copiar(produtoId: p.id)),
                ),
            ]),
            titulo('Faixa de preço'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_usarFaixa ? '${reais(_faixa.start)} a ${reais(_faixa.end)}' : 'Qualquer preço'),
              value: _usarFaixa,
              onChanged: (v) => setState(() => _usarFaixa = v),
            ),
            if (_usarFaixa)
              RangeSlider(
                values: _faixa,
                min: 1.5,
                max: 12,
                divisions: 105,
                labels: RangeLabels(reais(_faixa.start), reais(_faixa.end)),
                onChanged: (v) => setState(() => _faixa = v),
              ),
            titulo('Distância'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: const Text('Qualquer'),
                selected: f.distanciaMaxKm == null,
                onSelected: (_) => setState(() => f = f.copiar(limparDistancia: true)),
              ),
              for (final d in _distancias)
                ChoiceChip(
                  label: Text('Até ${d.toStringAsFixed(0)} km'),
                  selected: f.distanciaMaxKm == d,
                  onSelected: (_) => setState(() => f = f.copiar(distanciaMaxKm: d)),
                ),
            ]),
            titulo('Avaliação mínima'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final n in [0.0, 3.0, 4.0, 4.5])
                ChoiceChip(
                  avatar: n == 0 ? null : const Icon(Icons.star_rounded, size: 18, color: Color(0xFFE0A100)),
                  label: Text(n == 0 ? 'Qualquer' : '${n.toString().replaceAll('.', ',')}+'),
                  selected: f.avaliacaoMinima == n,
                  onSelected: (_) => setState(() => f = f.copiar(avaliacaoMinima: n)),
                ),
            ]),
            titulo('Última atualização do preço'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in PeriodoAtualizacao.values)
                ChoiceChip(
                  label: Text(p.texto),
                  selected: f.periodo == p,
                  onSelected: (_) => setState(() => f = f.copiar(periodo: p)),
                ),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Só postos favoritos'),
              value: f.soFavoritos,
              onChanged: (v) => setState(() => f = f.copiar(soFavoritos: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Incluir preços estimados'),
              value: f.incluirEstimativas,
              onChanged: (v) => setState(() => f = f.copiar(incluirEstimativas: v)),
            ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => Navigator.pop(context, Filtros(produtoId: f.produtoId, ordenacao: f.ordenacao)),
                  child: const Text('Limpar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    _usarFaixa
                        ? f.copiar(precoMin: _faixa.start, precoMax: _faixa.end)
                        : f.copiar(limparFaixaPreco: true),
                  ),
                  child: const Text('Aplicar'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
