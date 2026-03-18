# Deploy-AKS-Terraform

Deploy and manage multi-environment AKS clusters on Azure with Terraform, including disaster recovery failover, Azure Front Door with WAF, Helm-based ingress, and CI/CD with pre-flight infrastructure validation.

## Architecture

```
                        ┌──────────────────────────┐
                        │     Azure Front Door      │
                        │  (Premium + WAF + Cache)  │
                        └────────────┬─────────────┘
                                     │
                      ┌──────────────┴──────────────┐
                      │                             │
             Priority 1 (active)          Priority 2 (standby)
                      │                             │
            ┌─────────▼─────────┐        ┌──────────▼────────┐
            │  AKS Primary      │        │  AKS DR            │
            │  (westus)         │        │  (eastus)          │
            │  NGINX Ingress    │        │  NGINX Ingress     │
            │  10.11.0.0/16     │        │  10.12.0.0/16      │
            └─────────┬─────────┘        └──────────┬─────────┘
                      │                             │
            ┌─────────▼─────────┐        ┌──────────▼────────┐
            │  Azure Container  │◄───────│  ACR Pull Role     │
            │  Registry (ACR)   │        │  Assignment        │
            └───────────────────┘        └────────────────────┘
```

## Features

### Multi-Environment Support

Three environments with independent configurations, each deployable to separate Azure subscriptions:

| Environment | File | Description |
|-------------|------|-------------|
| `lab` | `terraform/env/lab.tfvars` | Lab/sandbox, fixed node count, DR disabled |
| `dev` | `terraform/env/dev.tfvars` | Development, autoscaling 2-5 nodes, DR disabled |
| `uac` | `terraform/env/uac.tfvars` | User acceptance, autoscaling 3-10 nodes, DR enabled |

Add new environments by creating a new `terraform/env/<name>.tfvars` file and a corresponding GitHub Environment.

### AKS Clusters

- Primary AKS cluster with configurable node pools, VM sizes, and Kubernetes version
- Optional DR/failover AKS cluster in a separate region (controlled by `enable_dr`)
- System-assigned managed identity
- Azure CNI networking with dedicated VNets per cluster
- Optional autoscaling with configurable min/max node counts

### Azure Front Door (Premium)

Deployed when `enable_dr = true`. Provides global load balancing and failover:

- **Priority-based routing** -- primary cluster (priority 1) with automatic failover to DR (priority 2)
- **Health probes** -- HTTPS HEAD requests to `/healthz` every 30 seconds
- **Traffic recovery** -- auto-restores to primary 5 minutes after it becomes healthy
- **Caching** -- query string ignored, compression enabled for HTML, CSS, JS, JSON, XML, SVG, fonts
- **HTTPS enforcement** -- HTTP-to-HTTPS redirect on all routes

### WAF (Web Application Firewall)

- **OWASP 2.1** managed rule set (block mode)
- **Bot Manager 1.1** managed rule set
- **Rate limiting** -- 1000 requests per minute per IP
- **Geo-blocking** -- blocks all traffic from outside the US
- **Scanner blocking** -- blocks requests from known scanning tools (sqlmap, nikto, etc.)
- **Custom block response** -- returns 403 with a message body

### Security Headers

Injected via Front Door rule set on all responses:

- `Strict-Transport-Security` (HSTS with preload)
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: SAMEORIGIN`
- `X-XSS-Protection: 1; mode=block`
- `Referrer-Policy: strict-origin-when-cross-origin`

### Helm Deployments

NGINX Ingress Controller deployed to both primary and DR clusters:

- 2 replicas per cluster
- Azure LoadBalancer service type with health probe annotations
- Metrics enabled
- Configurable chart version via `helm_nginx_ingress_version`

### Azure Container Registry

- Shared ACR with AcrPull role assignments for both primary and DR clusters
- Configurable SKU (Standard/Premium)
- Optional geo-replication

## CI/CD Workflows

### PR Validation (`terraform-validate.yml`)

Triggered on pull requests that modify `terraform/**`:

```
PR opened ──► detect-changes ──► validate (per env, parallel)
                                    ├── terraform fmt -check
                                    ├── terraform init
                                    ├── terraform validate
                                    ├── terraform plan
                                    ├── tfsec security scan
                                    ├── Infracost cost estimate
                                    ├── pre-flight quota check
                                    └── PR comment with results
```

**Change detection** automatically determines which environments are affected:
- If shared Terraform files change (anything outside `terraform/env/`), all environments are validated
- If only a specific `env/*.tfvars` changes, only that environment is validated

**Security scanning (tfsec)** runs against the Terraform code with environment-specific variables:
- Detects security misconfigurations (public endpoints, missing encryption, permissive network rules, etc.)
- Results categorized by severity (critical, high, medium, low)
- Fails the PR if any critical or high severity findings are detected
- Each finding links to the relevant file/line and remediation documentation

**Cost estimation (Infracost)** analyzes the plan JSON to estimate cost impact:
- Shows previous, new, and differential monthly cost
- Detailed per-resource cost breakdown
- Cost increase warning surfaced in the PR comment
- Requires an `INFRACOST_API_KEY` secret (free tier available at [infracost.io](https://www.infracost.io))

**Pre-flight quota validation** (`scripts/preflight-quota-check.sh`) runs before any infrastructure is provisioned:
- Parses the `terraform show -json` plan output to extract planned resources
- Calculates total vCPU requirements (including autoscaling max and DR nodes)
- Queries Azure compute quotas (`az vm list-usage`) in both primary and DR regions
- Queries Azure network quotas (VNets, public IPs, load balancers, NSGs)
- Verifies required resource providers are registered
- Checks VM SKU availability and region restrictions
- Fails the PR check if any quota would be exceeded

**PR comment** is posted/updated per environment with:
- Step-by-step status table (fmt, init, validate, plan, tfsec, Infracost, quota check)
- Resource change summary (add/change/destroy counts) with estimated monthly cost
- Destroy warning if resources will be removed
- Security findings warning if critical/high issues found
- Cost increase warning if monthly spend goes up
- Collapsible sections for plan output, security report, cost breakdown, and quota report

### Deploy (`terraform-deploy.yml`)

Triggered on merge to `main` for changed `terraform/**` files:

```
Merge to main ──► detect-changes ──► deploy (per env, sequential)
                                        ├── terraform plan
                                        └── terraform apply
                                                │
                                     smoke-test (per env, parallel)
                                        ├── AKS cluster health check
                                        ├── Node pool validation
                                        ├── DR cluster health check
                                        └── k6 smoke test
```

- Deploys sequentially (`max-parallel: 1`) to avoid resource contention
- Uses **GitHub Environments** for approval gates and per-environment secrets
- Post-deploy smoke test validates cluster health and runs k6 load test

### k6 Smoke Test (`loadtest/k6-infra-test.js`)

Post-deploy infrastructure validation:
- Staged ramp-up: 10 → 50 → 100 → 200 virtual users over 5 minutes
- Tests `/healthz` and `/` endpoints
- Pass criteria: p95 latency < 2s, error rate < 5%
- Results uploaded as workflow artifacts (retained 30 days)

## Project Structure

```
.
├── .github/workflows/
│   ├── terraform-validate.yml     # PR validation workflow
│   └── terraform-deploy.yml       # Deploy + smoke test workflow
├── loadtest/
│   └── k6-infra-test.js           # k6 infrastructure smoke test
├── scripts/
│   └── preflight-quota-check.sh   # Pre-flight Azure quota validation
├── terraform/
│   ├── env/
│   │   ├── lab.tfvars              # Lab environment config
│   │   ├── dev.tfvars              # Dev environment config
│   │   └── uac.tfvars              # UAC environment config
│   ├── backend.tf                  # Azure backend (configured at init)
│   ├── container_registry.tf       # ACR + role assignments
│   ├── frontdoor.tf                # Front Door, WAF, security headers
│   ├── helm.tf                     # NGINX ingress Helm releases
│   ├── kubernetes.tf               # Primary + DR AKS clusters
│   ├── networking.tf               # Primary + DR VNets and subnets
│   ├── outputs.tf                  # Cluster, Front Door, ACR outputs
│   ├── provider.tf                 # Azure, Kubernetes, Helm providers
│   ├── resource_groups.tf          # Resource groups (primary, DR, Front Door)
│   └── variables.tf                # All input variables
└── README.md
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- An Azure subscription (one per environment, or shared)
- An Azure Storage Account for Terraform state (per environment or shared)

## GitHub Environment Setup

Create a GitHub Environment for each deployment target (`lab`, `dev`, `uac`) with these secrets:

| Secret | Description |
|--------|-------------|
| `ARM_CLIENT_ID` | Azure service principal client ID |
| `ARM_CLIENT_SECRET` | Azure service principal secret |
| `ARM_SUBSCRIPTION_ID` | Target Azure subscription for deployment |
| `ARM_TENANT_ID` | Azure AD tenant ID |
| `TF_STATE_STORAGE_ACCOUNT` | Storage account name for Terraform state |
| `TF_STATE_CONTAINER` | Blob container name for state files |
| `TF_STATE_RG` | Resource group containing the state storage account |
| `TF_STATE_SUBSCRIPTION_ID` | Subscription where state storage lives |
| `PAT` | GitHub Personal Access Token |
| `INFRACOST_API_KEY` | Infracost API key for cost estimation ([free signup](https://www.infracost.io)) |

Each environment can point to a different Azure subscription. State storage can be centralized or per-environment.

## Usage

### Local Development

```bash
cd terraform

# Initialize with environment-specific backend
terraform init \
  -backend-config="key=lab.tfstate" \
  -backend-config="storage_account_name=<account>" \
  -backend-config="container_name=<container>" \
  -backend-config="resource_group_name=<rg>" \
  -backend-config="subscription_id=<sub-id>"

# Plan
terraform plan -var-file="env/lab.tfvars"

# Apply
terraform apply -var-file="env/lab.tfvars"
```

### Enable Disaster Recovery

Set `enable_dr = true` in the environment's tfvars file. This provisions:
- DR AKS cluster in the configured `dr_location`
- DR VNet with separate address space
- Azure Front Door with priority-based failover routing
- WAF policy with geo-blocking and managed rule sets
- ACR pull role assignment for the DR cluster

### Add a New Environment

1. Create `terraform/env/<name>.tfvars` with environment-specific values
2. Create a GitHub Environment named `<name>` with the required secrets
3. Optionally configure approval rules on the GitHub Environment
4. Push changes -- the workflows automatically detect and include the new environment

## License

MIT
