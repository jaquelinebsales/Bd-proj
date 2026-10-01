/// Interpreta o texto reconhecido na foto do painel de preços.
///
/// Recebe as linhas de texto com a posição de cada uma (vinda do ML Kit) e
/// devolve um preço por combustível. É código puro, sem dependência de câmera,
/// para ser testado. O resultado é sempre uma sugestão: o usuário revisa tudo.
library;

class LinhaTexto {
  final String texto;
  final double esquerda, topo, direita, base;
  const LinhaTexto(this.texto, {this.esquerda = 0, this.topo = 0, this.direita = 0, this.base = 0});
  double get centroY => (topo + base) / 2;
  double get centroX => (esquerda + direita) / 2;
  double get altura => (base - topo).abs().clamp(1, double.infinity).toDouble();
}

class LeituraPreco {
  final int produtoId;
  final double preco;
  final double confianca;
  final String trecho;
  const LeituraPreco(this.produtoId, this.preco, this.confianca, this.trecho);
  @override
  String toString() => 'LeituraPreco($produtoId, $preco, ${confianca.toStringAsFixed(2)})';
}

class ResultadoLeitura {
  final List<LeituraPreco> leituras;

  /// Preços encontrados sem combustível associado; o app mostra como sugestões.
  final List<double> precosSemRotulo;
  final String textoCompleto;
  const ResultadoLeitura(this.leituras, this.precosSemRotulo, this.textoCompleto);
  LeituraPreco? de(int produtoId) {
    for (final l in leituras) {
      if (l.produtoId == produtoId) return l;
    }
    return null;
  }
}

String _normalizar(String s) {
  const de = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç';
  const para = 'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = de.indexOf(c);
    b.write(i >= 0 ? para[i] : c);
  }
  return b.toString().toUpperCase();
}

/// Identifica o combustível citado no texto (ids da tabela produtos).
int? produtoDoTexto(String bruto) {
  final t = _normalizar(bruto);
  if (RegExp(r'\bGNV\b|GAS NATURAL').hasMatch(t)) return 6;
  if (RegExp(r'S\s?-?\s?10\b|DIESEL\s*10\b').hasMatch(t)) return 5;
  if (RegExp(r'S\s?-?\s?500|DIESEL').hasMatch(t)) return 4;
  if (RegExp(r'ETANOL|ALCOOL|\bETA\b').hasMatch(t)) return 3;
  if (RegExp(r'ADITIVAD|\bADIT\b|\bAD\.|V-?POWER|\bGRID\b').hasMatch(t)) return 2;
  if (RegExp(r'GASOLINA|\bGAS\b|\bGAS\.|COMUM').hasMatch(t)) return 1;
  return null;
}

class _PrecoEncontrado {
  final double valor;
  final double confianca;
  final String trecho;
  const _PrecoEncontrado(this.valor, this.confianca, this.trecho);
}

/// Extrai preços de uma linha. Aceita "5,99", "5.999", "5,99 9" (milésimo sobrescrito) e "5999" de painéis de LED.
List<_PrecoEncontrado> _precosNaLinha(String bruto) {
  // Confusões comuns do OCR em números
  final t = bruto
      .replaceAll(RegExp(r'(?<=\d)[Oo](?=\d|\b)'), '0')
      .replaceAll(RegExp(r'(?<=\d)[Il|](?=\d|\b)'), '1')
      .replaceAll(RegExp(r'(?<=[\.,]\s?\d)[Oo]'), '0');
  final achados = <_PrecoEncontrado>[];
  final comSeparador = RegExp(r'(?<!\d)(\d{1,2})\s?[\.,]\s?(\d{2})(?:\s?(\d))?(?!\d)');
  for (final m in comSeparador.allMatches(t)) {
    final inteiro = int.parse(m.group(1)!);
    final centavos = int.parse(m.group(2)!);
    final milesimo = m.group(3) == null ? 0 : int.parse(m.group(3)!);
    final v = inteiro + centavos / 100 + milesimo / 1000;
    if (v >= 1.5 && v <= 15) achados.add(_PrecoEncontrado(double.parse(v.toStringAsFixed(3)), 0.9, m.group(0)!));
  }
  if (achados.isEmpty) {
    final semSeparador = RegExp(r'(?<![\d\.,])([2-9])(\d{2})(\d)?(?![\d\.,])');
    for (final m in semSeparador.allMatches(t)) {
      final v = int.parse(m.group(1)!) + int.parse(m.group(2)!) / 100 + (m.group(3) == null ? 0 : int.parse(m.group(3)!) / 1000);
      if (v >= 1.5 && v <= 15) achados.add(_PrecoEncontrado(double.parse(v.toStringAsFixed(3)), 0.6, m.group(0)!));
    }
  }
  return achados;
}

ResultadoLeitura interpretarPainel(List<LinhaTexto> linhas) {
  final rotulos = <({int produto, LinhaTexto linha})>[];
  final precos = <({_PrecoEncontrado preco, LinhaTexto linha, bool mesmaLinhaDeRotulo})>[];
  final leituras = <int, LeituraPreco>{};

  for (final l in linhas) {
    final prod = produtoDoTexto(l.texto);
    final ps = _precosNaLinha(l.texto);
    if (prod != null && ps.isNotEmpty) {
      // Rótulo e preço na mesma linha: associação direta
      final p = ps.last;
      final atual = leituras[prod];
      if (atual == null || atual.confianca < p.confianca) {
        leituras[prod] = LeituraPreco(prod, p.valor, p.confianca, l.texto);
      }
      continue;
    }
    if (prod != null) rotulos.add((produto: prod, linha: l));
    for (final p in ps) {
      precos.add((preco: p, linha: l, mesmaLinhaDeRotulo: false));
    }
  }

  // Associa rótulos e preços em linhas separadas pela posição na foto
  final candidatos = <({int rotulo, int preco, double custo})>[];
  for (var r = 0; r < rotulos.length; r++) {
    if (leituras.containsKey(rotulos[r].produto)) continue;
    final lr = rotulos[r].linha;
    for (var p = 0; p < precos.length; p++) {
      final lp = precos[p].linha;
      final dy = (lp.centroY - lr.centroY).abs() / lr.altura;
      final dx = (lp.esquerda - lr.direita) / lr.altura;
      // Preço à direita na mesma altura é o padrão; abaixo do rótulo também é comum
      final aDireita = dx >= -1 && dy <= 1.2;
      final abaixo = lp.topo >= lr.topo && dy <= 4 && (lp.centroX - lr.centroX).abs() / lr.altura <= 6;
      if (!aDireita && !abaixo) continue;
      final custo = aDireita ? dy + dx.abs() * 0.05 : 2 + dy;
      candidatos.add((rotulo: r, preco: p, custo: custo));
    }
  }
  candidatos.sort((a, b) => a.custo.compareTo(b.custo));
  final usadosR = <int>{}, usadosP = <int>{};
  for (final c in candidatos) {
    if (usadosR.contains(c.rotulo) || usadosP.contains(c.preco)) continue;
    final prod = rotulos[c.rotulo].produto;
    if (leituras.containsKey(prod)) continue;
    usadosR.add(c.rotulo);
    usadosP.add(c.preco);
    final p = precos[c.preco].preco;
    final conf = (p.confianca - (c.custo > 2 ? 0.2 : 0.1)).clamp(0.3, 0.95).toDouble();
    leituras[prod] = LeituraPreco(prod, p.valor, conf, '${rotulos[c.rotulo].linha.texto} ${p.trecho}');
  }

  final soltos = <double>[
    for (var p = 0; p < precos.length; p++)
      if (!usadosP.contains(p)) precos[p].preco.valor,
  ];
  final ordem = [1, 2, 3, 5, 4, 6];
  final lista = leituras.values.toList()..sort((a, b) => ordem.indexOf(a.produtoId).compareTo(ordem.indexOf(b.produtoId)));
  return ResultadoLeitura(lista, soltos.toSet().toList(), linhas.map((l) => l.texto).join('\n'));
}
