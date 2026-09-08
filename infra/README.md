# infra

Azure provisioning for AI Receipt, via the `az` CLI.

## What it creates

| Resource | SKU / notes | ~cost |
|----------|-------------|-------|
| Resource group | container for everything | free |
| Azure OpenAI account + deployment | `S0`, `gpt-5-mini` (`GlobalStandard`, 20K TPM) | pay per token |
| PostgreSQL Flexible Server + `ai_receipt` db | `Standard_B1ms` Burstable, 32 GB, PG 16 | ~$13–15/mo + storage |
| Storage account + `receipts` container | `Standard_LRS`, no public blobs | cents/mo + usage |
| Log Analytics workspace + Application Insights | workspace-based | pay per GB ingested (small) |

> Real, billable resources. Postgres Flexible Server is the main standing cost.
> Tear everything down with `./teardown.sh` when not in use.

## Usage

```bash
az login
az account set --subscription "<subscription-id>"

# optional: cp .env.infra.example .env.infra   and edit
./provision.sh
```

On success it prints the block to paste into `backend/.env`
(`DATABASE_URL`, `AZURE_OPENAI_*`, `AZURE_STORAGE_*`,
`APPLICATIONINSIGHTS_CONNECTION_STRING`) and the generated Postgres password.

Both scripts are **idempotent** — re-run `provision.sh` to converge / pick up new
settings.

## Deploy the apps

After `provision.sh`, build + ship both services to Azure Container Apps:

```bash
./deploy.sh                 # both;  TARGET=backend|web for one
```

Creates an ACR (`Basic`, ~$5/mo) + a Container Apps environment on the existing
Log Analytics workspace, `az acr build`s each image in the cloud, and
creates/updates:

| App | Port | Notes |
|-----|------|-------|
| `ai-receipt-dev-api` | 8000 | secrets pulled from Azure + `backend/.env`; `AUTO_CREATE_TABLES=true` |
| `ai-receipt-dev-web` | 3000 | `BACKEND_URL` = the API's FQDN |

Both: external HTTPS ingress, scale-to-zero, 0.5 vCPU / 1 GiB. Re-run any time
to roll a new image (`TAG` defaults to a timestamp).

Current URLs:
- Web — https://ai-receipt-dev-web.ashymoss-2c5773fb.eastus2.azurecontainerapps.io
- API — https://ai-receipt-dev-api.ashymoss-2c5773fb.eastus2.azurecontainerapps.io/docs

## Continuous deployment

`./setup-cd.sh` (one-time) wires GitHub Actions to Azure via OIDC: an Entra app +
federated credential for `main`, Contributor on the resource group, and the repo
secrets. After that, a push to `main` that touches `backend/**` runs **Deploy
backend** and one touching `web/**` or `design/**` runs **Deploy web** — each just
calls `deploy.sh` with the right `TARGET`. Both also have a manual `Run workflow`
button.

## Teardown

```bash
./teardown.sh          # deletes the whole resource group after confirmation
```

## Notes

- `provision.sh` opens the Postgres firewall to `0.0.0.0` ("allow Azure
  services"). For local development add your own IP:
  `az postgres flexible-server firewall-rule create -n <pg> -g <rg> --rule-name dev --start-ip-address <ip> --end-ip-address <ip>`.
  Lock this down before production.
- Azure OpenAI availability and model versions vary by region — if
  `provision.sh` fails on the deployment step, try `LOCATION=eastus2` /
  `swedencentral`, or adjust `OPENAI_MODEL_VERSION`.
- Deployment/hosting of the FastAPI app itself (Container Apps / App Service) is
  not scripted yet.
