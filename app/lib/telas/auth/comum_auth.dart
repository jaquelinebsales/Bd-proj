import 'package:flutter/material.dart';

/// Moldura comum das telas de conta: largura limitada, marca e título.
class LayoutAuth extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final List<Widget> filhos;
  const LayoutAuth({super.key, required this.titulo, this.subtitulo, required this.filhos});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(Icons.local_gas_station_rounded, color: cs.primary, size: 32),
                  const SizedBox(width: 8),
                  Text('gasprice', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: cs.primary)),
                ]),
                const SizedBox(height: 24),
                Text(titulo, style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitulo != null) ...[
                  const SizedBox(height: 8),
                  Text(subtitulo!, style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                ],
                const SizedBox(height: 28),
                ...filhos,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

String? validarEmail(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return 'Informe seu e-mail.';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) return 'E-mail inválido.';
  return null;
}

/// Mesma regra configurada no Supabase: 8+ caracteres, com letras e números.
String? validarSenha(String? v) {
  final t = v ?? '';
  if (t.length < 8) return 'Use pelo menos 8 caracteres.';
  if (!RegExp(r'[A-Za-z]').hasMatch(t) || !RegExp(r'\d').hasMatch(t)) return 'Use letras e números.';
  return null;
}

class CampoSenha extends StatefulWidget {
  final TextEditingController controle;
  final String rotulo;
  final String? Function(String?)? validar;
  final TextInputAction acao;
  final VoidCallback? aoConcluir;
  final Iterable<String> preenchimento;
  const CampoSenha({
    super.key,
    required this.controle,
    this.rotulo = 'Senha',
    this.validar,
    this.acao = TextInputAction.done,
    this.aoConcluir,
    this.preenchimento = const [AutofillHints.password],
  });
  @override
  State<CampoSenha> createState() => _CampoSenhaState();
}

class _CampoSenhaState extends State<CampoSenha> {
  bool _oculta = true;
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: widget.controle,
        obscureText: _oculta,
        validator: widget.validar,
        textInputAction: widget.acao,
        autofillHints: widget.preenchimento,
        onFieldSubmitted: (_) => widget.aoConcluir?.call(),
        decoration: InputDecoration(
          labelText: widget.rotulo,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            tooltip: _oculta ? 'Mostrar senha' : 'Ocultar senha',
            onPressed: () => setState(() => _oculta = !_oculta),
            icon: Icon(_oculta ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          ),
        ),
      );
}

class BotaoCarregando extends StatelessWidget {
  final bool carregando;
  final VoidCallback aoTocar;
  final String texto;
  const BotaoCarregando({super.key, required this.carregando, required this.aoTocar, required this.texto});
  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: carregando ? null : aoTocar,
        child: carregando
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(texto),
      );
}
