/// Regra de senha. A mesma configurada no Supabase em Authentication → Sign In / Providers → Email →
/// Password requirements: "Lowercase, uppercase letters, digits and symbols", mínimo de 8 caracteres.
library;

/// Texto padrão mostrado sempre que a senha não atende à regra (no formulário ou na resposta do servidor).
const regraSenha = 'A senha precisa ter pelo menos 8 caracteres, com letra maiúscula, letra minúscula, número e '
    'caractere especial.';

bool senhaValida(String senha) =>
    senha.length >= 8 &&
    RegExp(r'[A-Z]').hasMatch(senha) &&
    RegExp(r'[a-z]').hasMatch(senha) &&
    RegExp(r'\d').hasMatch(senha) &&
    // Caractere especial: qualquer coisa que não seja letra sem acento, número ou espaço
    RegExp(r'[^A-Za-z0-9\s]').hasMatch(senha);

/// Validador dos campos de senha: cadastro, nova senha e alterar senha.
String? validarSenha(String? v) => senhaValida(v ?? '') ? null : regraSenha;
