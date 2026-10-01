import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'parser_painel.dart';

class LeituraFoto {
  final ResultadoLeitura resultado;
  final int duracaoMs;
  const LeituraFoto(this.resultado, this.duracaoMs);
}

/// Fotografa o painel e lê o texto no próprio aparelho (ML Kit, sem internet).
/// A foto é apagada logo depois da leitura: ela nunca é enviada nem guardada.
class LeitorPainel {
  final _picker = ImagePicker();

  /// Modo demonstração: o texto de um painel típico passa pelo leitor real de preços.
  static LeituraFoto demonstracao() => LeituraFoto(
        interpretarPainel(const [
          LinhaTexto('GASOLINA COMUM', esquerda: 10, topo: 10, direita: 300, base: 50),
          LinhaTexto('5,99 9', esquerda: 360, topo: 12, direita: 480, base: 52),
          LinhaTexto('ETANOL 4,29', esquerda: 10, topo: 70, direita: 480, base: 110),
          LinhaTexto('DIESEL S-10', esquerda: 10, topo: 130, direita: 300, base: 170),
          LinhaTexto('6,32', esquerda: 360, topo: 131, direita: 480, base: 171),
          LinhaTexto('GNV', esquerda: 10, topo: 190, direita: 120, base: 230),
          LinhaTexto('479', esquerda: 360, topo: 190, direita: 460, base: 230),
        ]),
        640,
      );

  Future<LeituraFoto?> fotografarELer() async {
    final foto = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 2400,
      imageQuality: 92,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (foto == null) return null;
    return lerArquivo(foto.path);
  }

  Future<LeituraFoto> lerArquivo(String caminho) async {
    final inicio = DateTime.now();
    final reconhecedor = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final texto = await reconhecedor.processImage(InputImage.fromFilePath(caminho));
      final linhas = <LinhaTexto>[
        for (final bloco in texto.blocks)
          for (final linha in bloco.lines)
            LinhaTexto(
              linha.text,
              esquerda: linha.boundingBox.left,
              topo: linha.boundingBox.top,
              direita: linha.boundingBox.right,
              base: linha.boundingBox.bottom,
            ),
      ];
      final resultado = interpretarPainel(linhas);
      return LeituraFoto(resultado, DateTime.now().difference(inicio).inMilliseconds);
    } finally {
      await reconhecedor.close();
      await _apagar(caminho);
    }
  }

  Future<void> _apagar(String caminho) async {
    try {
      final f = File(caminho);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
