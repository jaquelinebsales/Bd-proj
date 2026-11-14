# GasPrice

App de preços de combustíveis para Android e iOS, em celular e tablet, desenvolvido como projeto acadêmico da disciplina de **Banco de Dados**.

Demonstração no navegador: [gasprice-demo.vercel.app](https://gasprice-demo.vercel.app) (dados fictícios).

## Sobre o projeto

O preço do combustível muda toda semana e varia muito de um posto para outro, mas a pesquisa oficial da ANP é amostral: visita cerca de 9 mil dos 45 mil postos do país, e perto de 65% dos postos nunca tiveram um preço oficial publicado. O GasPrice junta essa pesquisa com preços enviados pela comunidade para mostrar, no mapa, quanto custa o litro em cada posto e de onde vem cada número.

**Objetivo:** ajudar o motorista a escolher onde abastecer com a informação mais recente e confiável disponível, deixando claro se o preço é oficial (ANP), enviado pela comunidade, ou estimado pela região.

## Tratamento dos dados

- **Limpeza das planilhas da ANP:** 13 semestres (2020 a 2026), 5,47 milhões de linhas lidas. Saíram só linhas vazias e repetidas (0,17%). Preços que destoam não são apagados: ficam no banco marcados como anomalia e nunca viram preço exibido.
- **Carga semanal:** toda semana o sistema baixa a planilha nova da ANP com o preço de cada posto pesquisado, grava sem duplicar, aplica a mesma regra de anomalia (comparação com a mediana do estado e com o histórico do próprio posto) e recalcula os preços exibidos.
- **Cadastro dos postos:** sincronizado com a API de Revendedores da ANP, estado por estado. Coordenadas que caem fora do estado do posto (conferidas pelo contorno dos estados do IBGE) são recusadas.
- **Preço exibido:** uma regra no banco escolhe, para cada posto e combustível, o preço mais confiável. A ordem é: comunidade confirmada nos últimos 7 dias, comunidade recente sem divergência, ANP e, sem nenhum dos dois, a estimativa regional.
- **Estimativa regional:** para postos sem preço, a mediana dos 5 postos mais próximos com preço da ANP recente (até 200 km), com margem de erro pela distância, medida no estudo de cobertura.
- **Plano gratuito:** o banco guarda só os últimos ~2 anos de preços da ANP. A série completa fica como arquivo no Storage. Um experimento mostrou que 2 anos bastam para o modelo de previsão.
- **Privacidade:** a foto do painel é lida no próprio aparelho e apagada; ela nunca é enviada. Vão para o servidor só os preços conferidos pela pessoa, a posição e o texto reconhecido.

## Funções do app

- Mapa com os postos ao redor e pinos coloridos pela idade do preço.
- Busca de postos por nome ou endereço, com filtros por combustível, faixa de preço, distância e data da atualização, e ordenação por preço, distância, avaliação ou atualização.
- Página do posto com preços por combustível, origem de cada preço, histórico em gráfico e rota até o posto.
- Envio de preços por foto do painel: o texto é reconhecido no aparelho e a pessoa confere os valores antes de enviar.
- Confirmação da comunidade: outros usuários no posto confirmam ou corrigem o preço enviado.
- "Estou neste posto": corrige a posição de um posto no mapa quando duas pessoas confirmam o mesmo lugar.
- Avaliações dos postos, com nota e votos de utilidade.
- Favoritos e notificações quando o preço de um posto favorito muda.
- Pontos por contribuição (em dobro em municípios sem pesquisa da ANP), ranking e nível de confiabilidade.
- Conta com login por e-mail, recuperação de senha e exclusão da conta.
- Tema claro e escuro, em português.

## Ferramentas utilizadas

| Parte | Ferramentas |
|---|---|
| App (front) | Flutter e Dart, Material 3, go_router, fl_chart (gráficos), Google ML Kit (leitura do painel no aparelho) |
| Mapa | OpenFreeMap, com dados do OpenStreetMap e OpenMapTiles, desenhado pelo MapLibre |
| Banco de dados | Supabase (PostgreSQL com PostGIS para as consultas por distância), regras de acesso por usuário (RLS), regras de negócio em funções SQL e tarefas agendadas com pg_cron |
| Backend | Supabase Edge Functions em TypeScript (Deno): envio de preços, posição dos postos, sincronização com a ANP e exclusão de conta |
| Dados e análises | Python: limpeza das planilhas, carga semanal, estudo de cobertura e experimento do modelo de previsão |
| APIs e fontes de dados | ANP: planilhas semestrais e semanais da pesquisa de preços e API de Revendedores (cadastro e coordenadas dos postos). IBGE: malhas dos estados e municípios |
| Testes e publicação | flutter test, deno test, testes das regras no banco, GitHub Actions (testes, publicação do banco e carga semanal), Vercel (demonstração web) |

## Estrutura do repositório

| Pasta | Conteúdo |
|---|---|
| `app/` | App Flutter (Material 3, go_router, mapa do OpenFreeMap com MapLibre, ML Kit para ler o painel) |
| `supabase/migrations/` | Banco: tabelas, regras de acesso (RLS), regras de negócio e tarefas agendadas |
| `supabase/functions/` | Edge Functions em TypeScript: envio de preços, posição dos postos ("Estou neste posto"), sincronização com a ANP, exclusão de conta |
| `supabase/tests/` | Testes das regras de negócio no banco |
| `scripts/` | Python: limpeza das planilhas da ANP, cobertura, experimento do modelo, publicação e importação no Supabase |
| `documentacao/` | Requisitos, relatórios e mockups |

## Chaves do Supabase

Todas as chaves ficam num único arquivo, o `.env` da raiz do projeto. Copie o `.env.example` para `.env`, preencha, **salve o arquivo** e rode:

```bash
python scripts/supabase/verificar_env.py
```

O script testa cada chave contra o Supabase e diz o que falta, sem nunca mostrar os valores. Nunca coloque uma chave secreta no app nem num arquivo que vá para o GitHub.

| Variável do `.env` | Onde encontrar | Pode ir no app? |
|---|---|---|
| `SUPABASE_URL` | Project Settings → Data API | Sim |
| `SUPABASE_PUBLISHABLE_KEY` (`sb_publishable_...`, ou a anon em projetos antigos) | Project Settings → API Keys | Sim, protegida pelas regras de acesso do banco |
| `SUPABASE_SECRET_KEY` (`sb_secret_...`, ou a service_role em projetos antigos) | Project Settings → API Keys → Secret keys | **Não** |
| `SUPABASE_DB_PASSWORD` | A senha definida ao criar o projeto. Se esqueceu: Project Settings → Database → Reset database password | **Não** |
| `SUPABASE_ACCESS_TOKEN` (`sbp_...`) | supabase.com/dashboard/account/tokens | **Não** |
| `CRON_SECRET` | Você inventa. Para gerar uma: `python scripts/supabase/verificar_env.py --gerar-cron-secret` | **Não** |
| `DATABASE_URL` | **Deixe vazia.** Os scripts montam a conexão sozinhos com a senha do banco e o token de acesso | **Não** |
| `SUPABASE_PROJECT_REF` | **Deixe vazia.** Sai da `SUPABASE_URL` | Sim |

Se preferir informar a `DATABASE_URL` à mão, copie do botão **Connect** no topo do painel, opção **Session pooler**, e troque `[YOUR-PASSWORD]` pela senha. Se a senha tiver `@ : / # ? %`, não use essa linha: deixe-a vazia e preencha só `SUPABASE_DB_PASSWORD`. A conexão direta (`db.xxx.supabase.co`) só funciona em redes com IPv6; o Session pooler funciona em qualquer rede.

O mapa usa o OpenFreeMap (estilos Positron, no tema claro, e Dark, no escuro) desenhado pelo pacote `maplibre`. Não precisa de chave nem de cartão, e o uso é livre, inclusive comercial, sem limite de acessos. Os créditos do OpenFreeMap, do OpenMapTiles e do OpenStreetMap ficam visíveis no canto do mapa e não podem ser removidos. Os endereços dos estilos ficam em `app/lib/telas/mapa/tela_mapa.dart`. Na versão 0.3.6 do `maplibre`, o Android precisa da linha do plugin ktlint em `app/android/settings.gradle.kts`; ela pode sair quando o pacote for atualizado para a 0.3.7.

Os arquivos `.env` e `app/config/app.json` estão no `.gitignore`.

## Colocar o backend no ar

Requer a [Supabase CLI](https://supabase.com/docs/guides/cli) e Python 3.10+ com `pip install -r scripts/requirements.txt`.

1. **Confira o `.env`:** `python scripts/supabase/verificar_env.py`. Só siga quando não houver nenhuma linha `FALHA`.

2. **Publique:** `python scripts/supabase/publicar.py`. Para ver os passos sem executar nada, use `--simular`. O script:
   - aplica as migrações no banco (`supabase db push`);
   - publica as quatro Edge Functions, sem precisar de Docker;
   - grava o `CRON_SECRET` nas funções e o endereço e a senha da sincronização no Vault do banco;
   - chama cada função sem login e confere que ela respondeu certo.

3. **Configure o login por e-mail.** Em Authentication → URL Configuration, adicione `br.com.gasprice.app://auth-callback` em *Redirect URLs*. O servidor de e-mail padrão do Supabase envia poucas mensagens por hora. Para uso real, configure um SMTP próprio em Authentication → Emails.

4. **Carregue os dados da ANP:**

   ```bash
   python scripts/anp/limpar_anp.py
   python scripts/supabase/importar_anp.py
   ```

   O importador sincroniza o cadastro dos cerca de 45 mil postos pela API da ANP, carrega os preços desde julho de 2024 e envia a série completa para o Storage. Tudo cabe no plano gratuito. O `publicar.py --com-dados` faz os passos 2 e 4 de uma vez.

## Rodar o app

Requer o [Flutter](https://docs.flutter.dev/get-started/install) 3.38 ou mais novo.

```bash
cd app
cp config/app.example.json config/app.json   # preencha URL e chave publishable
flutter pub get
flutter run --dart-define-from-file=config/app.json
```

Para ver as telas sem o Supabase, com dados de exemplo: `flutter run -d chrome --dart-define=DEMO=true`.

## Testes

```bash
cd app && flutter analyze && flutter test                    # app
cd supabase/functions && deno test                            # Edge Functions
python -m unittest discover -s scripts/supabase -p "test_*.py"   # scripts de publicação
python scripts/supabase/testar_banco_local.py --pg-bin CAMINHO/DO/POSTGRES/bin   # regras no banco (Postgres 17 + PostGIS)
```

Os mesmos testes rodam no GitHub Actions a cada push.

## Publicação pelo GitHub

Com os segredos cadastrados em *Settings → Secrets and variables → Actions* do repositório:

| Segredo | Usado por |
|---|---|
| `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`, `SUPABASE_PROJECT_REF` | deploy-supabase.yml |
| `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | build-android.yml |

- **ci.yml:** roda os testes do app, das Edge Functions, dos scripts e do banco em todo push e pull request.
- **deploy-supabase.yml:** a cada push na `main` que mude `supabase/`, aplica as migrações e publica as Edge Functions.
- **build-android.yml:** gera o APK sob demanda, pela aba Actions.

## Documentação

- `documentacao/regras_de_negocio.html`: regras de negócio, diagrama de entidades e relacionamentos e política das fotos.
- `documentacao/limpeza_dados_anp.md`: limpeza das planilhas da ANP.
- `documentacao/experimento_janela_treino.md`: experimento do modelo de previsão.
- `documentacao/cobertura_anp.html`: onde a ANP não pesquisa preços.
