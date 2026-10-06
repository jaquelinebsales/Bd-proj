import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../servicos/sessao.dart';
import '../../widgets/comuns.dart';
import 'comum_auth.dart';

class TelaCadastro extends StatefulWidget {
  const TelaCadastro({super.key});
  @override
  State<TelaCadastro> createState() => _TelaCadastroState();
}

class _TelaCadastroState extends State<TelaCadastro> {
  final _form = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _confirmacao = TextEditingController();
  bool _aceite = false;
  bool _carregando = false;

  @override
  void dispose() {
    for (final c in [_nome, _email, _senha, _confirmacao]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cadastrar() async {
    if (!_form.currentState!.validate()) return;
    if (!_aceite) return mostrarMensagem(context, 'Para criar a conta, aceite os termos de uso e a política de privacidade.');
    setState(() => _carregando = true);
    try {
      final precisaConfirmar = await Sessao.instancia.cadastrar(_nome.text, _email.text, _senha.text);
      if (!mounted) return;
      if (precisaConfirmar) {
        context.pushReplacement('/verificar-email?email=${Uri.encodeComponent(_email.text.trim())}');
      } else {
        mostrarMensagem(context, 'Conta criada.');
        context.go('/perfil');
      }
    } catch (e) {
      if (mounted) mostrarMensagem(context, e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutAuth(
        titulo: 'Criar conta',
        subtitulo: 'Só pedimos nome, e-mail e senha. Seu nome aparece abreviado para outras pessoas.',
        filhos: [
          Form(
            key: _form,
            child: AutofillGroup(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextFormField(
                  controller: _nome,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.length < 2) return 'Informe seu nome.';
                    if (t.length > 60) return 'Use no máximo 60 caracteres.';
                    return null;
                  },
                  decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: validarEmail,
                  decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
                ),
                const SizedBox(height: 16),
                CampoSenha(
                  controle: _senha,
                  validar: validarSenha,
                  acao: TextInputAction.next,
                  preenchimento: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: 4),
                Text('  Pelo menos 8 caracteres, com letras e números.', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                CampoSenha(
                  controle: _confirmacao,
                  rotulo: 'Confirme a senha',
                  preenchimento: const [AutofillHints.newPassword],
                  validar: (v) => v != _senha.text ? 'As senhas não conferem.' : null,
                  aoConcluir: _cadastrar,
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _aceite,
                  onChanged: (v) => setState(() => _aceite = v ?? false),
                  title: const Text('Li e aceito os termos de uso e a política de privacidade'),
                  subtitle: TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                    onPressed: () => context.push('/sobre'),
                    child: const Text('Ler os termos'),
                  ),
                ),
                const SizedBox(height: 12),
                BotaoCarregando(carregando: _carregando, aoTocar: _cadastrar, texto: 'Criar conta'),
                const SizedBox(height: 24),
                Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Text('Já tem conta?'),
                  TextButton(onPressed: () => context.pushReplacement('/entrar'), child: const Text('Entrar')),
                ]),
              ]),
            ),
          ),
        ],
      );
}
