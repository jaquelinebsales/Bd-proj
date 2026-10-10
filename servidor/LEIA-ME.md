# gasprice no servidor próprio (servidor-michael)

Roteiro para completar o Supabase self-hosted depois da cópia dos dados para o schema `combustivel`.
Feito para ser seguido no PC que tem acesso de administrador à VM (`ssh michael@servidor-michael`).

Situação conferida em 10/10/2026, só lendo o banco pela Tailscale:

| Item | Situação |
|---|---|
| Dados (`combustivel`): 1.872.416 preços da ANP, 51.056 postos, 38 funções, PostGIS | ok |
| API com a chave pública e `Accept-Profile: combustivel` | ok |
| Gatilho `ao_criar_usuario` em `auth.users` | **falta** (quem se cadastra fica sem perfil) |
| Buckets `avatares` e `anp-historico` e políticas | **falta** |
| `combustivel.notificacoes` no Realtime | **falta** |
| Vault (`project_url`, `cron_secret`) e pg_cron com as 4 tarefas | **falta** (o pg_cron já está pré-carregado) |
| Edge Functions | **falta** (404) |
| Cadastro de contas | **desligado** (`DISABLE_SIGNUP=true`) |

Nenhum comando abaixo mostra senha ou chave no terminal. Não cole segredos em chat.

## 0. Levar os arquivos para a VM

No PC com o repositório atualizado (depois do `git pull`), copie a pasta `servidor`, as Edge Functions e os scripts:

```powershell
ssh michael@servidor-michael "mkdir -p /tmp/gasprice"
scp -r servidor supabase/functions scripts michael@servidor-michael:/tmp/gasprice/
```

Ficam `/tmp/gasprice/servidor`, `/tmp/gasprice/functions` e `/tmp/gasprice/scripts`.

Na VM:

```bash
sudo mkdir -p /opt/gasprice && sudo cp -r /tmp/gasprice/scripts /opt/gasprice/
sudo cp /tmp/gasprice/servidor/carga-anp.sh /opt/gasprice/ && sudo chmod 700 /opt/gasprice/carga-anp.sh
```

## 1. Variáveis em /opt/supabase/.env

Faça uma cópia antes: `sudo cp /opt/supabase/.env /opt/supabase/.env.bak-$(date +%Y%m%d-%H%M%S)`.
Depois ajuste (com `sudo nano /opt/supabase/.env`):

| Variável | Valor |
|---|---|
| `DISABLE_SIGNUP` | `false` |
| `ENABLE_EMAIL_SIGNUP` | `true` |
| `ENABLE_EMAIL_AUTOCONFIRM` | `true` enquanto o e-mail não estiver configurado; `false` depois do passo 5 (Brevo) |
| `FUNCTIONS_VERIFY_JWT` | `false` (as funções do gasprice conferem o login sozinhas; a de sincronização usa o `x-cron-secret`) |
| `GASPRICE_CRON_SECRET` | o mesmo valor de `CRON_SECRET` do `.env` do projeto (linha nova) |
| `ADDITIONAL_REDIRECT_URLS` | `br.com.gasprice.app://auth-callback` |

`SITE_URL`, `API_EXTERNAL_URL` e `SUPABASE_PUBLIC_URL` mudam no passo 6, quando houver o endereço público.

## 2. Complemento do docker compose

```bash
cd /opt/supabase
ls docker-compose.override.yml 2>/dev/null && echo "JÁ EXISTE: junte os blocos à mão"
sudo cp /tmp/gasprice/servidor/docker-compose.override.yml /opt/supabase/
grep '^COMPOSE_FILE=' .env
```

**Atenção:** o `.env` do servidor define `COMPOSE_FILE=docker-compose.yml`, e com isso o compose **ignora** o
override. Troque a linha por `COMPOSE_FILE=docker-compose.yml:docker-compose.override.yml` e só então rode:

```bash
sudo docker compose up -d
```

O `up -d` relê o `.env` e o override (o `restart` não relê). Confira: `sudo docker compose ps` com tudo `healthy`,
e que a regra de senha e o `GASPRICE_SCHEMA` chegaram aos containers
(`sudo docker compose config | grep -E 'GOTRUE_PASSWORD|GASPRICE_SCHEMA'`).

## 3. Banco: gatilho, Storage, Realtime, Vault e pg_cron

```bash
CRON_SECRET=$(sudo grep '^GASPRICE_CRON_SECRET=' /opt/supabase/.env | cut -d= -f2-)
sudo docker exec -i supabase-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 \
  -v project_url='http://kong:8000' -v cron_secret="$CRON_SECRET" < /tmp/gasprice/servidor/configurar_banco.sql
unset CRON_SECRET
```

O fim mostra a conferência: gatilho `1`, buckets `anp-historico, avatares`, 4 políticas, `combustivel.notificacoes`
no Realtime, `cron_secret, project_url` no Vault e as 4 tarefas `gasprice-*`. Pode rodar de novo sem estragar nada.

## 4. Edge Functions

```bash
sudo bash /tmp/gasprice/servidor/publicar_funcoes.sh /tmp/gasprice/functions
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost:8000/functions/v1/enviar-precos -H 'Content-Type: application/json' -d '{}'
```

Esperado: `401` (a função recusa quem não está logado). `404` quer dizer que a função não foi publicada.
Na primeira chamada as funções baixam o `supabase-js` do npm: a VM precisa de internet.

## 5. E-mail pelo Brevo (faça ANTES do Funnel)

Com o cadastro aberto e a confirmação de e-mail automática (passo 1), quem alcançar o servidor cria conta sem
confirmar o e-mail. Hoje só chega quem está na Tailscale; com o Funnel ligado seria qualquer pessoa na internet.
Por isso o e-mail vem primeiro, e `ENABLE_EMAIL_AUTOCONFIRM` volta para `false` aqui.

No `/opt/supabase/.env`:

| Variável | Valor |
|---|---|
| `SMTP_HOST` | `smtp-relay.brevo.com` |
| `SMTP_PORT` | `587` |
| `SMTP_USER` | o Login do Brevo (`xxxx@smtp-brevo.com`) |
| `SMTP_PASS` | a chave SMTP do Brevo (digite você mesmo; não passe por chat) |
| `SMTP_ADMIN_EMAIL` | o remetente verificado no Brevo |
| `SMTP_SENDER_NAME` | `gasprice` |
| `ENABLE_EMAIL_AUTOCONFIRM` | `false` |

Depois: `cd /opt/supabase && sudo docker compose up -d`. Teste criando uma conta com outro e-mail seu: o link de
confirmação deve chegar (veja também o spam).

## 6. Endereço público com HTTPS (Tailscale Funnel)

O app no celular precisa de HTTPS e de um endereço que qualquer aparelho alcance. Na conta da Tailscale:
DNS → ligar MagicDNS e HTTPS Certificates; Access controls → permitir `funnel` para o servidor
(`"nodeAttrs": [{"target": ["autogroup:member"], "attr": ["funnel"]}]`).

Antes, troque a senha do Studio (`sudo definir-login-studio.sh <usuario>`). Depois, publique **só os caminhos que o
app usa**, e não a porta inteira: assim o Studio e o resto da API não ficam na internet.

```bash
for c in rest/v1 auth/v1 functions/v1 storage/v1 realtime/v1; do
  sudo tailscale funnel --bg --https=443 --set-path "/$c" "http://localhost:8000/$c"
done
tailscale funnel status
curl -s -o /dev/null -w 'raiz: %{http_code}\n' https://servidor-michael.<sua-rede>.ts.net/
```

A raiz (`/`), onde fica o Studio, deve responder 404 ou ser recusada. Se o `--set-path` não existir na versão da
Tailscale instalada, ou a raiz continuar respondendo, publique a porta inteira com
`sudo tailscale funnel --bg --https=443 http://localhost:8000` e confie na senha forte do Studio.

O endereço fica `https://servidor-michael.<sua-rede>.ts.net`. Ponha esse endereço em `SITE_URL`, `API_EXTERNAL_URL`
e `SUPABASE_PUBLIC_URL` no `/opt/supabase/.env` e rode `cd /opt/supabase && sudo docker compose up -d`.

## 7. Carga semanal da ANP no próprio servidor

```bash
sudo cp /tmp/gasprice/servidor/gasprice-carga-anp.service /tmp/gasprice/servidor/gasprice-carga-anp.timer /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now gasprice-carga-anp.timer
sudo /opt/gasprice/carga-anp.sh --simular      # só mostra as semanas que faltam
sudo systemctl start gasprice-carga-anp         # carrega de verdade (log: /var/log/gasprice-carga-anp.log)
```

Em 10/10/2026 faltava a semana de 04/10/2026 (17.085 preços).

## 8. Fora do servidor

- GitHub (Settings → Secrets and variables → Actions):
  - segredo `SUPABASE_URL` = o endereço do Funnel (passo 6)
  - segredo `SUPABASE_PUBLISHABLE_KEY` = a `ANON_KEY` do servidor (`sudo cat /root/supabase-segredos.txt`)
  - aba Variables → variável `SUPABASE_SCHEMA` = `combustivel`
- Rodar "Gerar APK", desinstalar o app antigo do celular e instalar o novo.
- Só depois de tudo funcionar: pausar o projeto do Supabase da nuvem.
