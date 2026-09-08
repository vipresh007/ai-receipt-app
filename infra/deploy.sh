#!/usr/bin/env bash
# Build + deploy the backend and web apps to Azure Container Apps. Idempotent.
#
#   ./infra/deploy.sh                 # build + deploy both
#   TARGET=backend ./infra/deploy.sh  # just one  (backend | web | both)
#
# Prereqs: ./infra/provision.sh has run (resource group + Postgres + OpenAI +
# storage + App Insights exist), az is logged in, infra/.env.infra is filled.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
[ -f "$HERE/.env.infra" ] && { set -a; . "$HERE/.env.infra"; set +a; }

NAME_PREFIX="${NAME_PREFIX:-ai-receipt-dev}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-ai-receipt-dev}"
LOCATION="${LOCATION:-eastus2}"
TARGET="${TARGET:-both}"
TAG="${TAG:-$(date +%Y%m%d%H%M%S)}"
# REUSE_LATEST=1 skips `az acr build` and redeploys the existing :latest images.
[ "${REUSE_LATEST:-}" = "1" ] && TAG="latest"

ACR_NAME="${ACR_NAME:-$(printf '%s' "${NAME_PREFIX}acr" | tr -cd 'a-z0-9')}"
CAE_NAME="${CAE_NAME:-${NAME_PREFIX}-cae}"
API_APP="${API_APP:-${NAME_PREFIX}-api}"
WEB_APP="${WEB_APP:-${NAME_PREFIX}-web}"

OPENAI_NAME="${OPENAI_NAME:-${NAME_PREFIX}-openai}"
OPENAI_DEPLOYMENT="${OPENAI_DEPLOYMENT:-gpt-5-mini}"
PG_NAME="${PG_NAME:-${NAME_PREFIX}-pg}"
PG_ADMIN_USER="${PG_ADMIN_USER:-airadmin}"
PG_DB="${PG_DB:-ai_receipt}"
STORAGE_CONTAINER="${STORAGE_CONTAINER:-receipts}"
LOGS_NAME="${LOGS_NAME:-${NAME_PREFIX}-logs}"
APPI_NAME="${APPI_NAME:-${NAME_PREFIX}-appi}"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# ---- Auth0 config: env wins, else read web/.env.local, else backend/.env ----
_from_env_file() {  # $1 KEY  $2 file
  [ -f "$2" ] && grep -E "^$1=" "$2" | head -1 | cut -d= -f2- || true
}
WEB_ENV="$ROOT/web/.env.local"
API_ENV="$ROOT/backend/.env"
AUTH0_DOMAIN="${AUTH0_DOMAIN:-$(_from_env_file AUTH0_DOMAIN "$WEB_ENV")}"
AUTH0_CLIENT_ID="${AUTH0_CLIENT_ID:-$(_from_env_file AUTH0_CLIENT_ID "$WEB_ENV")}"
AUTH0_CLIENT_SECRET="${AUTH0_CLIENT_SECRET:-$(_from_env_file AUTH0_CLIENT_SECRET "$WEB_ENV")}"
AUTH0_SECRET="${AUTH0_SECRET:-$(_from_env_file AUTH0_SECRET "$WEB_ENV")}"
AUTH0_AUDIENCE="${AUTH0_AUDIENCE:-$(_from_env_file AUTH0_AUDIENCE "$WEB_ENV")}"
[ -n "$AUTH0_AUDIENCE" ] || AUTH0_AUDIENCE="$(_from_env_file AUTH0_AUDIENCE "$API_ENV")"
if [ -z "$AUTH0_DOMAIN" ] || [ -z "$AUTH0_AUDIENCE" ]; then
  echo "WARNING: AUTH0_DOMAIN / AUTH0_AUDIENCE not set (see docs/AUTH.md)."
  echo "         Deploying anyway — protected routes will 401 until they're configured."
fi

say "Registering providers"
for p in Microsoft.App Microsoft.ContainerRegistry Microsoft.OperationalInsights; do
  s="$(az provider show -n "$p" --query registrationState -o tsv 2>/dev/null || echo NotRegistered)"
  [ "$s" = "Registered" ] || { echo "  registering $p"; az provider register -n "$p" --wait -o none; }
done
az extension show -n containerapp -o none 2>/dev/null || az extension add -n containerapp -y -o none

say "Container registry: $ACR_NAME"
az acr show -n "$ACR_NAME" -g "$RESOURCE_GROUP" -o none 2>/dev/null || \
  az acr create -n "$ACR_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" --sku Basic -o none
az acr update -n "$ACR_NAME" --admin-enabled true -o none
ACR_SERVER="$(az acr show -n "$ACR_NAME" -g "$RESOURCE_GROUP" --query loginServer -o tsv)"
ACR_USER="$(az acr credential show -n "$ACR_NAME" --query username -o tsv)"
ACR_PASS="$(az acr credential show -n "$ACR_NAME" --query 'passwords[0].value' -o tsv)"

say "Container Apps environment: $CAE_NAME"
if ! az containerapp env show -n "$CAE_NAME" -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
  LOGS_CID="$(az monitor log-analytics workspace show -n "$LOGS_NAME" -g "$RESOURCE_GROUP" --query customerId -o tsv)"
  LOGS_KEY="$(az monitor log-analytics workspace get-shared-keys -n "$LOGS_NAME" -g "$RESOURCE_GROUP" --query primarySharedKey -o tsv)"
  az containerapp env create -n "$CAE_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" \
    --logs-workspace-id "$LOGS_CID" --logs-workspace-key "$LOGS_KEY" -o none
fi

# deploy_app NAME IMAGE PORT SECRETS_KV ENV_KV
#   SECRETS_KV / ENV_KV are space-separated KEY=VALUE (values must not contain
#   spaces — ours don't). `create` takes --secrets/--env-vars; `update` needs
#   `secret set` + `--set-env-vars` instead.
deploy_app() {
  local name="$1" image="$2" port="$3" secrets_kv="$4" env_kv="$5"
  if az containerapp show -n "$name" -g "$RESOURCE_GROUP" -o none 2>/dev/null; then
    az containerapp registry set -n "$name" -g "$RESOURCE_GROUP" \
      --server "$ACR_SERVER" --username "$ACR_USER" --password "$ACR_PASS" -o none
    if [ -n "$secrets_kv" ]; then
      # shellcheck disable=SC2086
      az containerapp secret set -n "$name" -g "$RESOURCE_GROUP" --secrets $secrets_kv -o none
    fi
    # shellcheck disable=SC2086
    az containerapp update -n "$name" -g "$RESOURCE_GROUP" --image "$image" \
      ${env_kv:+--set-env-vars $env_kv} -o none
  else
    # shellcheck disable=SC2086
    az containerapp create -n "$name" -g "$RESOURCE_GROUP" --environment "$CAE_NAME" \
      --image "$image" --target-port "$port" --ingress external \
      --registry-server "$ACR_SERVER" --registry-username "$ACR_USER" --registry-password "$ACR_PASS" \
      --min-replicas 0 --max-replicas 2 --cpu 0.5 --memory 1.0Gi \
      ${secrets_kv:+--secrets $secrets_kv} ${env_kv:+--env-vars $env_kv} -o none
  fi
  az containerapp show -n "$name" -g "$RESOURCE_GROUP" --query properties.configuration.ingress.fqdn -o tsv
}

if [ "$TARGET" = "backend" ] || [ "$TARGET" = "both" ]; then
  if [ "$TAG" != "latest" ]; then
    say "Build backend image (az acr build)"
    az acr build -r "$ACR_NAME" -t "ai-receipt-api:$TAG" -t "ai-receipt-api:latest" \
      -f "$ROOT/backend/Dockerfile" "$ROOT/backend" -o none
  fi

  OPENAI_ENDPOINT="$(az cognitiveservices account show -n "$OPENAI_NAME" -g "$RESOURCE_GROUP" --query 'properties.endpoint' -o tsv)"
  OPENAI_KEY="$(az cognitiveservices account keys list -n "$OPENAI_NAME" -g "$RESOURCE_GROUP" --query key1 -o tsv)"
  PG_FQDN="$(az postgres flexible-server show -n "$PG_NAME" -g "$RESOURCE_GROUP" --query fullyQualifiedDomainName -o tsv)"
  STORAGE_CONN="$(grep -E '^AZURE_STORAGE_CONNECTION_STRING=' "$ROOT/backend/.env" 2>/dev/null | head -1 | cut -d= -f2- || true)"
  APPI_CONN="$(az monitor app-insights component show --app "$APPI_NAME" -g "$RESOURCE_GROUP" --query connectionString -o tsv)"
  DB_URL="postgresql+asyncpg://${PG_ADMIN_USER}:${PG_ADMIN_PASSWORD}@${PG_FQDN}:5432/${PG_DB}?ssl=require"

  say "Deploy $API_APP"
  api_secrets="database-url=$DB_URL aoai-key=$OPENAI_KEY storage-conn=$STORAGE_CONN appi-conn=$APPI_CONN"
  api_env="ENVIRONMENT=production LOG_LEVEL=INFO AUTO_CREATE_TABLES=true"
  api_env="$api_env DATABASE_URL=secretref:database-url"
  api_env="$api_env AUTH0_DOMAIN=$AUTH0_DOMAIN AUTH0_AUDIENCE=$AUTH0_AUDIENCE"
  api_env="$api_env AZURE_OPENAI_ENDPOINT=$OPENAI_ENDPOINT AZURE_OPENAI_API_KEY=secretref:aoai-key"
  api_env="$api_env AZURE_OPENAI_API_VERSION=2025-04-01-preview AZURE_OPENAI_DEPLOYMENT=$OPENAI_DEPLOYMENT"
  api_env="$api_env AZURE_STORAGE_CONNECTION_STRING=secretref:storage-conn AZURE_STORAGE_CONTAINER=$STORAGE_CONTAINER"
  api_env="$api_env APPLICATIONINSIGHTS_CONNECTION_STRING=secretref:appi-conn"
  API_FQDN="$(deploy_app "$API_APP" "$ACR_SERVER/ai-receipt-api:$TAG" 8000 "$api_secrets" "$api_env")"
  echo "backend: https://$API_FQDN"
fi

if [ "$TARGET" = "web" ] || [ "$TARGET" = "both" ]; then
  if [ "$TAG" != "latest" ]; then
    say "Build web image (az acr build, root context)"
    az acr build -r "$ACR_NAME" -t "ai-receipt-web:$TAG" -t "ai-receipt-web:latest" \
      -f "$ROOT/web/Dockerfile" "$ROOT" -o none
  fi

  if [ -z "${API_FQDN:-}" ]; then
    API_FQDN="$(az containerapp show -n "$API_APP" -g "$RESOURCE_GROUP" --query properties.configuration.ingress.fqdn -o tsv 2>/dev/null || true)"
  fi
  [ -n "$API_FQDN" ] || { echo "No backend FQDN — deploy backend first."; exit 1; }

  say "Deploy $WEB_APP"
  web_secrets="auth0-client-secret=$AUTH0_CLIENT_SECRET auth0-secret=$AUTH0_SECRET"
  web_env="NODE_ENV=production BACKEND_URL=https://$API_FQDN"
  web_env="$web_env AUTH0_DOMAIN=$AUTH0_DOMAIN AUTH0_CLIENT_ID=$AUTH0_CLIENT_ID AUTH0_AUDIENCE=$AUTH0_AUDIENCE"
  web_env="$web_env AUTH0_CLIENT_SECRET=secretref:auth0-client-secret AUTH0_SECRET=secretref:auth0-secret"
  WEB_FQDN="$(deploy_app "$WEB_APP" "$ACR_SERVER/ai-receipt-web:$TAG" 3000 "$web_secrets" "$web_env")"

  # APP_BASE_URL needs the app's own FQDN, known only after the first create.
  az containerapp update -n "$WEB_APP" -g "$RESOURCE_GROUP" \
    --set-env-vars APP_BASE_URL="https://$WEB_FQDN" -o none
  echo "web: https://$WEB_FQDN"
fi

say "Done"
[ -n "${API_FQDN:-}" ] && echo "  API  https://$API_FQDN  (docs: /docs)"
[ -n "${WEB_FQDN:-}" ] && echo "  Web  https://$WEB_FQDN"
