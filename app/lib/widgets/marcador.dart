import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Gera o marcador do mapa: uma pílula com o preço e a cor da idade do dado.
class FabricaMarcadores {
  final _cache = <String, BitmapDescriptor>{};

  Future<BitmapDescriptor> pilula(String texto, Color fundo, Color borda, {double escala = 3}) async {
    final chave = '$texto|${fundo.toARGB32()}|${borda.toARGB32()}';
    final existente = _cache[chave];
    if (existente != null) return existente;

    final pintor = TextPainter(
      text: TextSpan(
        text: texto,
        style: TextStyle(color: Colors.white, fontSize: 13 * escala, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final largura = pintor.width + 20 * escala;
    final altura = pintor.height + 10 * escala;
    final ponta = 6 * escala;

    final gravador = ui.PictureRecorder();
    final canvas = Canvas(gravador);
    final corpo = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, largura, altura), Radius.circular(altura / 2));
    final caminho = Path()
      ..addRRect(corpo)
      ..moveTo(largura / 2 - ponta, altura - 1)
      ..lineTo(largura / 2, altura + ponta)
      ..lineTo(largura / 2 + ponta, altura - 1)
      ..close();
    canvas.drawPath(caminho, Paint()..color = fundo);
    canvas.drawRRect(corpo, Paint()
      ..color = borda
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * escala);
    pintor.paint(canvas, Offset((largura - pintor.width) / 2, (altura - pintor.height) / 2));

    final imagem = await gravador.endRecording().toImage(largura.ceil(), (altura + ponta).ceil());
    final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
    final descritor = BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), imagePixelRatio: escala);
    _cache[chave] = descritor;
    return descritor;
  }
}
