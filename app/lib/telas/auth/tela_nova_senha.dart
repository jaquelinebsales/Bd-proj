import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../servicos/sessao.dart';
import '../../widgets/comuns.dart';
import 'comum_auth.dart';

/// Aberta pelo link de recuperação de senha recebido por e-mail.
class TelaNovaSenha extends StatefulWidget {
  const TelaNovaSenha({super.key});
  @override
  State<TelaNovaSenha> createState() => _TelaNovaSenhaState();
}

class _TelaNovaSenhaState extends State<TelaNovaSenha> {
  final _form = GlobalKey<FormState>();
  final _senha = TextEditingController();
  final _confirmacao = TextEditingController();
  bool _carregando = false;

  @override
  void dispose() {
    _senha.dispose();
    _confirmacao.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _carregando = true);
    try {
      await Sessao.instancia.definirNovaSenha(_senha.text);
      if (!mounted) return;
      mostrarMensagem(context, 'Senha alterada. Você já está conectado.');
      context.go('/perfil');
    } catch (e) {
      if (mounted) mostrarMensagem(context, e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutAuth(
        titulo: 'Crie uma nova senha',
        subtitulo: 'Use pelo menos 8 caracteres, com letras e números.',
        filhos: [
          Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CampoSenha(
                controle: _senha,
                rotulo: 'Nova senha',
                validar: validarSenha,
                acao: TextInputAction.next,
                preenchimento: const [AutofillHints.newPassword],
              ),
              const SizedBox(height: 16),
              CampoSenha(
                controle: _confirmacao,
                rotulo: 'Confirme a nova senha',
                validar: (v) => v != _senha.text ? 'As senhas não conferem.' : null,
                preenchimento: const [AutofillHints.newPassword],
                aoConcluir: _salvar,
              ),
              const SizedBox(height: 24),
              BotaoCarregando(carregando: _carregando, aoTocar: _salvar, texto: 'Salvar nova senha'),
            ]),
          ),
        ],
      );
}
