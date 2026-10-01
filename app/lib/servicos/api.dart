import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../modelos/modelos.dart';
import 'demo.dart';

/// Erro com mensagem pronta para mostrar ao usuário.
class ErroApp implements Exception {
  final String mensagem;
  const ErroApp(this.mensagem);
  @override
  String toString() => mensagem;
}

class _ItemCache {
  final DateTime quando;
  final Object valor;
  _ItemCache(this.valor) : quando = DateTime.now();
}

/// Acesso ao backend. Consultas passam por um cache em memória para evitar
/// chamadas repetidas ao mover o mapa (item 17 do documento de requisitos).
class Api {
  Api._();
  static final instancia = Api._();

  SupabaseClient get _db => Supabase.instance.client;
  final _cache = <String, _ItemCache>{};

  Future<T> _comCache<T extends Object>(String chave, Duration validade, Future<T> Function() buscar) async {
    final c = _cache[chave];
    if (c != null && DateTime.now().difference(c.quando) < validade) return c.valor as T;
    final v = await buscar();
    _cache[chave] = _ItemCache(v);
    if (_cache.length > 200) _cache.remove(_cache.keys.first);
    return v;
  }

  void invalidarPosto(int id) => _cache.removeWhere((k, _) => k.startsWith('posto:$id') || k.startsWith('area:'));

  Future<T> _proteger<T>(Future<T> Function() f) async {
    if (!Config.configurado) {
      throw const ErroApp('O app ainda não foi ligado ao Supabase. Veja config/app.example.json.');
    }
    try {
      return await f();
    } on ErroApp {
      rethrow;
    } on AuthException catch (e) {
      throw ErroApp(traduzirErroAuth(e));
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = d is Map ? d['erro']?.toString() : null;
      throw ErroApp(msg ?? 'Não foi possível concluir. Tente de novo.');
    } on PostgrestException catch (e) {
      throw ErroApp(e.code == '42501' ? 'Você não tem permissão para isso.' : 'Não foi possível carregar os dados. Tente de novo.');
    } catch (_) {
      throw const ErroApp('Sem conexão com o servidor. Verifique sua internet e tente de novo.');
    }
  }

  List<PostoResumo> _postos(dynamic dados) =>
      (dados as List).map((e) => PostoResumo.deJson(Map<String, dynamic>.from(e as Map))).toList();

  // ------------------------------------------------------------------ consultas públicas

  /// Postos na área visível do mapa. A área é arredondada para reaproveitar o cache.
  Future<List<PostoResumo>> postosNaArea(double latMin, double lonMin, double latMax, double lonMax) {
    if (Config.demo) {
      return Future.value(Demo.postos
          .where((p) => p.precisao.noMapa && p.lat! >= latMin && p.lat! <= latMax && p.lon! >= lonMin && p.lon! <= lonMax)
          .toList());
    }
    double r(double v) => (v * 50).floorToDouble() / 50;
    double r2(double v) => (v * 50).ceilToDouble() / 50;
    final chave = 'area:${r(latMin)}:${r(lonMin)}:${r2(latMax)}:${r2(lonMax)}';
    return _proteger(() => _comCache(chave, const Duration(minutes: 3), () async {
          final d = await _db.rpc('postos_na_area', params: {
            'p_lat_min': r(latMin),
            'p_lon_min': r(lonMin),
            'p_lat_max': r2(latMax),
            'p_lon_max': r2(lonMax),
            'p_limite': 400,
          });
          final lista = _postos(d);
          _salvarUltimaArea(d);
          return lista;
        }));
  }

  Future<List<PostoResumo>> postosProximos(double lat, double lon, {double raioKm = 20}) => Config.demo
      ? Future.value(Demo.postos.where((p) => p.precisao.noMapa).toList())
      : _proteger(() => _comCache('prox:${lat.toStringAsFixed(3)}:${lon.toStringAsFixed(3)}:$raioKm',
          const Duration(minutes: 3), () async {
        final d = await _db.rpc('postos_proximos', params: {'p_lat': lat, 'p_lon': lon, 'p_raio_km': raioKm, 'p_limite': 300});
        return _postos(d);
      }));

  Future<List<PostoResumo>> buscar(String texto, {double? lat, double? lon}) =>
      Config.demo ? Future.value(Demo.buscar(texto)) : _proteger(() async {
        final d = await _db.rpc('buscar_postos', params: {'p_texto': texto, 'p_lat': lat, 'p_lon': lon, 'p_limite': 60});
        return _postos(d);
      });

  Future<List<PostoResumo>> postosPorIds(List<int> ids) => Config.demo
      ? Future.value(Demo.postos.where((p) => ids.contains(p.id)).toList())
      : _proteger(() async {
        if (ids.isEmpty) return <PostoResumo>[];
        final d = await _db.rpc('postos_por_ids', params: {'p_ids': ids});
        return _postos(d);
      });

  Future<PostoDetalhe> detalhe(int id, {bool forcar = false}) {
    if (Config.demo) return Future.value(Demo.detalhe(id));
    if (forcar) _cache.remove('posto:$id');
    return _proteger(() => _comCache('posto:$id', const Duration(minutes: 2), () async {
          final d = await _db.rpc('detalhe_posto', params: {'p_id': id});
          if (d == null) throw const ErroApp('Este posto não está mais disponível.');
          return PostoDetalhe.deJson(Map<String, dynamic>.from(d as Map));
        }));
  }

  Future<List<PontoHistorico>> historico(int posto, int produto, int dias) =>
      Config.demo ? Future.value(Demo.historico(produto, dias)) : _proteger(() =>
      _comCache('posto:$posto:hist:$produto:$dias', const Duration(minutes: 10), () async {
        final d = await _db.rpc('historico_precos', params: {'p_posto': posto, 'p_produto': produto, 'p_dias': dias});
        return (d as List).map((e) => PontoHistorico.deJson(Map<String, dynamic>.from(e as Map))).toList();
      }));

  Future<List<Contribuicao>> contribuicoes(int posto, int produto) =>
      Config.demo ? Future.value(Demo.contribuicoes()) : _proteger(() async {
        final d = await _db.rpc('contribuicoes', params: {'p_posto': posto, 'p_produto': produto});
        return (d as List).map((e) => Contribuicao.deJson(Map<String, dynamic>.from(e as Map))).toList();
      });

  Future<List<Avaliacao>> avaliacoes(int posto, {String ordem = 'recentes', int offset = 0}) =>
      Config.demo ? Future.value(offset > 0 ? <Avaliacao>[] : Demo.avaliacoes()) : _proteger(() async {
        final d = await _db.rpc('avaliacoes_posto',
            params: {'p_posto': posto, 'p_ordem': ordem, 'p_limite': 20, 'p_offset': offset});
        return (d as List).map((e) => Avaliacao.deJson(Map<String, dynamic>.from(e as Map))).toList();
      });

  Future<List<ItemRanking>> ranking() => Config.demo ? Future.value(Demo.ranking()) : _proteger(() async {
        final d = await _db.rpc('ranking', params: {'p_limite': 50});
        return (d as List).map((e) => ItemRanking.deJson(Map<String, dynamic>.from(e as Map))).toList();
      });

  // ------------------------------------------------------------------ usuário logado

  Future<ResumoPerfil?> meuResumo() => _proteger(() async {
        final d = await _db.rpc('meu_resumo');
        return d == null ? null : ResumoPerfil.deJson(Map<String, dynamic>.from(d as Map));
      });

  Future<List<PostoResumo>> meusFavoritos() => _proteger(() async => _postos(await _db.rpc('meus_favoritos')));

  Future<void> favoritar(int posto, bool favorito) => _proteger(() async {
        final uid = _db.auth.currentUser!.id;
        if (favorito) {
          await _db.from('favoritos').upsert({'usuario_id': uid, 'posto_id': posto});
        } else {
          await _db.from('favoritos').delete().eq('usuario_id', uid).eq('posto_id', posto);
        }
        _cache.remove('posto:$posto');
      });

  Future<void> notificarFavorito(int posto, bool notificar) => _proteger(() async {
        final uid = _db.auth.currentUser!.id;
        await _db.from('favoritos').update({'notificar': notificar}).eq('usuario_id', uid).eq('posto_id', posto);
      });

  Future<void> salvarAvaliacao(int posto, int nota, String? comentario, {int? id}) => _proteger(() async {
        final texto = (comentario ?? '').trim();
        final dados = {'nota': nota, 'comentario': texto.isEmpty ? null : texto};
        if (id == null) {
          await _db.from('avaliacoes').insert({...dados, 'posto_id': posto, 'usuario_id': _db.auth.currentUser!.id});
        } else {
          await _db.from('avaliacoes').update(dados).eq('id', id);
        }
        invalidarPosto(posto);
      });

  Future<void> apagarAvaliacao(int posto, int id) => _proteger(() async {
        await _db.from('avaliacoes').delete().eq('id', id);
        invalidarPosto(posto);
      });

  Future<void> votarUtil(int avaliacao, bool util) => _proteger(() async {
        final uid = _db.auth.currentUser!.id;
        if (util) {
          await _db.from('avaliacao_votos').upsert({'avaliacao_id': avaliacao, 'usuario_id': uid});
        } else {
          await _db.from('avaliacao_votos').delete().eq('avaliacao_id', avaliacao).eq('usuario_id', uid);
        }
      });

  Future<List<MovimentoPontos>> extratoPontos() => _proteger(() async {
        final d = await _db
            .from('pontos_movimentos')
            .select('tipo, pontos, descricao, criado_em')
            .order('criado_em', ascending: false)
            .limit(100);
        return d.map((e) => MovimentoPontos.deJson(e)).toList();
      });

  Future<List<Notificacao>> notificacoes() => _proteger(() async {
        final d = await _db
            .from('notificacoes')
            .select('id, posto_id, produto_id, preco_anterior, preco_novo, lida, criado_em, postos(nome_exibicao, razao_social)')
            .order('criado_em', ascending: false)
            .limit(100);
        return d.map((e) => Notificacao.deJson(e)).toList();
      });

  Future<void> marcarLidas() => _proteger(() async {
        await _db.from('notificacoes').update({'lida': true}).eq('lida', false);
      });

  /// Envia os preços revisados. A foto não é enviada: só os valores e o texto lido.
  Future<Map<String, dynamic>> enviarPrecos({
    required int postoId,
    required double latitude,
    required double longitude,
    required List<Map<String, dynamic>> itens,
    String? textoLido,
    int? duracaoLeituraMs,
  }) =>
      Config.demo
          ? Future.value({
              'itens': [
                for (final (i, item) in itens.indexed)
                  {
                    'produto_id': item['produto_id'],
                    'preco': item['preco'],
                    'status': i == 0 ? 'confirmado' : 'pendente',
                    'em_revisao': false,
                  },
              ],
              'ignorados': <int>[],
              'mensagem': '1 preço confirmado com outros usuários. Seus pontos já foram creditados.',
            })
          : _proteger(() async {
        final r = await _db.functions.invoke('enviar-precos', body: {
          'posto_id': postoId,
          'latitude': latitude,
          'longitude': longitude,
          'itens': itens,
          'ocr_texto': textoLido,
          'ocr_duracao_ms': duracaoLeituraMs,
          'app_versao': Config.versao,
        });
        invalidarPosto(postoId);
        return Map<String, dynamic>.from(r.data as Map);
      });

  /// "Estou neste posto": informa a posição do posto. Não envia preço.
  Future<Map<String, dynamic>> corrigirPosicao({
    required int postoId,
    required double latitude,
    required double longitude,
    required double precisaoGpsM,
  }) =>
      Config.demo
          ? Future.value({
              'status': 'aguardando',
              'mensagem': 'Obrigado! Quando outra pessoa que esteja neste posto também informar a posição, '
                  'ela será confirmada e você ganha pontos.',
            })
          : _proteger(() async {
              final r = await _db.functions.invoke('corrigir-posicao', body: {
                'posto_id': postoId,
                'latitude': latitude,
                'longitude': longitude,
                'precisao_gps_m': precisaoGpsM,
              });
              invalidarPosto(postoId);
              return Map<String, dynamic>.from(r.data as Map);
            });

  Future<void> excluirConta() => _proteger(() async {
        await _db.functions.invoke('excluir-conta');
      });

  // ------------------------------------------------------------------ cache persistente

  Future<void> _salvarUltimaArea(dynamic dados) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ultima_area', jsonEncode(dados));
    } catch (_) {}
  }

  /// Últimos postos vistos, para abrir o mapa mesmo sem internet.
  Future<List<PostoResumo>> ultimaAreaSalva() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString('ultima_area');
      return s == null ? [] : _postos(jsonDecode(s));
    } catch (_) {
      return [];
    }
  }
}

String traduzirErroAuth(AuthException e) {
  final m = e.message.toLowerCase();
  if (m.contains('invalid login') || m.contains('invalid credentials')) return 'E-mail ou senha incorretos.';
  if (m.contains('email not confirmed')) return 'Confirme seu e-mail antes de entrar. Procure a mensagem na sua caixa de entrada.';
  if (m.contains('already registered') || m.contains('already been registered')) {
    return 'Já existe uma conta com este e-mail. Entre ou recupere a senha.';
  }
  if (m.contains('password') && (m.contains('weak') || m.contains('at least') || m.contains('characters'))) {
    return 'A senha precisa ter pelo menos 8 caracteres, com letras e números.';
  }
  if (m.contains('rate limit') || m.contains('too many')) return 'Muitas tentativas. Aguarde alguns minutos e tente de novo.';
  if (m.contains('same password') || m.contains('different from the old')) return 'A nova senha precisa ser diferente da atual.';
  return 'Não foi possível concluir: ${e.message}';
}
