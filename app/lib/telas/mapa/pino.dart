import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../tema.dart';
import '../../util/formatos.dart';

/// Até 7 dias: preenchido, com o número em branco. Preço velho, estimativa e posto sem preço: contorno
/// (tracejado na estimativa), para que a idade do dado não dependa só da cor.
enum EstiloPino { cheio, contorno, tracejado, vazio }

/// Medidas do pino em pixels lógicos. No mapa nativo o fundo vira uma imagem esticada até caber o preço,
/// que o próprio mapa escreve: assim o pino anda junto com o mapa, sem atraso.
abstract final class MedidasPino {
  static const margem = 2.0; // espaço do anel do selecionado e da sombra
  static const folgaH = 9.0;
  static const folgaV = 4.0;
  static const ponta = 7.0;
  static const fonte = 13.0;
  static const alturaTexto = fonte * 1.2;
  static const larguraTexto = 26.0; // "5,99" em negrito
  static const largura = margem * 2 + folgaH * 2 + larguraTexto;
  static const altura = margem + folgaV * 2 + alturaTexto + ponta;
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Texto do pino: o preço sem "R$", com "≈" na estimativa e um traço no posto sem preço.
String textoPino(PrecoAtual? p) => p == null
    ? '–'
    : '${p.fonte == FontePreco.estimativa ? '≈' : ''}${preco(p.preco).replaceAll('R\$', '').trim()}';

@immutable
class AparenciaPino {
  final EstiloPino estilo;
  final Color fundo;
  final Color borda;
  final double larguraBorda;
  final Color corTexto;
  final Color corPonta;
  final Color? anel;

  const AparenciaPino._({
    required this.estilo,
    required this.fundo,
    required this.borda,
    required this.larguraBorda,
    required this.corTexto,
    required this.corPonta,
    this.anel,
  });

  factory AparenciaPino.de(PrecoAtual? p, {required bool selecionado, required CoresPreco cores, required ColorScheme cs}) {
    // Os pinos preenchidos usam os tons do tema claro também no escuro: ficam sobre o mapa, com o número em branco
    final (estilo, cor) = p == null
        ? (EstiloPino.vazio, cores.semPreco)
        : p.fonte == FontePreco.estimativa
            ? (EstiloPino.tracejado, cores.estimativa)
            : switch (p.frescor()) {
                Frescor.recente => (EstiloPino.cheio, CoresPreco.claro.recente),
                Frescor.antigo => (EstiloPino.cheio, CoresPreco.claro.antigo),
                Frescor.semAtualizacao => (EstiloPino.contorno, cores.semAtualizacao),
              };
    final cheio = estilo == EstiloPino.cheio;
    return AparenciaPino._(
      estilo: estilo,
      fundo: cheio ? cor : cores.fundoPino,
      borda: switch (estilo) {
        EstiloPino.cheio => Colors.white,
        EstiloPino.vazio => cores.bordaSemPreco,
        _ => cor,
      },
      larguraBorda: cheio || estilo == EstiloPino.vazio ? 1.5 : 2.0,
      corTexto: cheio ? Colors.white : cor,
      corPonta: estilo == EstiloPino.vazio ? cores.bordaSemPreco : cor,
      anel: selecionado ? cs.onSurface : null,
    );
  }

  /// Nome da imagem no estilo do mapa. A cor do texto não entra: o texto é desenhado pelo mapa.
  String get id => 'gasprice-pino-${estilo.name}-${_hex(fundo)}-${_hex(borda)}-${_hex(corPonta)}'
      '${anel == null ? '' : '-${_hex(anel!)}'}';

  String get corTextoHex => _hex(corTexto);

  /// Fundo do pino em PNG, na densidade da tela.
  Future<Uint8List> png(double densidade) async {
    final gravador = ui.PictureRecorder();
    final canvas = Canvas(gravador)..scale(densidade);
    PintorPino(this).paint(canvas, const Size(MedidasPino.largura, MedidasPino.altura));
    final imagem = await gravador.endRecording().toImage(
          (MedidasPino.largura * densidade).ceil(),
          (MedidasPino.altura * densidade).ceil(),
        );
    final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
    imagem.dispose();
    return bytes!.buffer.asUint8List();
  }

  @override
  bool operator ==(Object other) => other is AparenciaPino && other.id == id && other.corTexto == corTexto;

  @override
  int get hashCode => Object.hash(id, corTexto);
}

/// Pílula com borda e a ponta embaixo, que marca o posto.
class PintorPino extends CustomPainter {
  final AparenciaPino a;
  const PintorPino(this.a);

  @override
  void paint(Canvas canvas, Size size) {
    const m = MedidasPino.margem, t = MedidasPino.ponta;
    final alturaPilula = size.height - t - m;
    final pilula = RRect.fromRectAndRadius(
      Rect.fromLTWH(m, m, size.width - 2 * m, alturaPilula),
      Radius.circular(alturaPilula / 2),
    );
    canvas.drawRRect(
      pilula.shift(const Offset(0, 1)),
      Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
    final cx = size.width / 2, base = m + alturaPilula;
    canvas.drawPath(
      Path()
        ..moveTo(cx - 6, base - 1)
        ..lineTo(cx, size.height)
        ..lineTo(cx + 6, base - 1)
        ..close(),
      Paint()..color = a.corPonta,
    );
    canvas.drawRRect(pilula, Paint()..color = a.fundo);
    final tinta = Paint()
      ..color = a.borda
      ..style = PaintingStyle.stroke
      ..strokeWidth = a.larguraBorda;
    final contorno = pilula.deflate(a.larguraBorda / 2);
    if (a.estilo == EstiloPino.tracejado) {
      for (final trecho in (Path()..addRRect(contorno)).computeMetrics()) {
        for (var d = 0.0; d < trecho.length; d += 8) {
          canvas.drawPath(trecho.extractPath(d, d + 5), tinta);
        }
      }
    } else {
      canvas.drawRRect(contorno, tinta);
    }
    if (a.anel case final anel?) {
      canvas.drawRRect(
        pilula.inflate(1),
        Paint()
          ..color = anel
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(PintorPino old) => old.a != a;
}

/// Camada de símbolos dos postos no estilo do MapLibre. O fundo (icon-image) se ajusta ao preço
/// (icon-text-fit), e a base da ponta fica exatamente sobre o posto.
abstract final class CamadaPinos {
  static const id = 'gasprice-postos';
  static const idSelecionado = 'gasprice-posto-selecionado';
  static const fonte = 'gasprice-postos';

  static const _textFitPadding = [
    MedidasPino.margem + MedidasPino.folgaV,
    MedidasPino.margem + MedidasPino.folgaH,
    MedidasPino.folgaV + MedidasPino.ponta,
    MedidasPino.margem + MedidasPino.folgaH,
  ];
  static const _textOffset = [0.0, -(MedidasPino.folgaV + MedidasPino.ponta) / MedidasPino.fonte];

  static const layout = <String, Object>{
    'icon-image': ['get', 'icone'],
    'icon-text-fit': 'both',
    'icon-text-fit-padding': _textFitPadding,
    'icon-allow-overlap': false,
    'icon-padding': 2.0,
    'text-field': ['get', 'texto'],
    'text-font': ['Noto Sans Bold'],
    'text-size': MedidasPino.fonte,
    'text-anchor': 'bottom',
    'text-offset': _textOffset,
    'text-allow-overlap': false,
    'symbol-sort-key': ['get', 'ordem'],
  };

  static const layoutSelecionado = <String, Object>{
    'icon-image': ['get', 'icone'],
    'icon-text-fit': 'both',
    'icon-text-fit-padding': _textFitPadding,
    'icon-allow-overlap': true,
    'icon-ignore-placement': true,
    'text-field': ['get', 'texto'],
    'text-font': ['Noto Sans Bold'],
    'text-size': MedidasPino.fonte,
    'text-anchor': 'bottom',
    'text-offset': _textOffset,
    'text-allow-overlap': true,
    'text-ignore-placement': true,
  };

  static const paint = <String, Object>{
    'text-color': ['get', 'corTexto'],
  };
}
