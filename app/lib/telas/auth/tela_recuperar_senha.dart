import 'package:flutter/material.dart';

import '../../servicos/sessao.dart';
import '../../widgets/comuns.dart';
import 'comum_auth.dart';

class TelaRecuperarSenha extends StatefulWidget {
  const TelaRecuperarSenha({super.key});
  @override
  State<TelaRecuperarSenha> createState() => _TelaRecuperarSenhaState();
}

class _TelaRecuperarSenhaState extends State<TelaRecuperarSenha> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _carregando = false;
  bool _enviado = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _carregando = true);
    try {
      await Sessao.instancia.recuperarSenha(_email.text);
      if (mounted) setState(() => _enviado = true);
    } catch (e) {
      if (mounted) mostrarMensagem(context, e);
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutAuth(
        titulo: 'Recuperar senha',
        subtitulo: _enviado
            ? 'Link de redefinição enviado para ${_email.text.trim()}.'
            : null,
        filhos: _enviado
            ? [
                const Icon(Icons.outgoing_mail, size: 72),
                const SizedBox(height: 24),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => setState(() => _enviado = false),
                  child: const Text('Usar outro e-mail'),
                ),
              ]
            : [
                Form(
                  key: _form,
                  child: TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: validarEmail,
                    onFieldSubmitted: (_) => _enviar(),
                    decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
                  ),
                ),
                const SizedBox(height: 20),
                BotaoCarregando(carregando: _carregando, aoTocar: _enviar, texto: 'Enviar link'),
              ],
      );
}
