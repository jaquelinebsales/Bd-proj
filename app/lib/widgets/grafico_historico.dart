import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../modelos/modelos.dart';
import '../tema.dart';
import '../util/formatos.dart';

/// Gráfico de histórico com as duas origens separadas: pesquisa ANP e comunidade.
class GraficoHistorico extends StatelessWidget {
  final List<PontoHistorico> pontos;
  final bool compacto;
  const GraficoHistorico({super.key, required this.pontos, this.compacto = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final corAnp = Tema.cores(context).anp;
    if (pontos.isEmpty) {
      return SizedBox(
        height: compacto ? 120 : 260,
        child: Center(child: Text('Ainda não há histórico para este combustível.', style: TextStyle(color: cs.outline))),
      );
    }
    final inicio = pontos.first.dia;
    double x(DateTime d) => d.difference(inicio).inDays.toDouble();
    final anp = pontos.where((p) => p.anp).map((p) => FlSpot(x(p.dia), p.preco)).toList();
    final comunidade = pontos.where((p) => !p.anp).map((p) => FlSpot(x(p.dia), p.preco)).toList();
    final precos = pontos.map((p) => p.preco);
    final minY = (precos.reduce((a, b) => a < b ? a : b) - 0.1);
    final maxY = (precos.reduce((a, b) => a > b ? a : b) + 0.1);
    final maxX = x(pontos.last.dia).clamp(1, double.infinity).toDouble();

    LineChartBarData serie(List<FlSpot> s, Color cor, {bool tracejada = false}) => LineChartBarData(
          spots: s,
          color: cor,
          barWidth: 2,
          isCurved: false,
          dashArray: tracejada ? [6, 4] : null,
          dotData: FlDotData(
            show: !compacto,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 3, color: cor, strokeColor: cs.surface, strokeWidth: 1.5),
          ),
          belowBarData: BarAreaData(show: compacto, color: cor.withValues(alpha: 0.08)),
        );

    return SizedBox(
      height: compacto ? 120 : 280,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          lineBarsData: [
            if (anp.isNotEmpty) serie(anp, corAnp, tracejada: true),
            // Comunidade em tom neutro: a marca Asfalto é azulada e se confundiria com o azul da ANP
            if (comunidade.isNotEmpty) serie(comunidade, cs.onSurface),
          ],
          gridData: FlGridData(
            show: !compacto,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: cs.outlineVariant.withValues(alpha: 0.5), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            show: !compacto,
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                // As pontas do eixo (mínimo e máximo com folga de R$ 0,10) não caem no intervalo e encavalavam no vizinho
                getTitlesWidget: (v, meta) => v == meta.min || v == meta.max
                    ? const SizedBox.shrink()
                    : SideTitleWidget(
                        meta: meta,
                        child: Text(reais(v), style: TextStyle(fontSize: 10, color: cs.outline)),
                      ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: (maxX / 4).clamp(1, double.infinity).toDouble(),
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(dataCurta(inicio.add(Duration(days: v.round()))), style: TextStyle(fontSize: 10, color: cs.outline)),
                ),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            enabled: !compacto,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => cs.inverseSurface,
              getTooltipItems: (itens) => itens.map((s) {
                final eAnp = s.bar.color == corAnp;
                return LineTooltipItem(
                  '${eAnp ? 'ANP' : 'Comunidade'} · ${dataCurta(inicio.add(Duration(days: s.x.round())))}\n${preco(s.y)}',
                  TextStyle(color: cs.onInverseSurface, fontWeight: FontWeight.w600),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class LegendaHistorico extends StatelessWidget {
  const LegendaHistorico({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget item(Color c, String t, {bool tracejado = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 18,
            height: 3,
            child: tracejado
                ? Row(children: [Container(width: 7, color: c), const SizedBox(width: 4), Container(width: 7, color: c)])
                : ColoredBox(color: c),
          ),
          const SizedBox(width: 6),
          Flexible(child: Text(t, style: Theme.of(context).textTheme.bodySmall)),
        ]);
    return Wrap(spacing: 16, runSpacing: 4, children: [
      item(Tema.cores(context).anp, 'Pesquisa ANP (semanal)', tracejado: true),
      item(cs.onSurface, 'Comunidade (fotos dos usuários)'),
    ]);
  }
}
