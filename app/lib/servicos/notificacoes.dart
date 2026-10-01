import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../modelos/modelos.dart';
import '../util/formatos.dart';
import 'api.dart';
import 'sessao.dart';

/// Avisos de mudança de preço nos postos favoritos.
///
/// O servidor grava a notificação; com o app aberto ou em segundo plano ela
/// chega em tempo real e aparece como notificação do sistema. Com o app
/// fechado, o aviso fica na lista e aparece na próxima abertura (push com o
/// app fechado depende do Firebase Cloud Messaging, previsto para depois).
class ServicoNotificacoes extends ChangeNotifier {
  ServicoNotificacoes._();
  static final instancia = ServicoNotificacoes._();

  final _plugin = FlutterLocalNotificationsPlugin();
  RealtimeChannel? _canal;
  int naoLidas = 0;
  String? _usuarioAtual;

  Future<void> iniciar() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
    } catch (_) {}
    Sessao.instancia.addListener(_aoMudarSessao);
    _aoMudarSessao();
    if (Config.demoLogado) atualizarContagem();
  }

  Future<void> pedirPermissao() async {
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  void _aoMudarSessao() {
    if (!Config.configurado) return;
    final uid = Sessao.instancia.usuario?.id;
    if (uid == _usuarioAtual) return;
    _usuarioAtual = uid;
    _canal?.unsubscribe();
    _canal = null;
    naoLidas = 0;
    notifyListeners();
    if (uid == null) return;

    atualizarContagem();
    _canal = Supabase.instance.client
        .channel('notificacoes-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notificacoes',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'usuario_id', value: uid),
          callback: (payload) => _mostrar(Notificacao.deJson(payload.newRecord)),
        )
        .subscribe();
  }

  Future<void> atualizarContagem() async {
    try {
      final lista = await Api.instancia.notificacoes();
      naoLidas = lista.where((n) => !n.lida).length;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _mostrar(Notificacao n) async {
    naoLidas++;
    notifyListeners();
    final produto = Produto.porId(n.produtoId).nome.toLowerCase();
    final caiu = n.precoNovo < n.precoAnterior;
    try {
      await _plugin.show(
        id: n.id,
        title: caiu ? 'Preço caiu no seu posto favorito' : 'Preço mudou no seu posto favorito',
        body: 'A $produto ${caiu ? 'caiu' : 'subiu'} de ${preco(n.precoAnterior)} para ${preco(n.precoNovo)}.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('precos', 'Preços dos favoritos',
              channelDescription: 'Mudanças de preço nos postos favoritos', importance: Importance.defaultImportance),
          iOS: DarwinNotificationDetails(),
        ),
        payload: '${n.postoId}',
      );
    } catch (_) {}
  }

  Future<void> marcarTodasLidas() async {
    await Api.instancia.marcarLidas();
    naoLidas = 0;
    notifyListeners();
  }
}
