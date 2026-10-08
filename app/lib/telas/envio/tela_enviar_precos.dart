import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../config.dart';
import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../servicos/leitor_painel.dart';
import '../../servicos/localizacao.dart';
import '../../servicos/parser_painel.dart';
import '../../servicos/sessao.dart';
import '../../util/formatos.dart';
import '../../util/responsivo.dart';
import '../../widgets/comuns.dart';

enum _Etapa { instrucoes, lendo, revisao, enviando, concluido }

/// Converte o texto digitado em preço: aceita "5,99", "5.999" e "599".
double? lerPrecoDigitado(String s) {
  final t = s.trim().replaceAll('R\$', '').replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  if (RegExp(r'^\d{3,4}$').hasMatch(t)) {
    final n = int.parse(t);
    return t.length == 3 ? n / 100 : n / 1000;
  }
  return double.tryParse(t);
}

/// Atualizar preços: foto do painel → leitura no aparelho → revisão → envio.
class TelaEnviarPrecos extends StatefulWidget {
  final int postoId;
  const TelaEnviarPrecos({super.key, required this.postoId});
  @override
  State<TelaEnviarPrecos> createState() => _TelaEnviarPrecosState();
}

class _TelaEnviarPrecosState extends State<TelaEnviarPrecos> {
  _Etapa _etapa = _Etapa.instrucoes;
  PostoDetalhe? _posto;
  LeituraFoto? _leitura;
  final _campos = <int, TextEditingController>{};
  final _incluir = <int, bool>{};
  int? _campoEmFoco;
  double? _distanciaM;
  Map<String, dynamic>? _resposta;
  String? _erro;

  @override
  void initState() {
    super.initState();
    Api.instancia.detalhe(widget.postoId).then((d) {
      if (mounted) setState(() => _posto = d);
    }).catchError((Object e) {
      if (mounted) setState(() => _erro = e.toString());
    });
  }

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Raio de envio do posto, vindo do servidor: 300 m com posição exata, 1 km com posição aproximada.
  int get _raioM => _posto?.raioEnvioM ?? 300;

  String _textoRaio() => _raioM >= 1000 ? '${_raioM ~/ 1000} km' : '$_raioM m';

  Future<void> _atualizarDistancia() async {
    final pos = await Localizacao.instancia.obter(precisa: true);
    final p = _posto?.resumo;
    if (pos != null && p?.lat != null) {
      setState(() => _distanciaM = (Localizacao.instancia.distanciaKm(p!.lat, p.lon) ?? 0) * 1000);
    }
  }

  Future<void> _fotografar() async {
    setState(() {
      _etapa = _Etapa.lendo;
      _erro = null;
    });
    final distancia = _atualizarDistancia();
    try {
      final leitura = Config.demo ? LeitorPainel.demonstracao() : await LeitorPainel().fotografarELer();
      await distancia;
      if (leitura == null) {
        setState(() => _etapa = _Etapa.instrucoes);
        return;
      }
      _prepararFormulario(leitura);
    } catch (e) {
      setState(() {
        _etapa = _Etapa.instrucoes;
        _erro = 'Não foi possível ler a foto. Tente de novo com o painel inteiro enquadrado e sem reflexo.';
      });
    }
  }

  void _prepararFormulario(LeituraFoto leitura) {
    final produtos = <int>{...?_posto?.produtosExibidos, ...leitura.resultado.leituras.map((l) => l.produtoId)}.toList()
      ..sort((a, b) => Produto.ordem(a).compareTo(Produto.ordem(b)));
    if (produtos.isEmpty) produtos.addAll(Produto.todos.map((p) => p.id));
    for (final id in produtos) {
      final lido = leitura.resultado.de(id);
      _campos[id] = TextEditingController(text: lido == null ? '' : lido.preco.toStringAsFixed(lido.preco * 1000 % 10 == 0 ? 2 : 3).replaceAll('.', ','));
      _incluir[id] = lido != null;
    }
    setState(() {
      _leitura = leitura;
      _etapa = _Etapa.revisao;
    });
  }

  Future<void> _enviar() async {
    final itens = <Map<String, dynamic>>[];
    for (final e in _campos.entries) {
      if (_incluir[e.key] != true) continue;
      final valor = lerPrecoDigitado(e.value.text);
      final nome = Produto.porId(e.key).nome;
      if (valor == null) return mostrarMensagem(context, 'Preço de $nome inválido. Use o formato 5,99.');
      if (valor < 1.5 || valor > 15) return mostrarMensagem(context, 'O preço de $nome parece errado: ${reais(valor)}.');
      final lido = _leitura?.resultado.de(e.key);
      itens.add({'produto_id': e.key, 'preco': valor, 'preco_lido': lido?.preco, 'confianca': lido?.confianca});
    }
    if (itens.isEmpty) return mostrarMensagem(context, 'Marque pelo menos um combustível para enviar.');

    final pos = Localizacao.instancia.atual ?? await Localizacao.instancia.obter(precisa: true);
    if (pos == null) {
      if (mounted) mostrarMensagem(context, 'Ative a localização: ela confirma que você está no posto.');
      return;
    }
    setState(() => _etapa = _Etapa.enviando);
    try {
      _resposta = await Api.instancia.enviarPrecos(
        postoId: widget.postoId,
        latitude: pos.latitude,
        longitude: pos.longitude,
        itens: itens,
        textoLido: _leitura?.resultado.textoCompleto,
        duracaoLeituraMs: _leitura?.duracaoMs,
      );
      Sessao.instancia.carregarPerfil();
      setState(() => _etapa = _Etapa.concluido);
    } catch (e) {
      setState(() => _etapa = _Etapa.revisao);
      if (mounted) mostrarMensagem(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessao = Sessao.instancia;
    return PopScope(
      canPop: _etapa != _Etapa.enviando,
      child: Scaffold(
        appBar: AppBar(title: Text(_posto == null ? 'Atualizar preços' : 'Atualizar preços · ${_posto!.resumo.nome}')),
        body: LarguraMaxima(
          maxima: 640,
          child: !sessao.logado && !Config.demo
              ? EstadoVazio(
                  icone: Icons.lock_outline,
                  titulo: 'Entre para enviar preços',
                  texto: 'Consultar é livre. Para alterar ou acrescentar dados, é preciso ter conta.',
                  acao: FilledButton(onPressed: () => context.push('/entrar'), child: const Text('Entrar')),
                )
              : !sessao.emailConfirmado && !Config.demo
                  ? const EstadoVazio(
                      icone: Icons.mark_email_unread_outlined,
                      titulo: 'Confirme seu e-mail',
                      texto: 'Abra o link que enviamos para o seu e-mail. Depois disso você já pode enviar preços.',
                    )
                  : switch (_etapa) {
                      _Etapa.instrucoes => _instrucoes(),
                      _Etapa.lendo => const _Processando('Lendo os preços no seu celular…'),
                      _Etapa.revisao => _revisao(),
                      _Etapa.enviando => const _Processando('Enviando…'),
                      _Etapa.concluido => _concluido(),
                    },
        ),
      ),
    );
  }

  Widget _instrucoes() {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget passo(IconData i, String t) => ListTile(leading: Icon(i, color: cs.primary), title: Text(t));
    return ListView(padding: const EdgeInsets.all(20), children: [
      Icon(Icons.photo_camera_outlined, size: 64, color: cs.primary),
      const SizedBox(height: 12),
      Text('Fotografe o painel de preços', style: tt.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      Card(
        child: Column(children: [
          passo(Icons.crop_free, 'Painel inteiro, de frente'),
          passo(Icons.wb_sunny_outlined, 'Sem reflexo nem contraluz'),
          passo(Icons.place_outlined, 'No posto, a até ${_textoRaio()}'),
          passo(Icons.lock_outline, 'A foto não sai do celular'),
        ]),
      ),
      if (_erro != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_erro!, style: TextStyle(color: cs.error), textAlign: TextAlign.center),
        ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _posto == null ? null : _fotografar,
        icon: const Icon(Icons.photo_camera),
        label: const Text('Abrir câmera'),
      ),
    ]);
  }

  Widget _revisao() {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final leitura = _leitura!;
    final longe = _distanciaM != null && _distanciaM! > _raioM;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Confira os preços', style: tt.headlineSmall),
      if (leitura.resultado.leituras.isEmpty) ...[
        const SizedBox(height: 4),
        Text('Nenhum preço reconhecido na foto', style: tt.bodyMedium),
      ],
      if (longe)
        Card(
          color: cs.errorContainer,
          margin: const EdgeInsets.only(top: 12),
          child: ListTile(
            leading: Icon(Icons.wrong_location_outlined, color: cs.onErrorContainer),
            title: Text('Você está a ${distancia(_distanciaM! / 1000)} do posto',
                style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w700)),
            subtitle: Text('O envio só é aceito a até ${_textoRaio()}.', style: TextStyle(color: cs.onErrorContainer)),
            trailing: IconButton(onPressed: _atualizarDistancia, icon: const Icon(Icons.refresh), tooltip: 'Atualizar localização'),
          ),
        ),
      const SizedBox(height: 12),
      for (final e in _campos.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: Row(children: [
                Checkbox(value: _incluir[e.key] ?? false, onChanged: (v) => setState(() => _incluir[e.key] = v ?? false)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(Produto.porId(e.key).nome, style: tt.titleMedium),
                    Text(_dicaLeitura(leitura.resultado.de(e.key), e.key), style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ]),
                ),
                SizedBox(
                  width: 120,
                  child: Focus(
                    onFocusChange: (f) => f ? _campoEmFoco = e.key : null,
                    child: TextField(
                      controller: e.value,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,\.]'))],
                      textAlign: TextAlign.end,
                      style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      decoration: const InputDecoration(prefixText: 'R\$ ', isDense: true, hintText: '0,00'),
                      onChanged: (t) => setState(() => _incluir[e.key] = t.trim().isNotEmpty),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      if (leitura.resultado.precosSemRotulo.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('Outros valores na foto', style: tt.bodySmall),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final v in leitura.resultado.precosSemRotulo)
            ActionChip(
              label: Text(preco(v)),
              onPressed: _campoEmFoco == null
                  ? null
                  : () => setState(() {
                        _campos[_campoEmFoco!]!.text = v.toStringAsFixed(3).replaceAll('.', ',');
                        _incluir[_campoEmFoco!] = true;
                      }),
            ),
        ]),
      ],
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: _enviar, icon: const Icon(Icons.send), label: const Text('Enviar preços')),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        onPressed: _fotografar,
        icon: const Icon(Icons.replay),
        label: const Text('Tirar outra foto'),
      ),
    ]);
  }

  String _dicaLeitura(LeituraPreco? lido, int produtoId) {
    if (lido == null) return 'Não lido na foto';
    final conf = lido.confianca >= 0.8 ? 'leitura boa' : 'confira com atenção';
    return 'Lido: ${preco(lido.preco)} · $conf';
  }

  Widget _concluido() {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final itens = ((_resposta?['itens'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final ignorados = ((_resposta?['ignorados'] as List?) ?? const []).length;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Icon(Icons.check_circle_rounded, size: 72, color: cs.primary),
      const SizedBox(height: 12),
      Text('Obrigado por contribuir!', style: tt.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(_resposta?['mensagem']?.toString() ?? '', style: tt.bodyLarge, textAlign: TextAlign.center),
      const SizedBox(height: 20),
      Card(
        child: Column(children: [
          for (final i in itens)
            ListTile(
              leading: Icon(
                i['status'] == 'confirmado' ? Icons.verified : Icons.hourglass_top,
                color: i['status'] == 'confirmado' ? cs.primary : cs.outline,
              ),
              title: Text(Produto.porId((i['produto_id'] as num).toInt()).nome),
              subtitle: Text(i['status'] == 'confirmado'
                  ? 'Confirmado com outros usuários'
                  : i['em_revisao'] == true
                      ? 'Em revisão: precisa de 3 confirmações. ${i['motivo_revisao'] ?? ''}'
                      : 'Aguardando outra pessoa confirmar'),
              trailing: Text(preco((i['preco'] as num).toDouble()), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
        ]),
      ),
      if (ignorados > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('$ignorados preço(s) não foram enviados porque você já os enviou nas últimas 6 horas.',
              style: tt.bodySmall, textAlign: TextAlign.center),
        ),
      const SizedBox(height: 24),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Voltar ao posto')),
      TextButton(onPressed: () => context.push('/pontos'), child: const Text('Ver meus pontos')),
    ]);
  }
}

class _Processando extends StatelessWidget {
  final String texto;
  const _Processando(this.texto);
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(texto, style: Theme.of(context).textTheme.titleMedium),
        ]),
      );
}
