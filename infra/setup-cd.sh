#!/usr/bin/env bash
# One-time: set up GitHub Actions → Azure OIDC so pushes to main auto-deploy.
#
#   ./infra/setup-cd.sh
#
# Creates an Entra app registration + service principal, a federated credential
# for this repo's `main` branch, grants it Contributor on the resource group,
# and sets the repo secrets (via `gh`). Idempotent.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/.env.infra" ] && { set -a; . "$HERE/.env.infra"; set +a; }

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-ai-receipt-dev}"
APP_NAME="${OIDC_APP_NAME:-ai-receipt-github-oidc}"
REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
WEB_ENV="$HERE/../web/.env.local"

SUB_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
echo "repo=$REPO  rg=$RESOURCE_GROUP  sub=$SUB_ID"

APP_ID="$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)"
[ -n "$APP_ID" ] || APP_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
az ad sp show --id "$APP_ID" -o none 2>/dev/null || az ad sp create --id "$APP_ID" -o none
echo "app id: $APP_ID"

# GitHub's OIDC subject now embeds owner/repo IDs
# (e.g. repo:owner@<id>/repo@<id>:ref:refs/heads/main) — read the real prefix.
SUB_PREFIX="$(gh api "/repos/${REPO}/actions/oidc/customization/sub" -q .sub_claim_prefix 2>/dev/null)"
[ -n "$SUB_PREFIX" ] || SUB_PREFIX="repo:${REPO}"
SUBJECT="${SUB_PREFIX}:ref:refs/heads/main"
echo "federated subject: $SUBJECT"
OLD_FC="$(az ad app federated-credential list --id "$APP_ID" --query "[?name=='gh-main'].id" -o tsv)"
[ -n "$OLD_FC" ] && az ad app federated-credential delete --id "$APP_ID" --federated-credential-id "$OLD_FC" -o none
az ad app federated-credential create --id "$APP_ID" --parameters "{
  \"name\": \"gh-main\",
  \"issuer\": \"https://token.actions.githubusercontent.com\",
  \"subject\": \"${SUBJECT}\",
  \"audiences\": [\"api://AzureADTokenExchange\"]
}" -o none

az role assignment create --assignee "$APP_ID" --role Contributor \
  --scope "/subscriptions/${SUB_ID}/resourceGroups/${RESOURCE_GROUP}" -o none 2>/dev/null \
  || echo "  (role assignment already exists)"

echo "setting repo secrets…"
gh secret set AZURE_CLIENT_ID       -R "$REPO" -b "$APP_ID"
gh secret set AZURE_TENANT_ID       -R "$REPO" -b "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID -R "$REPO" -b "$SUB_ID"
[ -n "${PG_ADMIN_PASSWORD:-}" ] && gh secret set PG_ADMIN_PASSWORD -R "$REPO" -b "$PG_ADMIN_PASSWORD"

for k in AUTH0_DOMAIN AUTH0_CLIENT_ID AUTH0_CLIENT_SECRET AUTH0_SECRET AUTH0_AUDIENCE; do
  v="$(grep -E "^${k}=" "$WEB_ENV" 2>/dev/null | head -1 | cut -d= -f2- || true)"
  if [ -n "$v" ]; then gh secret set "$k" -R "$REPO" -b "$v"; echo "  set $k"; fi
done

echo
echo "Done. From now on:"
echo "  - push touching backend/**  → 'Deploy backend' workflow"
echo "  - push touching web/** or design/**  → 'Deploy web' workflow"
echo "  - or run either from the Actions tab (workflow_dispatch)"
