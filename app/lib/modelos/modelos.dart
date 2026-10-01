/// Modelos de dados do app. Conversões a partir do JSON das funções RPC do Supabase.
library;

double? _num(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse(v.toString()));
int _int(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0);
DateTime? _data(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

class Produto {
  final int id;
  final String codigo;
  final String nome;
  final String unidade;
  const Produto(this.id, this.codigo, this.nome, this.unidade);

  static const todos = <Produto>[
    Produto(1, 'GC', 'Gasolina comum', 'L'),
    Produto(2, 'GA', 'Gasolina aditivada', 'L'),
    Produto(3, 'ET', 'Etanol', 'L'),
    Produto(5, 'S10', 'Diesel S10', 'L'),
    Produto(4, 'DS', 'Diesel S500', 'L'),
    Produto(6, 'GNV', 'GNV', 'm³'),
  ];

  static Produto porId(int id) => todos.firstWhere((p) => p.id == id, orElse: () => todos.first);
  static int ordem(int id) => todos.indexWhere((p) => p.id == id);
}

enum FontePreco { comunidade, anp, estimativa }

enum SituacaoPreco { confirmado, naoConfirmado, divergente, oficial, estimado }

/// Idade do preço, usada na cor do indicador (regra 20.7 do documento de requisitos).
enum Frescor { recente, antigo, semAtualizacao }

class PrecoAtual {
  final int produtoId;
  final double preco;
  final FontePreco fonte;
  final SituacaoPreco situacao;
  final DateTime atualizadoEm;
  final int confirmacoes;
  final double? margem;
  final double? distanciaKm;

  const PrecoAtual({
    required this.produtoId,
    required this.preco,
    required this.fonte,
    required this.situacao,
    required this.atualizadoEm,
    this.confirmacoes = 0,
    this.margem,
    this.distanciaKm,
  });

  factory PrecoAtual.deJson(Map<String, dynamic> j) => PrecoAtual(
        produtoId: _int(j['produto_id']),
        preco: _num(j['preco']) ?? 0,
        fonte: switch (j['fonte']) {
          'anp' => FontePreco.anp,
          'estimativa' => FontePreco.estimativa,
          _ => FontePreco.comunidade,
        },
        situacao: switch (j['situacao']) {
          'confirmado' => SituacaoPreco.confirmado,
          'divergente' => SituacaoPreco.divergente,
          'oficial' => SituacaoPreco.oficial,
          'estimado' => SituacaoPreco.estimado,
          _ => SituacaoPreco.naoConfirmado,
        },
        atualizadoEm: _data(j['atualizado_em']) ?? DateTime.now(),
        confirmacoes: _int(j['confirmacoes']),
        margem: _num(j['margem']),
        distanciaKm: _num(j['distancia_km']),
      );

  Produto get produto => Produto.porId(produtoId);

  Frescor frescor([DateTime? agora]) {
    if (fonte == FontePreco.estimativa) return Frescor.semAtualizacao;
    final horas = (agora ?? DateTime.now()).difference(atualizadoEm).inHours;
    if (horas <= 24) return Frescor.recente;
    if (horas <= 24 * 7) return Frescor.antigo;
    return Frescor.semAtualizacao;
  }
}

class PostoResumo {
  final int id;
  final String nome;
  final String? bandeira;
  final String? endereco;
  final String? bairro;
  final String municipio;
  final String uf;
  final double? lat;
  final double? lon;
  final double? notaMedia;
  final int totalAvaliacoes;
  final bool municipioPesquisadoAnp;
  final List<PrecoAtual> precos;
  final double? distanciaKm;
  final bool notificar;

  const PostoResumo({
    required this.id,
    required this.nome,
    this.bandeira,
    this.endereco,
    this.bairro,
    required this.municipio,
    required this.uf,
    this.lat,
    this.lon,
    this.notaMedia,
    this.totalAvaliacoes = 0,
    this.municipioPesquisadoAnp = false,
    this.precos = const [],
    this.distanciaKm,
    this.notificar = true,
  });

  factory PostoResumo.deJson(Map<String, dynamic> j) => PostoResumo(
        id: _int(j['id']),
        nome: nomeExibicao(j['nome']?.toString() ?? 'Posto'),
        bandeira: j['bandeira']?.toString(),
        endereco: j['endereco']?.toString(),
        bairro: j['bairro']?.toString(),
        municipio: j['municipio']?.toString() ?? '',
        uf: j['uf']?.toString() ?? '',
        lat: _num(j['lat']),
        lon: _num(j['lon']),
        notaMedia: _num(j['nota_media']),
        totalAvaliacoes: _int(j['total_avaliacoes']),
        municipioPesquisadoAnp: j['municipio_pesquisado_anp'] == true,
        precos: ((j['precos'] as List?) ?? const [])
            .map((e) => PrecoAtual.deJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        distanciaKm: _num(j['distancia_km']),
        notificar: j['notificar'] != false,
      );

  PrecoAtual? preco(int produtoId) {
    for (final p in precos) {
      if (p.produtoId == produtoId) return p;
    }
    return null;
  }

  PostoResumo comDistancia(double? km) => PostoResumo(
        id: id,
        nome: nome,
        bandeira: bandeira,
        endereco: endereco,
        bairro: bairro,
        municipio: municipio,
        uf: uf,
        lat: lat,
        lon: lon,
        notaMedia: notaMedia,
        totalAvaliacoes: totalAvaliacoes,
        municipioPesquisadoAnp: municipioPesquisadoAnp,
        precos: precos,
        distanciaKm: km,
        notificar: notificar,
      );

  String get cidade => '$municipio, $uf';
}

class PostoDetalhe {
  final PostoResumo resumo;
  final String cnpj;
  final String razaoSocial;
  final String? complemento;
  final String? cep;
  final bool localizacaoValidada;
  final List<int> produtosVendidos;
  final Map<int, int> distribuicaoNotas;
  final Map<int, int> enviosAguardando;
  final bool favorito;
  final MinhaAvaliacao? minhaAvaliacao;
  final DateTime? sincronizadoEm;

  const PostoDetalhe({
    required this.resumo,
    required this.cnpj,
    required this.razaoSocial,
    this.complemento,
    this.cep,
    this.localizacaoValidada = false,
    this.produtosVendidos = const [],
    this.distribuicaoNotas = const {},
    this.enviosAguardando = const {},
    this.favorito = false,
    this.minhaAvaliacao,
    this.sincronizadoEm,
  });

  factory PostoDetalhe.deJson(Map<String, dynamic> j) {
    Map<int, int> mapa(dynamic v) => {
          for (final e in ((v as Map?) ?? const {}).entries) int.parse(e.key.toString()): _int(e.value),
        };
    final minha = j['minha_avaliacao'];
    return PostoDetalhe(
      resumo: PostoResumo.deJson(j),
      cnpj: j['cnpj']?.toString() ?? '',
      razaoSocial: j['razao_social']?.toString() ?? '',
      complemento: j['complemento']?.toString(),
      cep: j['cep']?.toString(),
      localizacaoValidada: j['localizacao_validada'] == true,
      produtosVendidos: ((j['produtos'] as List?) ?? const []).map(_int).toList(),
      distribuicaoNotas: mapa(j['distribuicao_notas']),
      enviosAguardando: mapa(j['envios_aguardando']),
      favorito: j['favorito'] == true,
      minhaAvaliacao: minha == null ? null : MinhaAvaliacao.deJson(Map<String, dynamic>.from(minha as Map)),
      sincronizadoEm: _data(j['sincronizado_em']),
    );
  }

  /// Combustíveis a mostrar: os vendidos segundo a ANP, mais os que tenham preço.
  List<int> get produtosExibidos {
    final ids = {...produtosVendidos, ...resumo.precos.map((p) => p.produtoId)}.toList();
    ids.sort((a, b) => Produto.ordem(a).compareTo(Produto.ordem(b)));
    return ids;
  }
}

class MinhaAvaliacao {
  final int id;
  final int nota;
  final String? comentario;
  const MinhaAvaliacao(this.id, this.nota, this.comentario);
  factory MinhaAvaliacao.deJson(Map<String, dynamic> j) =>
      MinhaAvaliacao(_int(j['id']), _int(j['nota']), j['comentario']?.toString());
}

class PontoHistorico {
  final DateTime dia;
  final double preco;
  final bool anp;
  final bool confirmado;
  const PontoHistorico(this.dia, this.preco, this.anp, this.confirmado);
  factory PontoHistorico.deJson(Map<String, dynamic> j) => PontoHistorico(
        DateTime.parse(j['dia'].toString()),
        _num(j['preco']) ?? 0,
        j['fonte'] == 'anp',
        j['confirmado'] == true,
      );
}

class Contribuicao {
  final int id;
  final String autor;
  final bool souEu;
  final double preco;
  final String status;
  final bool editado;
  final DateTime criadoEm;
  const Contribuicao({
    required this.id,
    required this.autor,
    required this.souEu,
    required this.preco,
    required this.status,
    required this.editado,
    required this.criadoEm,
  });
  factory Contribuicao.deJson(Map<String, dynamic> j) => Contribuicao(
        id: _int(j['item_id']),
        autor: j['autor']?.toString() ?? 'Usuário',
        souEu: j['sou_eu'] == true,
        preco: _num(j['preco']) ?? 0,
        status: j['status']?.toString() ?? 'pendente',
        editado: j['editado'] == true,
        criadoEm: _data(j['criado_em']) ?? DateTime.now(),
      );
}

class Avaliacao {
  final int id;
  final String autor;
  final int nota;
  final String? comentario;
  final int votosUteis;
  final DateTime criadoEm;
  final bool minha;
  final bool votei;
  const Avaliacao({
    required this.id,
    required this.autor,
    required this.nota,
    this.comentario,
    this.votosUteis = 0,
    required this.criadoEm,
    this.minha = false,
    this.votei = false,
  });
  factory Avaliacao.deJson(Map<String, dynamic> j) => Avaliacao(
        id: _int(j['id']),
        autor: j['autor']?.toString() ?? 'Usuário',
        nota: _int(j['nota']),
        comentario: j['comentario']?.toString(),
        votosUteis: _int(j['votos_uteis']),
        criadoEm: _data(j['criado_em']) ?? DateTime.now(),
        minha: j['minha'] == true,
        votei: j['votei'] == true,
      );
}

class ResumoPerfil {
  final String id;
  final String nome;
  final String? avatarUrl;
  final int pontos;
  final double confiabilidade;
  final DateTime? bloqueadoAte;
  final bool notificacoesAtivas;
  final int totalAvaliacoes;
  final int totalEnvios;
  final int enviosConfirmados;
  final int posicaoRanking;
  final List<Map<String, dynamic>> ultimasAvaliacoes;
  final List<Map<String, dynamic>> ultimosEnvios;

  const ResumoPerfil({
    required this.id,
    required this.nome,
    this.avatarUrl,
    this.pontos = 0,
    this.confiabilidade = 0.5,
    this.bloqueadoAte,
    this.notificacoesAtivas = true,
    this.totalAvaliacoes = 0,
    this.totalEnvios = 0,
    this.enviosConfirmados = 0,
    this.posicaoRanking = 0,
    this.ultimasAvaliacoes = const [],
    this.ultimosEnvios = const [],
  });

  factory ResumoPerfil.deJson(Map<String, dynamic> j) => ResumoPerfil(
        id: j['id'].toString(),
        nome: j['nome']?.toString() ?? '',
        avatarUrl: j['avatar_url']?.toString(),
        pontos: _int(j['pontos']),
        confiabilidade: _num(j['confiabilidade']) ?? 0.5,
        bloqueadoAte: _data(j['bloqueado_ate']),
        notificacoesAtivas: j['notificacoes_ativas'] != false,
        totalAvaliacoes: _int(j['total_avaliacoes']),
        totalEnvios: _int(j['total_envios']),
        enviosConfirmados: _int(j['envios_confirmados']),
        posicaoRanking: _int(j['posicao_ranking']),
        ultimasAvaliacoes: ((j['ultimas_avaliacoes'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        ultimosEnvios: ((j['ultimos_envios'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );

  /// Nível exibido a partir da confiabilidade (0 a 1).
  String get nivel => confiabilidade >= 0.8
      ? 'Referência'
      : confiabilidade >= 0.6
          ? 'Confiável'
          : confiabilidade >= 0.3
              ? 'Iniciante'
              : 'Em observação';
}

class MovimentoPontos {
  final String tipo;
  final int pontos;
  final String descricao;
  final DateTime criadoEm;
  const MovimentoPontos(this.tipo, this.pontos, this.descricao, this.criadoEm);
  factory MovimentoPontos.deJson(Map<String, dynamic> j) => MovimentoPontos(
        j['tipo']?.toString() ?? '',
        _int(j['pontos']),
        j['descricao']?.toString() ?? '',
        _data(j['criado_em']) ?? DateTime.now(),
      );
}

class ItemRanking {
  final int posicao;
  final String autor;
  final int pontos;
  final bool souEu;
  const ItemRanking(this.posicao, this.autor, this.pontos, this.souEu);
  factory ItemRanking.deJson(Map<String, dynamic> j) =>
      ItemRanking(_int(j['posicao']), j['autor']?.toString() ?? '', _int(j['pontos']), j['sou_eu'] == true);
}

class Notificacao {
  final int id;
  final int postoId;
  final int produtoId;
  final double precoAnterior;
  final double precoNovo;
  final bool lida;
  final DateTime criadoEm;
  final String? nomePosto;
  const Notificacao({
    required this.id,
    required this.postoId,
    required this.produtoId,
    required this.precoAnterior,
    required this.precoNovo,
    required this.lida,
    required this.criadoEm,
    this.nomePosto,
  });
  factory Notificacao.deJson(Map<String, dynamic> j) {
    final posto = j['postos'];
    String? nome;
    if (posto is Map) {
      nome = nomeExibicao((posto['nome_exibicao'] ?? posto['razao_social'] ?? '').toString());
    }
    return Notificacao(
      id: _int(j['id']),
      postoId: _int(j['posto_id']),
      produtoId: _int(j['produto_id']),
      precoAnterior: _num(j['preco_anterior']) ?? 0,
      precoNovo: _num(j['preco_novo']) ?? 0,
      lida: j['lida'] == true,
      criadoEm: _data(j['criado_em']) ?? DateTime.now(),
      nomePosto: nome,
    );
  }
}

/// "AUTO POSTO SAKAMOTO LTDA" -> "Auto Posto Sakamoto"
String nomeExibicao(String razao) {
  final sufixos = RegExp(r'\s+(-\s*)?(LTDA\.?|EIRELI|ME|EPP|S\.?A\.?|S/A|LIMITADA)(?=\s|$)', caseSensitive: false);
  var n = razao.replaceAll(sufixos, '').replaceAll(RegExp(r'\s+'), ' ').trim();
  n = n.replaceAll(RegExp(r'[\s\-,.]+$'), '');
  if (n.isEmpty) n = razao.trim();
  const minusculas = {'de', 'da', 'do', 'das', 'dos', 'e'};
  final palavras = n.toLowerCase().split(' ');
  return [
    for (var i = 0; i < palavras.length; i++)
      if (palavras[i].isEmpty)
        palavras[i]
      else if (i > 0 && minusculas.contains(palavras[i]))
        palavras[i]
      else
        palavras[i][0].toUpperCase() + palavras[i].substring(1),
  ].join(' ');
}
