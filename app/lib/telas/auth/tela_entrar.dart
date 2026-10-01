import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../servicos/api.dart';
import '../../servicos/sessao.dart';
import '../../widgets/comuns.dart';
import 'comum_auth.dart';

class TelaEntrar extends StatefulWidget {
  const TelaEntrar({super.key});
  @override
  State<TelaEntrar> createState() => _TelaEntrarState();
}

class _TelaEntrarState extends State<TelaEntrar> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _carregando = false;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _carregando = true);
    try {
      await Sessao.instancia.entrar(_email.text, _senha.text);
      if (!mounted) return;
      mostrarMensagem(context, 'Bem-vindo de volta!');
      context.canPop() ? context.pop() : context.go('/perfil');
    } on ErroApp catch (e) {
      if (!mounted) return;
      if (e.mensagem.startsWith('Confirme seu e-mail')) {
        context.push('/verificar-email?email=${Uri.encodeComponent(_email.text.trim())}');
      } else {
        mostrarMensagem(context, e);
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutAuth(
        titulo: 'Entrar',
        subtitulo: 'Com a conta você envia preços, avalia postos e ganha pontos.',
        filhos: [
          Form(
            key: _form,
            child: AutofillGroup(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: validarEmail,
                  decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
                ),
                const SizedBox(height: 16),
                CampoSenha(controle: _senha, validar: (v) => (v ?? '').isEmpty ? 'Informe sua senha.' : null, aoConcluir: _entrar),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => context.push('/recuperar-senha'), child: const Text('Esqueci minha senha')),
                ),
                const SizedBox(height: 8),
                BotaoCarregando(carregando: _carregando, aoTocar: _entrar, texto: 'Entrar'),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('Ainda não tem conta?'),
                  TextButton(onPressed: () => context.pushReplacement('/cadastro'), child: const Text('Criar conta')),
                ]),
              ]),
            ),
          ),
        ],
      );
}
