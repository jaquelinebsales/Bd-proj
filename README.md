# gasprice

App de preços de combustíveis para Android e iOS, em celular e tablet. Combina a pesquisa oficial da ANP com preços enviados pela comunidade por foto do painel. A foto é lida no próprio aparelho e apagada: só o valor lido vai para o servidor.

| Pasta | Conteúdo |
|---|---|
| `app/` | App Flutter (Material 3, go_router, Google Maps, ML Kit para ler o painel) |
| `supabase/migrations/` | Banco: tabelas, regras de acesso (RLS), regras de negócio e tarefas agendadas |
| `supabase/functions/` | Edge Functions em TypeScript: envio de preços, sincronização com a ANP, exclusão de conta |
| `supabase/tests/` | Testes das regras de negócio no banco |
| `scripts/` | Python: limpeza das planilhas da ANP, cobertura, experimento do modelo, importação no Supabase |
| `documentacao/` | Requisitos, relatórios e mockups |

## Chaves do Supabase

No painel do projeto, abra **Project Settings**. Nunca coloque uma chave secreta no app nem num arquivo que vá para o GitHub.

| Chave | Onde encontrar | Onde colocar | Pública? |
|---|---|---|---|
| URL do projeto (`https://xxxx.supabase.co`) | Project Settings → Data API | `app/config/app.json`, `.env` e segredo `SUPABASE_URL` do GitHub | Sim |
| Chave publishable (`sb_publishable_...`) ou anon, em projetos antigos | Project Settings → API Keys | `app/config/app.json`, `.env` e segredo `SUPABASE_PUBLISHABLE_KEY` do GitHub | Sim, protegida pela RLS |
| Chave secreta (`sb_secret_...`) ou service_role, em projetos antigos | Project Settings → API Keys | Só no `.env`, para o script de importação | **Não** |
| Senha do banco | A que você definiu ao criar o projeto. Pode ser redefinida em Project Settings → Database | `.env`, dentro de `DATABASE_URL`, e segredo `SUPABASE_DB_PASSWORD` do GitHub | **Não** |
| String de conexão | Botão **Connect** no topo do painel → Session pooler | `.env` como `DATABASE_URL` | **Não** |
| Project ref | O trecho `xxxx` da URL do projeto | `.env` e segredo `SUPABASE_PROJECT_REF` do GitHub | Sim |
| Token de acesso pessoal (`sbp_...`) | Menu da sua conta → Access Tokens | Segredo `SUPABASE_ACCESS_TOKEN` do GitHub | **Não** |
| `CRON_SECRET` | Você inventa: uma senha longa e aleatória | Segredo da Edge Function e Vault do banco, conforme o passo 3 abaixo | **Não** |

Também é preciso uma chave do **Google Maps**, criada no Google Cloud Console com as APIs *Maps SDK for Android* e *Maps SDK for iOS* ativadas:

- Android: `app/android/local.properties` com a linha `MAPS_API_KEY=...`
- iOS: copie `app/ios/Flutter/Secrets.xcconfig.example` para `Secrets.xcconfig` e preencha

Os arquivos `.env`, `app/config/app.json`, `local.properties` e `Secrets.xcconfig` estão no `.gitignore`.

## Colocar o backend no ar

Requer a [Supabase CLI](https://supabase.com/docs/guides/cli) e Python 3.10+.

1. **Ligue a pasta ao seu projeto e crie o banco:**

   ```bash
   supabase login
   supabase link --project-ref SEU_PROJECT_REF
   supabase db push
   ```

2. **Publique as Edge Functions:**

   ```bash
   supabase functions deploy enviar-precos
   supabase functions deploy sincronizar-cadastro-anp
   supabase functions deploy excluir-conta
   supabase secrets set CRON_SECRET=SUA_SENHA_ALEATORIA
   ```

3. **Libere a sincronização semanal com a ANP.** No SQL Editor do painel, rode:

   ```sql
   select vault.create_secret('https://SEU_PROJECT_REF.supabase.co', 'project_url');
   select vault.create_secret('SUA_SENHA_ALEATORIA', 'cron_secret');
   ```

4. **Configure o login por e-mail.** Em Authentication → URL Configuration, adicione `br.com.gasprice.app://auth-callback` em *Redirect URLs*. O servidor de e-mail padrão do Supabase envia poucas mensagens por hora. Para uso real, configure um SMTP próprio em Authentication → Emails.

5. **Carregue os dados da ANP.** Copie `.env.example` para `.env`, preencha e rode:

   ```bash
   python -m venv .venv
   .venv/Scripts/pip install -r scripts/requirements.txt
   .venv/Scripts/python scripts/anp/limpar_anp.py
   .venv/Scripts/python scripts/supabase/importar_anp.py
   ```

   O importador sincroniza o cadastro dos cerca de 45 mil postos pela API da ANP, carrega os preços desde julho de 2024 e envia a série completa para o Storage. Tudo cabe no plano gratuito.

## Rodar o app

Requer o [Flutter](https://docs.flutter.dev/get-started/install) 3.38 ou mais novo.

```bash
cd app
cp config/app.example.json config/app.json   # preencha URL e chave publishable
flutter pub get
flutter run --dart-define-from-file=config/app.json
```

## Testes

```bash
cd app && flutter analyze && flutter test                    # app
cd supabase/functions && deno test                            # Edge Functions
python scripts/supabase/testar_banco_local.py --pg-bin CAMINHO/DO/POSTGRES/bin   # regras no banco (Postgres 17 + PostGIS)
```

Os mesmos testes rodam no GitHub Actions a cada push.

## Publicação pelo GitHub

Com os segredos cadastrados em *Settings → Secrets and variables → Actions* do repositório:

- **ci.yml:** roda os testes do app, das Edge Functions e do banco em todo push e pull request.
- **deploy-supabase.yml:** a cada push na `main` que mude `supabase/`, aplica as migrações e publica as Edge Functions.
- **build-android.yml:** gera o APK sob demanda, pela aba Actions.

## Documentação

- `documentacao/regras_de_negocio.html`: regras de negócio, diagrama de entidades e relacionamentos e política das fotos.
- `documentacao/limpeza_dados_anp.md`: limpeza das planilhas da ANP.
- `documentacao/experimento_janela_treino.md`: experimento do modelo de previsão.
- `documentacao/cobertura_anp.html`: onde a ANP não pesquisa preços.
