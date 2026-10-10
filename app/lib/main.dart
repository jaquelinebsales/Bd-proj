import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config.dart';
import 'servicos/favoritos.dart';
import 'servicos/notificacoes.dart';
import 'servicos/preferencias.dart';
import 'servicos/sessao.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');

  if (Config.configurado) {
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabaseChavePublica,
      // Tabelas e funções do app ficam no schema configurado (combustivel no servidor próprio)
      postgrestOptions: const PostgrestClientOptions(schema: Config.supabaseSchema),
    );
  }
  await Preferencias.carregar();
  Sessao.instancia.iniciar();
  await Favoritos.instancia.iniciar();
  await ServicoNotificacoes.instancia.iniciar();

  final prefs = await SharedPreferences.getInstance();
  final viuBoasVindas = prefs.getBool('viu_boas_vindas') ?? false;

  runApp(GaspriceApp(mostrarBoasVindas: !viuBoasVindas));
}
