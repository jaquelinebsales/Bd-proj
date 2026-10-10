#!/usr/bin/env bash
# Carga semanal da pesquisa de preços da ANP no banco do servidor (schema combustivel).
# Roda scripts/anp/carga_semanal.py num container Python descartável. A senha do banco é lida do
# /opt/supabase/.env aqui mesmo e não fica gravada em lugar nenhum. Log: /var/log/gasprice-carga-anp.log
#
# Uso: sudo /opt/gasprice/carga-anp.sh            (o carga-anp.timer roda às segundas e quintas)
#      sudo /opt/gasprice/carga-anp.sh --simular  (só mostra o que faria)
set -euo pipefail

SCRIPTS=/opt/gasprice/scripts
ENV_SUPABASE=/opt/supabase/.env
[ -f "$SCRIPTS/anp/carga_semanal.py" ] || { echo "ERRO: falta $SCRIPTS/anp/carga_semanal.py (copie a pasta scripts do repositório)"; exit 1; }

valor() { grep "^$1=" "$ENV_SUPABASE" | cut -d= -f2-; }
SENHA=$(valor POSTGRES_PASSWORD)
TENANT=$(valor POOLER_TENANT_ID)
URL="postgresql://postgres.${TENANT}:$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$SENHA")@localhost:5432/postgres"

echo "[$(date '+%F %T')] início da carga da ANP"
docker run --rm --network host \
  -e DATABASE_URL="$URL" -e SUPABASE_SCHEMA=combustivel \
  -v "$SCRIPTS:/app/scripts:ro" -w /app python:3.12-slim \
  sh -c 'pip install --quiet --disable-pip-version-check "psycopg[binary]" openpyxl && python scripts/anp/carga_semanal.py "$@"' _ "$@"
echo "[$(date '+%F %T')] fim da carga da ANP"
