import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../servicos/notificacoes.dart';
import '../../servicos/sessao.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';

class TelaEditarPerfil extends StatefulWidget {
  const TelaEditarPerfil({super.key});
  @override
  State<TelaEditarPerfil> createState() => _TelaEditarPerfilState();
}

class _TelaEditarPerfilState extends State<TelaEditarPerfil> {
  final _form = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: Sessao.instancia.perfil?.nome ?? '');
  late bool _notificacoes = Sessao.instancia.perfil?.notificacoesAtivas ?? true;
  bool _salvando = false;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _salvando = true);
    try {
      await Sessao.instancia.atualizarPerfil(nome: _nome.text, notificacoes: _notificacoes);
      if (_notificacoes) await ServicoNotificacoes.instancia.pedirPermissao();
      if (mounted) {
        mostrarMensagem(context, 'Dados salvos.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) mostrarMensagem(context, e);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _trocarFoto() async {
    final foto = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 320, maxHeight: 320, imageQuality: 80);
    if (foto == null) return;
    try {
      final bytes = await foto.readAsBytes();
      if (bytes.length > 200 * 1024) {
        if (mounted) mostrarMensagem(context, 'A foto ficou maior que 200 KB. Escolha outra imagem.');
        return;
      }
      await Sessao.instancia.enviarAvatar(bytes);
      if (mounted) {
        setState(() {});
        mostrarMensagem(context, 'Foto de perfil atualizada.');
      }
    } catch (e) {
      if (mounted) mostrarMensagem(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = Sessao.instancia.perfil;
    return Scaffold(
      appBar: AppBar(title: const Text('Alterar dados')),
      body: LarguraMaxima(
        maxima: 560,
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Center(
              child: Stack(children: [
                CircleAvatar(
                  radius: 48,
                  foregroundImage: perfil?.avatarUrl == null ? null : NetworkImage(perfil!.avatarUrl!),
                  child: const Icon(Icons.person, size: 48),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IconButton.filled(
                    tooltip: 'Trocar foto de perfil',
                    onPressed: _trocarFoto,
                    icon: const Icon(Icons.photo_camera, size: 18),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            const Center(child: Text('Foto de perfil opcional')),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nome,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              validator: (v) => (v ?? '').trim().length < 2 ? 'Informe seu nome.' : null,
              decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: Sessao.instancia.usuario?.email,
              enabled: false,
              decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Avisos de preço dos favoritos'),
              subtitle: const Text('Receba um aviso quando o preço de um posto favorito mudar pelo menos R\$ 0,05.'),
              value: _notificacoes,
              onChanged: (v) => setState(() => _notificacoes = v),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _salvando ? null : _salvar, child: const Text('Salvar')),
          ]),
        ),
      ),
    );
  }
}
