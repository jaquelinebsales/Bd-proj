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
  /// Schema das tabelas: public no Supabase da nuvem; combustivel no servidor próprio (self-hosted),
  /// que guarda cada sistema num schema separado.
  static const supabaseSchema = String.fromEnvironment('SUPABASE_SCHEMA', defaultValue: 'public');
  static const versao = '0.1.0';

  /// Modo demonstração: dados de exemplo, sem Supabase (--dart-define=DEMO=true).
  static const demo = bool.fromEnvironment('DEMO');

  /// Com DEMO, entra como uma usuária de exemplo já logada (--dart-define=DEMO_LOGADO=true).
  /// Serve para ver as telas que exigem conta.
  static const demoLogado = demo && bool.fromEnvironment('DEMO_LOGADO');

  /// Esconde a faixa "DEMO" do canto (capturas do portfólio, que já avisam que os dados são fictícios).
  static const semFaixaDemo = bool.fromEnvironment('SEM_FAIXA_DEMO');
  static const esquemaRetorno = 'br.com.gasprice.app://auth-callback';

  static bool get configurado => supabaseUrl.isNotEmpty && supabaseChavePublica.isNotEmpty;
}
