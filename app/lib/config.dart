/// Configuração lida em tempo de compilação.
///
/// Rode o app com:
///   flutter run --dart-define-from-file=config/app.json
/// O arquivo config/app.json fica fora do Git (modelo em config/app.example.json).
/// Só vão para o app chaves públicas: a URL do projeto e a chave publishable
/// (sb_publishable_...). A chave anon antiga também funciona.
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseChavePublica = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  static const versao = '0.1.0';

  /// Modo demonstração: dados de exemplo, sem Supabase (--dart-define=DEMO=true).
  static const demo = bool.fromEnvironment('DEMO');
  static const esquemaRetorno = 'br.com.gasprice.app://auth-callback';

  static bool get configurado => supabaseUrl.isNotEmpty && supabaseChavePublica.isNotEmpty;
}
