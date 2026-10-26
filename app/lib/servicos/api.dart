import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../modelos/modelos.dart';
import '../util/nova_tentativa.dart';
import '../util/senha.dart';
import 'demo.dart';
import 'monitor_demo.dart';

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
    final v = await lerComNovaTentativa(buscar);
    _cache[chave] = _ItemCache(v);
    if (_cache.length > 200) _cache.remove(_cache.keys.first);
    return v;
  }

  void invalidarPosto(int id) => _cache.removeWhere((k, _) => k.startsWith('posto:$id') || k.startsWith('area:'));

  /// Demonstração: devolve o dado local e conta ao painel qual chamada o app real faria.
  Future<T> _demo<T>(T valor, String chamada, {String? detalhe, List<String> camadas = const ['api', 'banco']}) {
    MonitorDemo.evento(chamada, detalhe: detalhe, camadas: camadas);
    return Future.value(valor);
  }

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
      final lista = Demo.postos
          .where((p) => p.precisao.noMapa && p.lat! >= latMin && p.lat! <= latMax && p.lon! >= lonMin && p.lon! <= lonMax)
          .toList();
      return _demo(lista, 'RPC postos_na_area', detalhe: '${lista.length} postos na área visível · PostGIS');
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
            'p_limite': 500,
          });
          final lista = _postos(d);
          _salvarUltimaArea(d);
          return lista;
        }));
  }

  Future<List<PostoResumo>> postosProximos(double lat, double lon, {double raioKm = 20, int limite = 300}) => Config.demo
      ? _demo(Demo.postos.where((p) => p.precisao.noMapa).toList(), 'RPC postos_proximos',
          detalhe: 'raio de ${raioKm.toStringAsFixed(0)} km · PostGIS')
      : _proteger(() => _comCache('prox:${lat.toStringAsFixed(3)}:${lon.toStringAsFixed(3)}:$raioKm:$limite',
          const Duration(minutes: 3), () async {
        final d = await _db.rpc('postos_proximos', params: {'p_lat': lat, 'p_lon': lon, 'p_raio_km': raioKm, 'p_limite': limite});
        return _postos(d);
      }));

  Future<List<PostoResumo>> buscar(String texto, {double? lat, double? lon}) =>
      Config.demo ? _demo(Demo.buscar(texto), 'RPC buscar_postos', detalhe: '"$texto"') : _proteger(() async {
        final d = await _db.rpc('buscar_postos', params: {'p_texto': texto, 'p_lat': lat, 'p_lon': lon, 'p_limite': 60});
        return _postos(d);
      });

  Future<List<PostoResumo>> postosPorIds(List<int> ids) => Config.demo
      ? _demo(Demo.postos.where((p) => ids.contains(p.id)).toList(), 'RPC postos_por_ids', detalhe: '${ids.length} postos')
      : _proteger(() async {
        if (ids.isEmpty) return <PostoResumo>[];
        final d = await _db.rpc('postos_por_ids', params: {'p_ids': ids});
        return _postos(d);
      });

  Future<PostoDetalhe> detalhe(int id, {bool forcar = false}) {
    if (Config.demo) {
      final d = Demo.detalhe(id);
      return _demo(d, 'RPC detalhe_posto', detalhe: d.resumo.nome);
    }
    if (forcar) _cache.remove('posto:$id');
    return _proteger(() => _comCache('posto:$id', const Duration(minutes: 2), () async {
          final d = await _db.rpc('detalhe_posto', params: {'p_id': id});
          if (d == null) throw const ErroApp('Este posto não está mais disponível.');
          return PostoDetalhe.deJson(Map<String, dynamic>.from(d as Map));
        }));
  }

  Future<List<PontoHistorico>> historico(int posto, int produto, int dias) =>
      Config.demo
          ? _demo(Demo.historico(produto, dias), 'RPC historico_precos', detalhe: '${Produto.porId(produto).nome} · $dias dias')
          : _proteger(() =>
      _comCache('posto:$posto:hist:$produto:$dias', const Duration(minutes: 10), () async {
        final d = await _db.rpc('historico_precos', params: {'p_posto': posto, 'p_produto': produto, 'p_dias': dias});
        return (d as List).map((e) => PontoHistorico.deJson(Map<String, dynamic>.from(e as Map))).toList();
      }));

  Future<List<Contribuicao>> contribuicoes(int posto, int produto) =>
      Config.demo ? _demo(Demo.contribuicoes(), 'RPC contribuicoes', detalhe: Produto.porId(produto).nome) : _proteger(() async {
        final d = await _db.rpc('contribuicoes', params: {'p_posto': posto, 'p_produto': produto});
        return (d as List).map((e) => Contribuicao.deJson(Map<String, dynamic>.from(e as Map))).toList();
      });

  Future<List<Avaliacao>> avaliacoes(int posto, {String ordem = 'recentes', int offset = 0}) =>
      Config.demo
          ? _demo(offset > 0 ? <Avaliacao>[] : Demo.avaliacoes(), 'RPC avaliacoes_posto', detalhe: 'ordem: $ordem')
          : _proteger(() async {
        final d = await _db.rpc('avaliacoes_posto',
            params: {'p_posto': posto, 'p_ordem': ordem, 'p_limite': 20, 'p_offset': offset});
        return (d as List).map((e) => Avaliacao.deJson(Map<String, dynamic>.from(e as Map))).toList();
      });

  Future<List<ItemRanking>> ranking() => Config.demo ? _demo(Demo.ranking(), 'RPC ranking') : _proteger(() async {
        final d = await _db.rpc('ranking', params: {'p_limite': 50});
        return (d as List).map((e) => ItemRanking.deJson(Map<String, dynamic>.from(e as Map))).toList();
      });

  // ------------------------------------------------------------------ usuário logado

  Future<ResumoPerfil?> meuResumo() => Config.demo
      ? _demo<ResumoPerfil?>(Demo.perfil(), 'RPC meu_resumo', detalhe: 'sessão autenticada · RLS')
      : _proteger(() async {
        final d = await _db.rpc('meu_resumo');
        return d == null ? null : ResumoPerfil.deJson(Map<String, dynamic>.from(d as Map));
      });

  Future<List<PostoResumo>> meusFavoritos() => Config.demo
      ? _demo(Demo.postos.where((p) => p.id == 1 || p.id == 2).toList(), 'RPC meus_favoritos', detalhe: 'RLS · só a própria conta')
      : _proteger(() async => _postos(await _db.rpc('meus_favoritos')));

  Future<void> favoritar(int posto, bool favorito) => Config.demo
      ? _demo<void>(null, favorito ? 'favoritos · insert' : 'favoritos · delete', detalhe: 'RLS · só a própria conta')
      : _proteger(() async {
        final uid = _db.auth.currentUser!.id;
        if (favorito) {
          await _db.from('favoritos').upsert({'usuario_id': uid, 'posto_id': posto});
        } else {
          await _db.from('favoritos').delete().eq('usuario_id', uid).eq('posto_id', posto);
        }
        _cache.remove('posto:$posto');
      });

  Future<void> notificarFavorito(int posto, bool notificar) => Config.demo
      ? _demo<void>(null, 'favoritos · update', detalhe: notificar ? 'avisar quando o preço mudar' : 'sem aviso')
      : _proteger(() async {
        final uid = _db.auth.currentUser!.id;
        await _db.from('favoritos').update({'notificar': notificar}).eq('usuario_id', uid).eq('posto_id', posto);
      });

  Future<void> salvarAvaliacao(int posto, int nota, String? comentario, {int? id}) => Config.demo
      ? _demo<void>(null, id == null ? 'avaliacoes · insert' : 'avaliacoes · update', detalhe: '$nota estrelas')
      : _proteger(() async {
        final texto = (comentario ?? '').trim();
        final dados = {'nota': nota, 'comentario': texto.isEmpty ? null : texto};
        if (id == null) {
          await _db.from('avaliacoes').insert({...dados, 'posto_id': posto, 'usuario_id': _db.auth.currentUser!.id});
        } else {
          await _db.from('avaliacoes').update(dados).eq('id', id);
        }
        invalidarPosto(posto);
      });

  Future<void> apagarAvaliacao(int posto, int id) => Config.demo
      ? _demo<void>(null, 'avaliacoes · delete')
      : _proteger(() async {
        await _db.from('avaliacoes').delete().eq('id', id);
        invalidarPosto(posto);
      });

  Future<void> votarUtil(int avaliacao, bool util) => Config.demo
      ? _demo<void>(null, util ? 'avaliacao_votos · insert' : 'avaliacao_votos · delete')
      : _proteger(() async {
        final uid = _db.auth.currentUser!.id;
        if (util) {
          await _db.from('avaliacao_votos').upsert({'avaliacao_id': avaliacao, 'usuario_id': uid});
        } else {
          await _db.from('avaliacao_votos').delete().eq('avaliacao_id', avaliacao).eq('usuario_id', uid);
        }
      });

  /// Todos os preços enviados pela conta, do mais recente ao mais antigo, em páginas
  Future<List<Map<String, dynamic>>> meusEnvios({int limite = 50, int offset = 0}) => Config.demo
      ? _demo(Demo.envios().skip(offset).take(limite).toList(), 'RPC meus_envios', detalhe: 'sessão autenticada · RLS')
      : _proteger(() => _listaDoPerfil('meus_envios', limite, offset, (r) => r.ultimosEnvios));

  /// Todas as avaliações da conta, da mais recente à mais antiga, em páginas
  Future<List<Map<String, dynamic>>> minhasAvaliacoes({int limite = 50, int offset = 0}) => Config.demo
      ? _demo(Demo.minhasAvaliacoes().skip(offset).take(limite).toList(), 'RPC minhas_avaliacoes',
          detalhe: 'sessão autenticada · RLS')
      : _proteger(() => _listaDoPerfil('minhas_avaliacoes', limite, offset, (r) => r.ultimasAvaliacoes));

  Future<List<Map<String, dynamic>>> _listaDoPerfil(
      String funcao, int limite, int offset, List<Map<String, dynamic>> Function(ResumoPerfil) doResumo) async {
    try {
      final d = await _db.rpc(funcao, params: {'p_limite': limite, 'p_offset': offset});
      return (d as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on PostgrestException catch (e) {
      // Servidor ainda sem a migração 20261025000010: mostra os últimos itens que o resumo do perfil já traz
      if (e.code != 'PGRST202' || offset > 0) rethrow;
      final r = await _db.rpc('meu_resumo');
      return r == null ? const [] : doResumo(ResumoPerfil.deJson(Map<String, dynamic>.from(r as Map)));
    }
  }

  Future<List<MovimentoPontos>> extratoPontos() => Config.demo
      ? _demo(Demo.extrato(), 'pontos_movimentos · select')
      : _proteger(() async {
        final d = await _db
            .from('pontos_movimentos')
            .select('tipo, pontos, descricao, criado_em')
            .order('criado_em', ascending: false)
            .limit(100);
        return d.map((e) => MovimentoPontos.deJson(e)).toList();
      });

  Future<List<Notificacao>> notificacoes() => Config.demo
      ? _demo(Demo.notificacoes(), 'notificacoes · select')
      : _proteger(() async {
        final d = await _db
            .from('notificacoes')
            .select('id, posto_id, produto_id, preco_anterior, preco_novo, lida, criado_em, postos(nome_exibicao, razao_social)')
            .order('criado_em', ascending: false)
            .limit(100);
        return d.map((e) => Notificacao.deJson(e)).toList();
      });

  Future<void> marcarLidas() => Config.demo
      ? _demo<void>(null, 'notificacoes · update', detalhe: 'marcar como lidas')
      : _proteger(() async {
        await _db.from('notificacoes').update({'lida': true}).eq('lida', false);
      });

  /// Envia os preços revisados. A foto não é enviada: vão os valores, o texto lido e a posição.
  Future<Map<String, dynamic>> enviarPrecos({
    required int postoId,
    required double latitude,
    required double longitude,
    required List<Map<String, dynamic>> itens,
    String? textoLido,
    int? duracaoLeituraMs,
  }) =>
      Config.demo
          ? _demo<Map<String, dynamic>>({
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
            }, 'Edge Function enviar-precos',
              detalhe: '${itens.length} preços, texto lido e posição · sem a foto',
              camadas: const ['api', 'funcao', 'banco'])
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
          ? _demo<Map<String, dynamic>>({
              'status': 'aguardando',
              'mensagem': 'Obrigado! Quando outra pessoa que esteja neste posto também informar a posição, '
                  'ela será confirmada e você ganha pontos.',
            }, 'Edge Function corrigir-posicao',
              detalhe: 'GPS ±${precisaoGpsM.round()} m', camadas: const ['api', 'funcao', 'banco'])
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
    return regraSenha;
  }
  if (m.contains('rate limit') || m.contains('too many')) return 'Muitas tentativas. Aguarde alguns minutos e tente de novo.';
  if (m.contains('same password') || m.contains('different from the old')) return 'A nova senha precisa ser diferente da atual.';
  return 'Não foi possível concluir: ${e.message}';
}
