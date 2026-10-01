import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../servicos/sessao.dart';
import '../../widgets/comuns.dart';
import 'comum_auth.dart';

/// Depois do cadastro: pede para abrir o link de confirmação enviado por e-mail.
class TelaVerificarEmail extends StatefulWidget {
  final String email;
  const TelaVerificarEmail({super.key, required this.email});
  @override
  State<TelaVerificarEmail> createState() => _TelaVerificarEmailState();
}

class _TelaVerificarEmailState extends State<TelaVerificarEmail> {
  int _espera = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Sessao.instancia.addListener(_aoMudarSessao);
  }

  @override
  void dispose() {
    Sessao.instancia.removeListener(_aoMudarSessao);
    _timer?.cancel();
    super.dispose();
  }

  // Ao abrir o link do e-mail, o app recebe a sessão e segue para o perfil
  void _aoMudarSessao() {
    if (Sessao.instancia.logado && Sessao.instancia.emailConfirmado && mounted) {
      mostrarMensagem(context, 'E-mail confirmado. Sua conta está pronta.');
      context.go('/perfil');
    }
  }

  Future<void> _reenviar() async {
    try {
      await Sessao.instancia.reenviarConfirmacao(widget.email);
      if (!mounted) return;
      mostrarMensagem(context, 'Enviamos um novo link para ${widget.email}.');
      setState(() => _espera = 60);
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_espera <= 1) t.cancel();
        if (mounted) setState(() => _espera--);
      });
    } catch (e) {
      if (mounted) mostrarMensagem(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutAuth(
        titulo: 'Confirme seu e-mail',
        subtitulo: 'Enviamos um link para ${widget.email.isEmpty ? 'o seu e-mail' : widget.email}. '
            'Abra a mensagem neste celular e toque no link para ativar a conta.',
        filhos: [
          const Icon(Icons.mark_email_unread_outlined, size: 80),
          const SizedBox(height: 24),
          const Text('Não chegou? Veja a caixa de spam ou peça outro link.'),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _espera > 0 || widget.email.isEmpty ? null : _reenviar,
            child: Text(_espera > 0 ? 'Reenviar em $_espera s' : 'Reenviar link'),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: () => context.go('/entrar'), child: const Text('Já confirmei, quero entrar')),
        ],
      );
}
