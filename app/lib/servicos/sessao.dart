import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../modelos/modelos.dart';
import 'api.dart';
import 'demo.dart';

/// Estado de login. Consulta não exige conta; só alterar ou acrescentar dados.
class Sessao extends ChangeNotifier {
  Sessao._();
  static final instancia = Sessao._();

  User? usuario;
  ResumoPerfil? perfil;

  /// Verdadeiro quando o usuário abriu o link de recuperação de senha.
  bool recuperandoSenha = false;
  StreamSubscription<AuthState>? _assinatura;

  bool get logado => usuario != null || Config.demoLogado;
  bool get emailConfirmado => Config.demoLogado || usuario?.emailConfirmedAt != null;
  String? get email => Config.demoLogado ? 'carla.m@exemplo.com' : usuario?.email;
  SupabaseClient get _auth => Supabase.instance.client;

  void iniciar() {
    if (Config.demoLogado) {
      perfil = Demo.perfil();
      return;
    }
    if (!Config.configurado) return;
    usuario = _auth.auth.currentUser;
    _assinatura = _auth.auth.onAuthStateChange.listen((estado) {
      usuario = estado.session?.user;
      if (estado.event == AuthChangeEvent.passwordRecovery) recuperandoSenha = true;
      if (estado.event == AuthChangeEvent.signedOut) perfil = null;
      notifyListeners();
      if (logado) carregarPerfil();
    });
    if (logado) carregarPerfil();
  }

  Future<void> carregarPerfil() async {
    try {
      perfil = await Api.instancia.meuResumo();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _executar(Future<void> Function() f) async {
    if (!Config.configurado) {
      throw const ErroApp('O app ainda não foi ligado ao Supabase. Veja config/app.example.json.');
    }
    try {
      await f();
    } on AuthException catch (e) {
      throw ErroApp(traduzirErroAuth(e));
    } on ErroApp {
      rethrow;
    } catch (_) {
      throw const ErroApp('Sem conexão com o servidor. Verifique sua internet e tente de novo.');
    }
  }

  Future<void> entrar(String email, String senha) =>
      _executar(() async => _auth.auth.signInWithPassword(email: email.trim(), password: senha));

  /// Cria a conta. Retorna true se o e-mail ainda precisa ser confirmado.
  Future<bool> cadastrar(String nome, String email, String senha) async {
    var precisaConfirmar = true;
    await _executar(() async {
      final r = await _auth.auth.signUp(
        email: email.trim(),
        password: senha,
        data: {'nome': nome.trim()},
        emailRedirectTo: Config.esquemaRetorno,
      );
      precisaConfirmar = r.session == null;
    });
    return precisaConfirmar;
  }

  Future<void> reenviarConfirmacao(String email) => _executar(() async {
        await _auth.auth.resend(type: OtpType.signup, email: email.trim(), emailRedirectTo: Config.esquemaRetorno);
      });

  Future<void> recuperarSenha(String email) => _executar(() async {
        await _auth.auth.resetPasswordForEmail(email.trim(), redirectTo: Config.esquemaRetorno);
      });

  Future<void> definirNovaSenha(String senha) => _executar(() async {
        await _auth.auth.updateUser(UserAttributes(password: senha));
        recuperandoSenha = false;
        notifyListeners();
      });

  Future<void> alterarSenha(String atual, String nova) => _executar(() async {
        // Confirma a senha atual antes de trocar
        await _auth.auth.signInWithPassword(email: usuario!.email!, password: atual);
        await _auth.auth.updateUser(UserAttributes(password: nova));
      });

  Future<void> atualizarPerfil({String? nome, bool? notificacoes}) => _executar(() async {
        final dados = <String, dynamic>{
          'nome': ?nome?.trim(),
          'notificacoes_ativas': ?notificacoes,
        };
        if (dados.isEmpty) return;
        await _auth.from('perfis').update(dados).eq('id', usuario!.id);
        await carregarPerfil();
      });

  Future<void> enviarAvatar(Uint8List bytes) => _executar(() async {
        final caminho = '${usuario!.id}/avatar.jpg';
        await _auth.storage.from('avatares').uploadBinary(caminho, bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
        final url = '${_auth.storage.from('avatares').getPublicUrl(caminho)}?v=${DateTime.now().millisecondsSinceEpoch}';
        await _auth.from('perfis').update({'avatar_url': url}).eq('id', usuario!.id);
        await carregarPerfil();
      });

  Future<void> sair() => _executar(() async => _auth.auth.signOut());

  Future<void> excluirConta() async {
    await Api.instancia.excluirConta();
    await _executar(() async => _auth.auth.signOut());
  }

  @override
  void dispose() {
    _assinatura?.cancel();
    super.dispose();
  }
}
