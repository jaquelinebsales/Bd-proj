import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../modelos/modelos.dart';
import '../tema.dart';

final _real = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 2);
final _real3 = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$', decimalDigits: 3);
final _data = DateFormat('dd/MM/yyyy', 'pt_BR');
final _dataCurta = DateFormat('dd/MM', 'pt_BR');
final _km = NumberFormat('#,##0.0', 'pt_BR');

String reais(double v) => _real.format(v);

/// Preço com 3 casas só quando a terceira casa não é zero (ex.: R$ 5,999).
String preco(double v) {
  final mil = (v * 1000).round();
  return mil % 10 == 0 ? _real.format(v) : _real3.format(v);
}

String data(DateTime d) => _data.format(d);
String dataCurta(DateTime d) => _dataCurta.format(d);

String distancia(double? km) {
  if (km == null) return '';
  if (km < 1) return '${(km * 1000).round()} m';
  return '${_km.format(km)} km';
}

String tempoRelativo(DateTime quando, [DateTime? agora]) {
  final d = (agora ?? DateTime.now()).difference(quando);
  if (d.inMinutes < 1) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  if (d.inDays == 1) return 'há 1 dia';
  if (d.inDays < 30) return 'há ${d.inDays} dias';
  return 'em ${data(quando)}';
}

/// Texto da origem do preço, como no item 14 do documento de requisitos.
String origemPreco(PrecoAtual p) => switch (p.situacao) {
      SituacaoPreco.confirmado => '${tempoRelativo(p.atualizadoEm)} · comunidade',
      SituacaoPreco.naoConfirmado => '${tempoRelativo(p.atualizadoEm)} · aguardando confirmação',
      SituacaoPreco.divergente => p.fonte == FontePreco.anp
          ? 'Pesquisa ANP de ${dataCurta(p.atualizadoEm)} · envios divergentes'
          : '${tempoRelativo(p.atualizadoEm)} · envios divergentes',
      SituacaoPreco.oficial => 'Pesquisa ANP · semana de ${dataCurta(p.atualizadoEm)}',
      SituacaoPreco.estimado =>
        'Estimativa · erro médio ${reais(p.margem ?? 0)} · referência a ${distancia(p.distanciaKm)}',
    };

Color corFrescor(Frescor f) => switch (f) {
      Frescor.recente => Tema.recente,
      Frescor.antigo => Tema.antigo,
      Frescor.semAtualizacao => Tema.semAtualizacao,
    };

String textoFrescor(Frescor f) => switch (f) {
      Frescor.recente => 'Atualizado recentemente',
      Frescor.antigo => 'Atualização antiga',
      Frescor.semAtualizacao => 'Sem atualização recente',
    };
