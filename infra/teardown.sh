#!/usr/bin/env bash
# Delete the entire resource group created by provision.sh. Destructive.
#
#   ./infra/teardown.sh            # prompts for confirmation
#   NAME_PREFIX=foo ./infra/teardown.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$HERE/.env.infra" ] && { set -a; . "$HERE/.env.infra"; set +a; }

NAME_PREFIX="${NAME_PREFIX:-airreceipt}"
RESOURCE_GROUP="${RESOURCE_GROUP:-${NAME_PREFIX}-rg}"

echo "This will DELETE resource group: $RESOURCE_GROUP and everything in it."
read -r -p "Type the resource group name to confirm: " confirm
[ "$confirm" = "$RESOURCE_GROUP" ] || { echo "Aborted."; exit 1; }

az group delete -n "$RESOURCE_GROUP" --yes --no-wait
echo "Deletion started (running in the background)."
