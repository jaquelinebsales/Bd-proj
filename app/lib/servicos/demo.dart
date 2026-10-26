import 'dart:math';

import '../modelos/modelos.dart';

/// Dados de exemplo para o modo demonstração (--dart-define=DEMO=true).
/// Servem para ver e testar as telas antes de ligar o app ao Supabase.
/// Nada aqui é dado real.
class Demo {
  Demo._();

  static DateTime _ha(Duration d) => DateTime.now().subtract(d);

  static PrecoAtual _com(int produto, double preco, Duration idade, {int conf = 3, bool confirmado = true}) => PrecoAtual(
        produtoId: produto,
        preco: preco,
        fonte: FontePreco.comunidade,
        situacao: confirmado ? SituacaoPreco.confirmado : SituacaoPreco.naoConfirmado,
        atualizadoEm: _ha(idade),
        confirmacoes: conf,
      );

  static PrecoAtual _anp(int produto, double preco, int dias) => PrecoAtual(
        produtoId: produto,
        preco: preco,
        fonte: FontePreco.anp,
        situacao: SituacaoPreco.oficial,
        atualizadoEm: _ha(Duration(days: dias)),
      );

  static final postos = <PostoResumo>[
    PostoResumo(
      id: 1, nome: 'Posto Vale Verde', bandeira: 'Ipiranga', endereco: 'Av. João Pessoa, 6094', bairro: 'Montese',
      municipio: 'Fortaleza', uf: 'CE', lat: -3.7625, lon: -38.5402, notaMedia: 4.6, totalAvaliacoes: 128,
      municipioPesquisadoAnp: true,
      precos: [
        _com(1, 5.99, const Duration(hours: 2)),
        _anp(3, 4.29, 4),
        _com(5, 6.32, const Duration(days: 9), conf: 2),
        _com(6, 4.79, const Duration(hours: 5), conf: 1, confirmado: false),
      ],
    ),
    PostoResumo(
      id: 2, nome: 'Auto Posto Aldeota', bandeira: 'Vibra', endereco: 'Av. Santos Dumont, 2000', bairro: 'Aldeota',
      municipio: 'Fortaleza', uf: 'CE', lat: -3.7350, lon: -38.5100, notaMedia: 4.1, totalAvaliacoes: 57,
      municipioPesquisadoAnp: true,
      precos: [_anp(1, 6.09, 3), _anp(2, 6.29, 3), _com(3, 4.39, const Duration(hours: 20), conf: 2)],
    ),
    PostoResumo(
      id: 3, nome: 'Posto Beira Mar', bandeira: 'Shell', endereco: 'Av. Beira Mar, 3500', bairro: 'Meireles',
      municipio: 'Fortaleza', uf: 'CE', lat: -3.7250, lon: -38.4950, notaMedia: 3.8, totalAvaliacoes: 211,
      municipioPesquisadoAnp: true,
      precos: [_com(1, 6.19, const Duration(hours: 20), conf: 2), _com(2, 6.49, const Duration(hours: 20), conf: 2)],
    ),
    PostoResumo(
      id: 4, nome: 'Posto Messejana', bandeira: 'Bandeira branca', endereco: 'Rua Coronel Guilherme Alencar, 120',
      bairro: 'Messejana', municipio: 'Fortaleza', uf: 'CE', lat: -3.8300, lon: -38.4900, notaMedia: 4.4,
      totalAvaliacoes: 33, municipioPesquisadoAnp: true, precisao: PrecisaoLocalizacao.rua,
      precos: [_com(1, 5.89, const Duration(hours: 1), conf: 5), _com(3, 4.19, const Duration(hours: 1), conf: 4)],
    ),
    PostoResumo(
      id: 5, nome: 'Posto Parangaba', bandeira: 'Ale', endereco: 'Av. João Pessoa, 7500', bairro: 'Parangaba',
      municipio: 'Fortaleza', uf: 'CE', lat: -3.7780, lon: -38.5600, notaMedia: 3.2, totalAvaliacoes: 12,
      municipioPesquisadoAnp: true,
      precos: [_anp(1, 6.05, 6), _anp(4, 5.99, 6)],
    ),
    PostoResumo(
      id: 6, nome: 'Posto Itaitinga', bandeira: 'Bandeira branca', endereco: 'Rua Principal, 10', bairro: 'Centro',
      municipio: 'Itaitinga', uf: 'CE', lat: -3.9690, lon: -38.5280, totalAvaliacoes: 0,
      precisao: PrecisaoLocalizacao.cepCidade,
      precos: [
        PrecoAtual(
          produtoId: 1, preco: 6.14, fonte: FontePreco.estimativa, situacao: SituacaoPreco.estimado,
          atualizadoEm: _ha(const Duration(days: 2)), margem: 0.29, distanciaKm: 26.1,
        ),
      ],
    ),
    // Com coordenada: entra no mapa com o pino tracejado da estimativa
    PostoResumo(
      id: 7, nome: 'Posto Bom Jardim', bandeira: 'Bandeira branca', endereco: 'Rua Oscar Araripe, 900',
      bairro: 'Bom Jardim', municipio: 'Fortaleza', uf: 'CE', lat: -3.7850, lon: -38.5830, totalAvaliacoes: 0,
      precos: [
        PrecoAtual(
          produtoId: 1, preco: 6.14, fonte: FontePreco.estimativa, situacao: SituacaoPreco.estimado,
          atualizadoEm: _ha(const Duration(days: 2)), margem: 0.25, distanciaKm: 7.4,
        ),
      ],
    ),
    // Vende só diesel e GNV: no mapa de gasolina aparece sem preço
    PostoResumo(
      id: 8, nome: 'Posto Mondubim', bandeira: 'Vibra', endereco: 'Av. Presidente Costa e Silva, 3100',
      bairro: 'Mondubim', municipio: 'Fortaleza', uf: 'CE', lat: -3.7980, lon: -38.5200, notaMedia: 4.0,
      totalAvaliacoes: 9, municipioPesquisadoAnp: true,
      precos: [_anp(5, 6.27, 5), _com(6, 4.69, const Duration(hours: 6), conf: 2)],
    ),
  ];

  static List<PostoResumo> buscar(String texto) {
    final t = texto.toLowerCase();
    return postos
        .where((p) => '${p.nome} ${p.endereco} ${p.bairro} ${p.municipio} ${p.uf} ${p.bandeira}'.toLowerCase().contains(t))
        .toList();
  }

  static PostoDetalhe detalhe(int id) {
    final p = postos.firstWhere((e) => e.id == id, orElse: () => postos.first);
    return PostoDetalhe(
      resumo: p,
      cnpj: '0${id}123456000190'.padRight(14, '0').substring(0, 14),
      razaoSocial: '${p.nome.toUpperCase()} COMERCIO DE COMBUSTIVEIS LTDA',
      cep: '60410000',
      localizacaoValidada: p.precisao == PrecisaoLocalizacao.exata,
      raioEnvioM: p.precisao.raioEnvioM(),
      produtosVendidos: p.precos.map((e) => e.produtoId).toList(),
      distribuicaoNotas: id == 1 ? const {5: 84, 4: 28, 3: 9, 2: 4, 1: 2, 0: 1} : const {5: 3, 4: 2, 3: 1, 2: 0, 1: 0, 0: 0},
      enviosAguardando: id == 1 ? const {6: 1} : const {},
      sincronizadoEm: _ha(const Duration(days: 2)),
    );
  }

  static List<PontoHistorico> historico(int produto, int dias) {
    final r = Random(produto * 31 + dias);
    final pontos = <PontoHistorico>[];
    var preco = produto == 3 ? 4.45 : 6.35;
    for (var d = dias; d >= 0; d -= 7) {
      preco += (r.nextDouble() - 0.55) * 0.06;
      pontos.add(PontoHistorico(DateTime.now().subtract(Duration(days: d)), double.parse(preco.toStringAsFixed(2)), true, true));
    }
    for (var d = min(dias, 28); d >= 0; d -= 3) {
      pontos.add(PontoHistorico(
        DateTime.now().subtract(Duration(days: d)),
        double.parse((preco - 0.12 + (r.nextDouble() - 0.5) * 0.08).toStringAsFixed(2)),
        false,
        r.nextDouble() > 0.25,
      ));
    }
    pontos.sort((a, b) => a.dia.compareTo(b.dia));
    return pontos;
  }

  static List<Contribuicao> contribuicoes() => [
        Contribuicao(id: 1, autor: 'Carla M.', souEu: false, preco: 5.99, status: 'confirmado', editado: false, criadoEm: _ha(const Duration(hours: 1))),
        Contribuicao(id: 2, autor: 'Bruno L.', souEu: false, preco: 5.99, status: 'confirmado', editado: true, criadoEm: _ha(const Duration(hours: 2))),
        Contribuicao(id: 3, autor: 'Ana S.', souEu: false, preco: 5.99, status: 'confirmado', editado: false, criadoEm: _ha(const Duration(hours: 4))),
        Contribuicao(id: 4, autor: 'João T.', souEu: false, preco: 6.15, status: 'expirado', editado: false, criadoEm: _ha(const Duration(days: 3))),
      ];

  static List<Avaliacao> avaliacoes() => [
        Avaliacao(id: 1, autor: 'Mariana C.', nota: 5, comentario: 'Atendimento rápido e o preço da gasolina bate com o painel.', votosUteis: 12, criadoEm: _ha(const Duration(days: 2))),
        Avaliacao(id: 2, autor: 'Rafael P.', nota: 4, comentario: 'Bom posto, mas a calibragem estava quebrada.', votosUteis: 5, criadoEm: _ha(const Duration(days: 6))),
        Avaliacao(id: 3, autor: 'Lúcia F.', nota: 5, comentario: 'Conveniência limpa e banheiro aberto a noite toda.', votosUteis: 2, criadoEm: _ha(const Duration(days: 11))),
      ];

  static ResumoPerfil perfil() => ResumoPerfil(
        id: 'demo',
        nome: 'Carla M.',
        pontos: 1840,
        confiabilidade: 0.86,
        totalAvaliacoes: 4,
        totalEnvios: 37,
        enviosConfirmados: 33,
        posicaoRanking: 1,
        ultimosEnvios: envios().take(10).toList(),
        ultimasAvaliacoes: minhasAvaliacoes(),
      );

  /// Os 37 preços enviados pela usuária de exemplo, do mais recente ao mais antigo: 33 confirmados, 1 aguardando,
  /// 2 contrariados e 1 sem confirmação, como no resumo do perfil
  static List<Map<String, dynamic>> envios() {
    const postos = [(1, 'Posto Vale Verde'), (4, 'Posto Messejana'), (2, 'Auto Posto Aldeota'), (5, 'Posto Parangaba'),
                    (3, 'Posto Beira Mar'), (8, 'Posto Mondubim')];
    const produtos = [(1, 5.99), (3, 4.19), (1, 6.09), (5, 6.32), (3, 4.29), (6, 4.79)];
    return [
      for (var i = 0; i < 37; i++)
        {
          'id': 37 - i,
          'posto_id': postos[i % 6].$1,
          'posto': postos[i % 6].$2,
          'produto_id': produtos[i % 6].$1,
          // os mais antigos, um pouco mais altos (o preço veio caindo)
          'preco': ((produtos[i % 6].$2 + 0.03 * (i ~/ 6)) * 100).round() / 100,
          'status': i == 1 ? 'pendente' : (i == 9 || i == 22) ? 'contestado' : i == 30 ? 'expirado' : 'confirmado',
          'criado_em': _ha(Duration(hours: 2 + i * 19)).toUtc().toIso8601String(),
        },
    ];
  }

  /// As 4 avaliações da usuária de exemplo
  static List<Map<String, dynamic>> minhasAvaliacoes() => [
        {'id': 41, 'posto_id': 1, 'posto': 'Posto Vale Verde', 'nota': 5, 'votos_uteis': 12,
         'comentario': 'Atendimento rápido e o preço da gasolina bate com o painel.',
         'criado_em': _ha(const Duration(days: 2)).toUtc().toIso8601String()},
        {'id': 37, 'posto_id': 3, 'posto': 'Posto Beira Mar', 'nota': 4, 'votos_uteis': 3, 'comentario': null,
         'criado_em': _ha(const Duration(days: 9)).toUtc().toIso8601String()},
        {'id': 22, 'posto_id': 4, 'posto': 'Posto Messejana', 'nota': 5, 'votos_uteis': 7,
         'comentario': 'O preço do etanol está sempre atualizado no painel.',
         'criado_em': _ha(const Duration(days: 23)).toUtc().toIso8601String()},
        {'id': 9, 'posto_id': 2, 'posto': 'Auto Posto Aldeota', 'nota': 3, 'votos_uteis': 1,
         'comentario': 'Fila grande no fim da tarde, mas o atendimento é cordial.',
         'criado_em': _ha(const Duration(days: 41)).toUtc().toIso8601String()},
      ];

  static List<MovimentoPontos> extrato() => [
        MovimentoPontos('envio_confirmado', 10, 'Preço confirmado: Gasolina comum no Posto Vale Verde', _ha(const Duration(hours: 2))),
        MovimentoPontos('bonus_primeiro', 5, 'Primeiro envio do consenso', _ha(const Duration(hours: 2))),
        MovimentoPontos('posicao_confirmada', 5, 'Posição confirmada: Posto Messejana', _ha(const Duration(days: 2))),
        MovimentoPontos('envio_contestado', -5, 'Envio contestado: Etanol no Auto Posto Aldeota', _ha(const Duration(days: 4))),
        MovimentoPontos('envio_confirmado', 20, 'Preço confirmado em cidade sem pesquisa da ANP', _ha(const Duration(days: 6))),
      ];

  static List<Notificacao> notificacoes() => [
        Notificacao(id: 1, postoId: 1, produtoId: 1, precoAnterior: 6.09, precoNovo: 5.99, lida: false, criadoEm: _ha(const Duration(hours: 3)), nomePosto: 'Posto Vale Verde'),
        Notificacao(id: 2, postoId: 2, produtoId: 3, precoAnterior: 4.29, precoNovo: 4.39, lida: false, criadoEm: _ha(const Duration(hours: 20)), nomePosto: 'Auto Posto Aldeota'),
        Notificacao(id: 3, postoId: 1, produtoId: 5, precoAnterior: 6.45, precoNovo: 6.32, lida: true, criadoEm: _ha(const Duration(days: 5)), nomePosto: 'Posto Vale Verde'),
      ];

  static List<ItemRanking> ranking() => const [
        ItemRanking(1, 'Carla M.', 1840, false),
        ItemRanking(2, 'Bruno L.', 1575, false),
        ItemRanking(3, 'Ana S.', 1210, false),
        ItemRanking(4, 'Diego R.', 980, false),
        ItemRanking(5, 'Patrícia A.', 760, false),
        ItemRanking(6, 'João T.', 515, false),
        ItemRanking(7, 'Helena V.', 340, false),
        ItemRanking(8, 'Marcos D.', 125, false),
      ];
}
