import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicos/api.dart';
import '../../servicos/localizacao.dart';
import '../../servicos/sessao.dart';
import '../../util/responsivo.dart';

/// "Estou neste posto": a pessoa informa a posição do posto sem enviar preço e sem limite de raio.
/// Duas pessoas diferentes a até 150 m uma da outra confirmam a posição.
class TelaPosicaoPosto extends StatefulWidget {
  final int postoId;
  const TelaPosicaoPosto({super.key, required this.postoId});
  @override
  State<TelaPosicaoPosto> createState() => _TelaPosicaoPostoState();
}

class _TelaPosicaoPostoState extends State<TelaPosicaoPosto> {
  PostoDetalhe? _posto;
  bool _enviando = false;
  String? _erro;
  Map<String, dynamic>? _resultado;
  double? _precisaoGps;

  @override
  void initState() {
    super.initState();
    Api.instancia.detalhe(widget.postoId).then((d) {
      if (mounted) setState(() => _posto = d);
    }).catchError((Object e) {
      if (mounted) setState(() => _erro = e.toString());
    });
  }

  Future<void> _informar() async {
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final pos = await Localizacao.instancia.obter(precisa: true);
      if (pos == null) {
        throw ErroApp(Localizacao.instancia.estado == EstadoLocalizacao.desligada
            ? 'Ative a localização do aparelho e tente de novo.'
            : 'Permita o acesso à localização nas configurações do app.');
      }
      setState(() => _precisaoGps = pos.accuracy);
      final r = await Api.instancia.corrigirPosicao(
        postoId: widget.postoId,
        latitude: pos.latitude,
        longitude: pos.longitude,
        precisaoGpsM: pos.accuracy,
      );
      Sessao.instancia.carregarPerfil();
      if (mounted) setState(() => _resultado = r);
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = _posto?.resumo;
    return Scaffold(
      appBar: AppBar(title: const Text('Estou neste posto')),
      body: LarguraMaxima(
        maxima: 560,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          if (_resultado != null) ..._concluido(tt, cs) else ..._formulario(tt, cs, p),
        ]),
      ),
    );
  }

  List<Widget> _formulario(TextTheme tt, ColorScheme cs, PostoResumo? p) => [
        Icon(Icons.my_location, size: 64, color: cs.primary),
        const SizedBox(height: 12),
        Text(p?.nome ?? '', style: tt.headlineSmall, textAlign: TextAlign.center),
        if (p != null)
          Text([p.endereco, p.cidade].where((e) => e != null && e.isNotEmpty).join(' · '),
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
        const SizedBox(height: 20),
        Card(
          child: Column(children: [
            ListTile(
              leading: Icon(Icons.place_outlined, color: cs.primary),
              title: const Text('Esteja dentro do posto, de preferência ao ar livre'),
            ),
            ListTile(
              leading: Icon(Icons.groups_outlined, color: cs.primary),
              title: const Text('A posição vale quando duas pessoas diferentes informam pontos a até 150 m um do outro'),
            ),
            ListTile(
              leading: Icon(Icons.stars_outlined, color: cs.primary),
              title: const Text('Quando a posição é confirmada, você ganha 5 pontos'),
            ),
            ListTile(
              leading: Icon(Icons.lock_outline, color: cs.primary),
              title: const Text('Sua posição é usada só para localizar o posto. Nenhum preço é enviado'),
            ),
          ]),
        ),
        if (_precisaoGps != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Precisão do GPS: ${_precisaoGps!.round()} m', style: tt.bodySmall, textAlign: TextAlign.center),
          ),
        if (_erro != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_erro!, style: TextStyle(color: cs.error), textAlign: TextAlign.center),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _enviando || _posto == null ? null : _informar,
          icon: _enviando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: Text(_enviando ? 'Obtendo a posição…' : 'Informar a posição deste posto'),
        ),
      ];

  List<Widget> _concluido(TextTheme tt, ColorScheme cs) {
    final confirmada = _resultado?['status'] == 'confirmada';
    return [
      Icon(confirmada ? Icons.verified_rounded : Icons.hourglass_top_rounded, size: 72, color: cs.primary),
      const SizedBox(height: 12),
      Text(confirmada ? 'Posição confirmada!' : 'Obrigado por contribuir!', style: tt.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(_resultado?['mensagem']?.toString() ?? '', style: tt.bodyLarge, textAlign: TextAlign.center),
      const SizedBox(height: 24),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Voltar ao posto')),
    ];
  }
}
