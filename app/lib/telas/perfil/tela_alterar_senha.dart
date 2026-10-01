import 'package:flutter/material.dart';

import '../../servicos/sessao.dart';
import '../../widgets/comuns.dart';
import '../auth/comum_auth.dart';

class TelaAlterarSenha extends StatefulWidget {
  const TelaAlterarSenha({super.key});
  @override
  State<TelaAlterarSenha> createState() => _TelaAlterarSenhaState();
}

class _TelaAlterarSenhaState extends State<TelaAlterarSenha> {
  final _form = GlobalKey<FormState>();
  final _atual = TextEditingController();
  final _nova = TextEditingController();
  final _confirmacao = TextEditingController();
  bool _carregando = false;

  @override
  void dispose() {
    for (final c in [_atual, _nova, _confirmacao]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _carregando = true);
    try {
      await Sessao.instancia.alterarSenha(_atual.text, _nova.text);
      if (mounted) {
        mostrarMensagem(context, 'Senha alterada.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        mostrarMensagem(context, e.toString().contains('incorretos') ? 'A senha atual está incorreta.' : e);
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutAuth(
        titulo: 'Alterar senha',
        subtitulo: 'Confirme a senha atual e escolha a nova.',
        filhos: [
          Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              CampoSenha(
                controle: _atual,
                rotulo: 'Senha atual',
                acao: TextInputAction.next,
                validar: (v) => (v ?? '').isEmpty ? 'Informe a senha atual.' : null,
              ),
              const SizedBox(height: 16),
              CampoSenha(
                controle: _nova,
                rotulo: 'Nova senha',
                acao: TextInputAction.next,
                validar: validarSenha,
                preenchimento: const [AutofillHints.newPassword],
              ),
              const SizedBox(height: 16),
              CampoSenha(
                controle: _confirmacao,
                rotulo: 'Confirme a nova senha',
                validar: (v) => v != _nova.text ? 'As senhas não conferem.' : null,
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
