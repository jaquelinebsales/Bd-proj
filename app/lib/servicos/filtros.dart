import '../modelos/modelos.dart';

/// Filtros e ordenação são processados no aparelho (item 17 do documento de requisitos).
enum Ordenacao { maisProximos, menorPreco, maiorPreco, melhorAvaliacao, piorAvaliacao, maisRecente, menosRecente }

extension OrdenacaoTexto on Ordenacao {
  String get texto => switch (this) {
        Ordenacao.maisProximos => 'Mais próximos',
        Ordenacao.menorPreco => 'Menor preço',
        Ordenacao.maiorPreco => 'Maior preço',
        Ordenacao.melhorAvaliacao => 'Melhor avaliação',
        Ordenacao.piorAvaliacao => 'Pior avaliação',
        Ordenacao.maisRecente => 'Atualização mais recente',
        Ordenacao.menosRecente => 'Atualização menos recente',
      };
}

/// Período máximo desde a última atualização do preço.
enum PeriodoAtualizacao { qualquer, ultimas24h, ultimos7dias, ultimos30dias }

extension PeriodoTexto on PeriodoAtualizacao {
  String get texto => switch (this) {
        PeriodoAtualizacao.qualquer => 'Qualquer data',
        PeriodoAtualizacao.ultimas24h => 'Últimas 24 h',
        PeriodoAtualizacao.ultimos7dias => 'Últimos 7 dias',
        PeriodoAtualizacao.ultimos30dias => 'Últimos 30 dias',
      };
  Duration? get duracao => switch (this) {
        PeriodoAtualizacao.qualquer => null,
        PeriodoAtualizacao.ultimas24h => const Duration(hours: 24),
        PeriodoAtualizacao.ultimos7dias => const Duration(days: 7),
        PeriodoAtualizacao.ultimos30dias => const Duration(days: 30),
      };
}

class Filtros {
  final int produtoId;
  final double? precoMin;
  final double? precoMax;
  final double? distanciaMaxKm;
  final double avaliacaoMinima;
  final bool soFavoritos;
  final PeriodoAtualizacao periodo;
  final bool incluirEstimativas;
  final Ordenacao ordenacao;

  const Filtros({
    this.produtoId = 1,
    this.precoMin,
    this.precoMax,
    this.distanciaMaxKm,
    this.avaliacaoMinima = 0,
    this.soFavoritos = false,
    this.periodo = PeriodoAtualizacao.qualquer,
    this.incluirEstimativas = true,
    this.ordenacao = Ordenacao.maisProximos,
  });

  Filtros copiar({
    int? produtoId,
    double? precoMin,
    double? precoMax,
    bool limparFaixaPreco = false,
    double? distanciaMaxKm,
    bool limparDistancia = false,
    double? avaliacaoMinima,
    bool? soFavoritos,
    PeriodoAtualizacao? periodo,
    bool? incluirEstimativas,
    Ordenacao? ordenacao,
  }) =>
      Filtros(
        produtoId: produtoId ?? this.produtoId,
        precoMin: limparFaixaPreco ? null : (precoMin ?? this.precoMin),
        precoMax: limparFaixaPreco ? null : (precoMax ?? this.precoMax),
        distanciaMaxKm: limparDistancia ? null : (distanciaMaxKm ?? this.distanciaMaxKm),
        avaliacaoMinima: avaliacaoMinima ?? this.avaliacaoMinima,
        soFavoritos: soFavoritos ?? this.soFavoritos,
        periodo: periodo ?? this.periodo,
        incluirEstimativas: incluirEstimativas ?? this.incluirEstimativas,
        ordenacao: ordenacao ?? this.ordenacao,
      );

  /// Quantos filtros além do combustível estão ativos (para o selo do botão).
  int get ativos => [
        precoMin != null || precoMax != null,
        distanciaMaxKm != null,
        avaliacaoMinima > 0,
        soFavoritos,
        periodo != PeriodoAtualizacao.qualquer,
        !incluirEstimativas,
      ].where((x) => x).length;
}

/// Aplica filtros e ordenação. [favoritos] são os ids favoritados; [agora] é injetável para teste.
List<PostoResumo> aplicarFiltros(List<PostoResumo> postos, Filtros f, {Set<int> favoritos = const {}, DateTime? agora}) {
  final momento = agora ?? DateTime.now();
  final limiteData = f.periodo.duracao == null ? null : momento.subtract(f.periodo.duracao!);

  final saida = postos.where((p) {
    final pr = p.preco(f.produtoId);
    if (f.soFavoritos && !favoritos.contains(p.id)) return false;
    if (f.avaliacaoMinima > 0 && (p.notaMedia ?? 0) < f.avaliacaoMinima) return false;
    if (f.distanciaMaxKm != null && (p.distanciaKm == null || p.distanciaKm! > f.distanciaMaxKm!)) return false;
    final exigePreco = f.precoMin != null || f.precoMax != null || limiteData != null;
    if (pr == null) return !exigePreco;
    if (!f.incluirEstimativas && pr.fonte == FontePreco.estimativa) return false;
    if (f.precoMin != null && pr.preco < f.precoMin!) return false;
    if (f.precoMax != null && pr.preco > f.precoMax!) return false;
    if (limiteData != null && (pr.fonte == FontePreco.estimativa || pr.atualizadoEm.isBefore(limiteData))) {
      return false;
    }
    return true;
  }).toList();

  // Postos sem preço do combustível escolhido vão sempre para o fim nas ordenações por preço/data.
  int porPreco(PostoResumo a, PostoResumo b, bool crescente) {
    final pa = a.preco(f.produtoId)?.preco, pb = b.preco(f.produtoId)?.preco;
    if (pa == null && pb == null) return 0;
    if (pa == null) return 1;
    if (pb == null) return -1;
    return crescente ? pa.compareTo(pb) : pb.compareTo(pa);
  }

  int porData(PostoResumo a, PostoResumo b, bool recente) {
    final da = a.preco(f.produtoId)?.atualizadoEm, db = b.preco(f.produtoId)?.atualizadoEm;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return recente ? db.compareTo(da) : da.compareTo(db);
  }

  int porNota(PostoResumo a, PostoResumo b, bool melhor) {
    final na = a.notaMedia, nb = b.notaMedia;
    if (na == null && nb == null) return 0;
    if (na == null) return 1;
    if (nb == null) return -1;
    final c = melhor ? nb.compareTo(na) : na.compareTo(nb);
    return c != 0 ? c : b.totalAvaliacoes.compareTo(a.totalAvaliacoes);
  }

  int porDistancia(PostoResumo a, PostoResumo b) =>
      (a.distanciaKm ?? double.infinity).compareTo(b.distanciaKm ?? double.infinity);

  saida.sort((a, b) {
    final c = switch (f.ordenacao) {
      Ordenacao.maisProximos => porDistancia(a, b),
      Ordenacao.menorPreco => porPreco(a, b, true),
      Ordenacao.maiorPreco => porPreco(a, b, false),
      Ordenacao.melhorAvaliacao => porNota(a, b, true),
      Ordenacao.piorAvaliacao => porNota(a, b, false),
      Ordenacao.maisRecente => porData(a, b, true),
      Ordenacao.menosRecente => porData(a, b, false),
    };
    return c != 0 ? c : porDistancia(a, b);
  });
  return saida;
}
