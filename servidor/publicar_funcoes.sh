#!/usr/bin/env bash
# Publica (ou atualiza) as Edge Functions do gasprice no Supabase self-hosted.
# Copia supabase/functions/<nome> e _shared para /opt/supabase/volumes/functions e recria o container.
#
# Uso, no servidor:  sudo bash servidor/publicar_funcoes.sh [pasta-das-funcoes]
#   sem argumento, usa supabase/functions a partir da pasta atual (raiz do repositório)
set -euo pipefail

ORIGEM=${1:-supabase/functions}
DESTINO=/opt/supabase/volumes/functions
FUNCOES=(enviar-precos corrigir-posicao sincronizar-cadastro-anp excluir-conta)

[ -d "$ORIGEM/_shared" ] || { echo "ERRO: falta $ORIGEM/_shared (informe a pasta das funções)"; exit 1; }
[ -d "$DESTINO/main" ] || { echo "ERRO: $DESTINO/main não existe (o Supabase está em /opt/supabase?)"; exit 1; }
grep -q '^GASPRICE_CRON_SECRET=.' /opt/supabase/.env || { echo "ERRO: falta GASPRICE_CRON_SECRET em /opt/supabase/.env"; exit 1; }

for nome in _shared "${FUNCOES[@]}"; do
  rm -rf "${DESTINO:?}/$nome"
  mkdir -p "$DESTINO/$nome"
  # Os testes (*_test.ts) não vão para o servidor
  find "$ORIGEM/$nome" -maxdepth 1 -type f -name '*.ts' ! -name '*_test.ts' -exec cp {} "$DESTINO/$nome/" \;
  echo "copiada: $nome ($(ls "$DESTINO/$nome" | tr '\n' ' '))"
done

# "up -d" relê o .env e o override; "restart" não relê
cd /opt/supabase && docker compose up -d functions
echo "Edge Functions publicadas. Teste: curl -s -X POST http://localhost:8000/functions/v1/enviar-precos -H 'Content-Type: application/json' -d '{}'"
echo "(sem login, a resposta esperada é um erro 401 da própria função, e não 404)"
