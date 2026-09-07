#!/usr/bin/env bash
# Provision the Azure resources for AI Receipt. Idempotent: safe to re-run.
#
#   ./infra/provision.sh            # uses infra/.env.infra if present, else defaults
#   NAME_PREFIX=foo LOCATION=eastus2 ./infra/provision.sh
#
# Requires: az CLI, logged in (`az login`), correct subscription selected
#   (`az account set --subscription <id>`).
#
# On success it prints the values to paste into backend/.env.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/.env.infra" ] && { set -a; . "$HERE/.env.infra"; set +a; }

NAME_PREFIX="${NAME_PREFIX:-airreceipt}"
LOCATION="${LOCATION:-eastus}"
RESOURCE_GROUP="${RESOURCE_GROUP:-${NAME_PREFIX}-rg}"

OPENAI_NAME="${OPENAI_NAME:-${NAME_PREFIX}-openai}"
# gpt-4o / gpt-4o-mini are deprecated on Azure OpenAI; the current small
# multimodal tier is the gpt-5-mini family. Override any of these to change.
OPENAI_MODEL="${OPENAI_MODEL:-gpt-5-mini}"
OPENAI_MODEL_VERSION="${OPENAI_MODEL_VERSION:-2025-08-07}"
OPENAI_DEPLOYMENT="${OPENAI_DEPLOYMENT:-gpt-5-mini}"
OPENAI_SKU="${OPENAI_SKU:-GlobalStandard}"   # gpt-5* minis don't offer plain "Standard"
OPENAI_CAPACITY="${OPENAI_CAPACITY:-20}"     # thousands of tokens/min

PG_NAME="${PG_NAME:-${NAME_PREFIX}-pg}"
PG_ADMIN_USER="${PG_ADMIN_USER:-airadmin}"
PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD:-}"
PG_DB="${PG_DB:-ai_receipt}"
PG_TIER="${PG_TIER:-Burstable}"
PG_SKU="${PG_SKU:-Standard_B1ms}"
PG_STORAGE_GB="${PG_STORAGE_GB:-32}"
PG_VERSION="${PG_VERSION:-16}"

# Storage account name: 3-24 chars, lowercase letters + digits only.
if [ -z "${STORAGE_NAME:-}" ]; then
  _s="$(printf '%s' "${NAME_PREFIX}sa${RANDOM}" | tr -cd 'a-z0-9')"
  STORAGE_NAME="${_s:0:24}"
fi
STORAGE_CONTAINER="${STORAGE_CONTAINER:-receipts}"

LOGS_NAME="${LOGS_NAME:-${NAME_PREFIX}-logs}"
APPI_NAME="${APPI_NAME:-${NAME_PREFIX}-appi}"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

if [ -z "$PG_ADMIN_PASSWORD" ]; then
  _raw="$(uuidgen)$(uuidgen)"
  _raw="${_raw//-/}"
  PG_ADMIN_PASSWORD="${_raw:0:24}Aa1!"
  echo "Generated Postgres admin password (save it): $PG_ADMIN_PASSWORD"
fi

say "Subscription"
az account show --query '{name:name, id:id}' -o table

say "Resource group: $RESOURCE_GROUP ($LOCATION)"
az group create -n "$RESOURCE_GROUP" -l "$LOCATION" -o none

say "Azure OpenAI account: $OPENAI_NAME"
az cognitiveservices account show -n "$OPENAI_NAME" -g "$RESOURCE_GROUP" -o none 2>/dev/null || \
az cognitiveservices account create \
  -n "$OPENAI_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" \
  --kind OpenAI --sku S0 --custom-domain "$OPENAI_NAME" --yes -o none

say "Model deployment: $OPENAI_DEPLOYMENT ($OPENAI_MODEL:$OPENAI_MODEL_VERSION)"
az cognitiveservices account deployment show \
  -n "$OPENAI_NAME" -g "$RESOURCE_GROUP" --deployment-name "$OPENAI_DEPLOYMENT" -o none 2>/dev/null || \
az cognitiveservices account deployment create \
  -n "$OPENAI_NAME" -g "$RESOURCE_GROUP" \
  --deployment-name "$OPENAI_DEPLOYMENT" \
  --model-name "$OPENAI_MODEL" --model-version "$OPENAI_MODEL_VERSION" --model-format OpenAI \
  --sku-name "$OPENAI_SKU" --sku-capacity "$OPENAI_CAPACITY" -o none

say "PostgreSQL Flexible Server: $PG_NAME ($PG_SKU)"
az postgres flexible-server show -n "$PG_NAME" -g "$RESOURCE_GROUP" -o none 2>/dev/null || \
az postgres flexible-server create \
  -n "$PG_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" \
  --tier "$PG_TIER" --sku-name "$PG_SKU" --storage-size "$PG_STORAGE_GB" \
  --version "$PG_VERSION" \
  --admin-user "$PG_ADMIN_USER" --admin-password "$PG_ADMIN_PASSWORD" \
  --public-access 0.0.0.0 --yes -o none

az postgres flexible-server db show -d "$PG_DB" -s "$PG_NAME" -g "$RESOURCE_GROUP" -o none 2>/dev/null || \
az postgres flexible-server db create -d "$PG_DB" -s "$PG_NAME" -g "$RESOURCE_GROUP" -o none

# Allow Azure services (adjust/remove for production; add your IP for local dev).
az postgres flexible-server firewall-rule create \
  -n "$PG_NAME" -g "$RESOURCE_GROUP" --rule-name AllowAzure \
  --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 -o none 2>/dev/null || true

say "Storage account: $STORAGE_NAME + container $STORAGE_CONTAINER"
az storage account show -n "$STORAGE_NAME" -g "$RESOURCE_GROUP" -o none 2>/dev/null || \
az storage account create \
  -n "$STORAGE_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 --allow-blob-public-access false -o none
STORAGE_CONN="$(az storage account show-connection-string -n "$STORAGE_NAME" -g "$RESOURCE_GROUP" --query connectionString -o tsv)"
az storage container create --name "$STORAGE_CONTAINER" --connection-string "$STORAGE_CONN" -o none

say "Application Insights: $APPI_NAME (workspace $LOGS_NAME)"
az monitor log-analytics workspace show -n "$LOGS_NAME" -g "$RESOURCE_GROUP" -o none 2>/dev/null || \
az monitor log-analytics workspace create -n "$LOGS_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" -o none
LOGS_ID="$(az monitor log-analytics workspace show -n "$LOGS_NAME" -g "$RESOURCE_GROUP" --query id -o tsv)"
az extension show -n application-insights -o none 2>/dev/null || az extension add -n application-insights -y -o none
az monitor app-insights component show --app "$APPI_NAME" -g "$RESOURCE_GROUP" -o none 2>/dev/null || \
az monitor app-insights component create \
  --app "$APPI_NAME" -g "$RESOURCE_GROUP" -l "$LOCATION" \
  --workspace "$LOGS_ID" --application-type web -o none

# ----- Gather outputs -----
OPENAI_ENDPOINT="$(az cognitiveservices account show -n "$OPENAI_NAME" -g "$RESOURCE_GROUP" --query properties.endpoint -o tsv)"
OPENAI_KEY="$(az cognitiveservices account keys list -n "$OPENAI_NAME" -g "$RESOURCE_GROUP" --query key1 -o tsv)"
PG_FQDN="$(az postgres flexible-server show -n "$PG_NAME" -g "$RESOURCE_GROUP" --query fullyQualifiedDomainName -o tsv)"
APPI_CONN="$(az monitor app-insights component show --app "$APPI_NAME" -g "$RESOURCE_GROUP" --query connectionString -o tsv)"

DB_URL="postgresql+asyncpg://${PG_ADMIN_USER}:${PG_ADMIN_PASSWORD}@${PG_FQDN}:5432/${PG_DB}?ssl=require"

cat <<ENV

============================================================
Provisioning complete. Paste into backend/.env:
============================================================
DATABASE_URL=${DB_URL}
AZURE_OPENAI_ENDPOINT=${OPENAI_ENDPOINT%/}
AZURE_OPENAI_API_KEY=${OPENAI_KEY}
AZURE_OPENAI_API_VERSION=2025-04-01-preview
AZURE_OPENAI_DEPLOYMENT=${OPENAI_DEPLOYMENT}
AZURE_STORAGE_CONNECTION_STRING=${STORAGE_CONN}
AZURE_STORAGE_CONTAINER=${STORAGE_CONTAINER}
APPLICATIONINSIGHTS_CONNECTION_STRING=${APPI_CONN}
============================================================
Postgres admin password: ${PG_ADMIN_PASSWORD}
(Store secrets in a vault / GitHub Actions secrets — do not commit .env)
ENV
