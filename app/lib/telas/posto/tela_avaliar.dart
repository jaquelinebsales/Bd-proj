import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';

/// Avaliar o posto de 0 a 5 estrelas, com comentário opcional. Uma avaliação por pessoa, editável.
class TelaAvaliar extends StatefulWidget {
  final int postoId;
  const TelaAvaliar({super.key, required this.postoId});
  @override
  State<TelaAvaliar> createState() => _TelaAvaliarState();
}

class _TelaAvaliarState extends State<TelaAvaliar> {
  final _comentario = TextEditingController();
  int? _nota;
  PostoDetalhe? _posto;
  bool _salvando = false;

  static const _rotulos = ['Péssimo', 'Muito ruim', 'Ruim', 'Regular', 'Bom', 'Excelente'];

  @override
  void initState() {
    super.initState();
    Api.instancia.detalhe(widget.postoId, forcar: true).then((d) {
      if (!mounted) return;
      setState(() {
        _posto = d;
        _nota = d.minhaAvaliacao?.nota;
        _comentario.text = d.minhaAvaliacao?.comentario ?? '';
      });
    }).catchError((Object e) {
      if (mounted) mostrarMensagem(context, e);
    });
  }

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final texto = _comentario.text.trim();
    if (_nota == null) return mostrarMensagem(context, 'Escolha uma nota de 0 a 5 estrelas.');
    if (texto.isNotEmpty && texto.length < 3) return mostrarMensagem(context, 'O comentário precisa ter pelo menos 3 letras.');
    setState(() => _salvando = true);
    try {
      await Api.instancia.salvarAvaliacao(widget.postoId, _nota!, texto, id: _posto?.minhaAvaliacao?.id);
      if (mounted) {
        mostrarMensagem(context, 'Avaliação publicada.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) mostrarMensagem(context, e);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _apagar() async {
    final id = _posto?.minhaAvaliacao?.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Apagar sua avaliação?'),
        content: const Text('A nota e o comentário deixam de aparecer para outras pessoas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.instancia.apagarAvaliacao(widget.postoId, id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) mostrarMensagem(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_posto?.minhaAvaliacao == null ? 'Avaliar posto' : 'Editar avaliação'),
        actions: [
          if (_posto?.minhaAvaliacao != null)
            IconButton(tooltip: 'Apagar avaliação', onPressed: _apagar, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: LarguraMaxima(
        maxima: 560,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(_posto?.resumo.nome ?? '', style: tt.titleLarge),
          const SizedBox(height: 24),
          Text('Sua nota', style: tt.titleMedium),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var n = 1; n <= 5; n++)
              IconButton(
                iconSize: 44,
                tooltip: '$n estrela${n > 1 ? 's' : ''}',
                onPressed: () => setState(() => _nota = n),
                icon: Icon(
                  (_nota ?? 0) >= n ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: const Color(0xFFE0A100),
                ),
              ),
          ]),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _nota = 0),
              child: Text(_nota == 0 ? 'Nota 0 selecionada' : 'Dar nota 0'),
            ),
          ),
          Center(child: Text(_nota == null ? 'Toque nas estrelas' : _rotulos[_nota!], style: tt.titleMedium)),
          const SizedBox(height: 24),
          TextField(
            controller: _comentario,
            maxLength: 500,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Comentário (opcional)',
              hintText: 'Atendimento, qualidade do combustível, estrutura, conveniência…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Text('Seu nome aparece abreviado, por exemplo "Carla M.".', style: tt.bodySmall),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _salvando ? null : _salvar,
            child: _salvando
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Publicar avaliação'),
          ),
        ]),
      ),
    );
  }
}
