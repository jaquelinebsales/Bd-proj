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
  final _sobrenome = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _confirmacao = TextEditingController();
  final _dataNascCtrl = TextEditingController();
  String _genero = 'NI';
  DateTime? _dataNasc;
  bool _aceite = false;
  bool _carregando = false;

  @override
  void dispose() {
    for (final c in [_nome, _sobrenome, _email, _senha, _confirmacao, _dataNascCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _escolherData() async {
    final hoje = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dataNasc ?? DateTime(hoje.year - 25),
      firstDate: DateTime(1900),
      lastDate: DateTime(hoje.year - 13, hoje.month, hoje.day),
      helpText: 'Data de nascimento',
    );
    if (d != null) {
      setState(() {
        _dataNasc = d;
        _dataNascCtrl.text =
            '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      });
    }
  }

  Future<void> _cadastrar() async {
    if (!_form.currentState!.validate()) return;
    if (!_aceite) {
      return mostrarMensagem(
          context, 'Para criar a conta, aceite os termos de uso e a política de privacidade.');
    }
    setState(() => _carregando = true);
    try {
      final precisaConfirmar = await Sessao.instancia.cadastrar(
        _nome.text,
        _email.text,
        _senha.text,
        sobrenome: _sobrenome.text.trim().isEmpty ? null : _sobrenome.text,
        genero: _genero == 'NI' ? null : _genero,
        dataNascimento: _dataNasc,
      );
      if (!mounted) return;
      if (precisaConfirmar) {
        context
            .pushReplacement('/verificar-email?email=${Uri.encodeComponent(_email.text.trim())}');
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
        filhos: [
          Form(
            key: _form,
            child: AutofillGroup(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Nome
                TextFormField(
                  controller: _nome,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.givenName],
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.length < 2) return 'Informe seu nome.';
                    if (t.length > 60) return 'Use no máximo 60 caracteres.';
                    return null;
                  },
                  decoration:
                      const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 16),
                // Sobrenome
                TextFormField(
                  controller: _sobrenome,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.familyName],
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isNotEmpty && t.length > 80) return 'Use no máximo 80 caracteres.';
                    return null;
                  },
                  decoration: const InputDecoration(
                      labelText: 'Sobrenome (opcional)',
                      prefixIcon: Icon(Icons.person_outline)),
                ),
                const SizedBox(height: 20),
                // Gênero
                Text('Gênero',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'F', label: Text('Feminino')),
                    ButtonSegment(value: 'M', label: Text('Masculino')),
                    ButtonSegment(value: 'NI', label: Text('Prefiro não informar')),
                  ],
                  selected: {_genero},
                  onSelectionChanged: (s) => setState(() => _genero = s.first),
                  showSelectedIcon: false,
                ),
                const SizedBox(height: 20),
                // Data de nascimento
                TextFormField(
                  controller: _dataNascCtrl,
                  readOnly: true,
                  onTap: _escolherData,
                  decoration: InputDecoration(
                    labelText: 'Data de nascimento (opcional)',
                    prefixIcon: const Icon(Icons.cake_outlined),
                    suffixIcon: _dataNasc != null
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Remover data',
                            onPressed: () => setState(() {
                              _dataNasc = null;
                              _dataNascCtrl.clear();
                            }),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 20),
                // E-mail
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: validarEmail,
                  decoration:
                      const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
                ),
                const SizedBox(height: 16),
                CampoSenha(
                  controle: _senha,
                  validar: validarSenha,
                  acao: TextInputAction.next,
                  preenchimento: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: 16),
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
                  TextButton(
                      onPressed: () => context.pushReplacement('/entrar'), child: const Text('Entrar')),
                ]),
              ]),
            ),
          ),
        ],
      );
}
