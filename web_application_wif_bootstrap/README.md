# Web Application Template — WIF + Bootstrap

Startup template for web applications deployed on **Google Cloud Run** with **PostgreSQL (Cloud SQL)**, **GCS storage**, and **GitHub Actions CI/CD** authenticated via **Workload Identity Federation** (keyless, no long-lived credentials).

Same as [`web_application_wif`](../web_application_wif/README.md), plus a `bootstrap.yml` workflow for first-time setup. It creates the state bucket, enables APIs, brings the WIF pool, provider and GitHub Actions service account under Terraform, grants the SA its roles and creates the Artifact Registry. After that, `deploy.yml` only deploys.

## Structure

```
web_application_wif_bootstrap/
├── terraform_template/          # GCP infrastructure
│   ├── main.tf                  # Resources: WIF, Cloud Run, Cloud SQL, GCS, Artifact Registry
│   ├── variables.tf             # All input variables
│   ├── outputs.tf               # Key outputs (URLs, WIF provider, registry path)
│   └── environments/
│       ├── dev.tfvars           # Dev environment values
│       └── prod.tfvars          # Prod environment values
└── workflows_template/          # GitHub Actions
    ├── bootstrap.yml            # First-time setup: state bucket → APIs → WIF + CI SA + roles → registry
    ├── deploy.yml               # Full deploy: provision → build → migrate → release
    ├── destroy.yml              # Tear down all infrastructure for an environment
    ├── db-reset.yml             # Reset and optionally re-seed the database
    ├── test-and-lint-backend.yml
    └── test-and-lint-frontend.yml
```

## How to use

### 1. Copy and rename

Copy both `terraform_template/` and `workflows_template/` into your new project:

```
your-project/
├── terraform/               ← from terraform_template/
│   └── environments/
│       ├── dev.tfvars
│       └── prod.tfvars
└── .github/
    └── workflows/           ← from workflows_template/
```

### 2. Fill in the tfvars

Edit `terraform/environments/dev.tfvars` (and `prod.tfvars`) replacing all placeholder values:

| Field | Description |
|---|---|
| `app_name` | Short name used for all resource names (e.g. `my-app`) |
| `region` | GCP region (default `europe-west1`) |
| `backend_image` / `frontend_image` | Initial placeholder image references |
| `db_name` | PostgreSQL database name (default `app`) |
| `jwt_secret` | **Set via GitHub secret instead — do not commit real values** |

`github_repository` (which scopes the WIF trust) is passed by the workflows from `github.repository`, so it is not in the tfvars. Pass it with `-var` if you run Terraform locally.

### 3. Create the WIF identity (once per GCP project)

The pipeline needs credentials before it can run anything. Create the WIF pool, provider and `github-actions` SA by hand, and give the SA just enough access to bootstrap. The `bootstrap.yml` run then imports them into Terraform and grants the rest of the SA's roles.

```bash
PROJECT_ID=your-gcp-project-id
GITHUB_REPO=your-org/your-repo
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
SA_EMAIL="github-actions@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  cloudresourcemanager.googleapis.com --project="$PROJECT_ID"

gcloud iam workload-identity-pools create github-actions \
  --location=global --display-name="GitHub Actions" --project="$PROJECT_ID"

gcloud iam workload-identity-pools providers create-oidc github-oidc \
  --location=global --workload-identity-pool=github-actions --display-name="GitHub OIDC" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.actor=assertion.actor" \
  --attribute-condition="assertion.repository_owner == '${GITHUB_REPO%%/*}' && attribute.repository == '${GITHUB_REPO}'" \
  --project="$PROJECT_ID"

gcloud iam service-accounts create github-actions \
  --display-name="GitHub Actions CI/CD" --project="$PROJECT_ID"

gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/attribute.repository/${GITHUB_REPO}" \
  --project="$PROJECT_ID"

for ROLE in roles/resourcemanager.projectIamAdmin roles/serviceusage.serviceUsageAdmin roles/storage.admin roles/iam.serviceAccountAdmin roles/iam.workloadIdentityPoolAdmin; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" --role="$ROLE" --condition=None
done

echo "WIF_PROVIDER=projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-actions/providers/github-oidc"
echo "WIF_SERVICE_ACCOUNT=${SA_EMAIL}"
```

Keep the IDs (`github-actions`, `github-oidc`) as they are — Terraform expects them.

### 4. Add GitHub variables and secrets

Add the following under `Settings → Secrets and variables → Actions → Variables`:

| Name | Value |
|---|---|
| `GCP_PROJECT_ID` | Your GCP project ID |
| `WIF_PROVIDER` | Printed at the end of step 3 (also `terraform output workload_identity_provider`) |
| `WIF_SERVICE_ACCOUNT` | Printed at the end of step 3 (also `terraform output github_actions_service_account`) |

Then add the following under `Settings → Secrets and variables → Actions → Secrets`:

| Name | Description |
|---|---|
| `JWT_SECRET` | JWT signing key for the backend |

Add any additional application secrets here and reference them in the `Terraform Apply` steps inside `deploy.yml` and `destroy.yml`.

### 5. Run the Bootstrap workflow

Run `bootstrap.yml` once for each environment (`dev`, `prod`). It is safe to re-run. Then run `deploy.yml`.

`destroy.yml` leaves the WIF pool, provider and GitHub Actions SA in place, since every environment authenticates through them. Run `bootstrap.yml` again after a destroy, before the next deploy.

### 6. Extend for your application

**Add backend environment variables** — edit `main.tf` inside the `google_cloud_run_v2_service.backend` container block (look for the comment `# Add application-specific environment variables below`).

**Add Terraform variables** — add new entries to `variables.tf` and the corresponding `-var=` flags in the workflow `Terraform Apply` steps.

**Add frontend build args** — extend the `build-args` block in the `build-frontend` job inside `deploy.yml`.

**Remove frontend or backend** — if your app is API-only or static-only, delete the unused Cloud Run service block from `main.tf` and remove the corresponding build/deploy jobs from `deploy.yml`.

## Workflow overview

| Workflow | Trigger | What it does |
|---|---|---|
| `bootstrap.yml` | Manual (env choice) | First-time setup: state bucket, APIs, WIF + CI SA roles, Artifact Registry |
| `deploy.yml` | Manual (env choice) | Provision infra → build images → run migrations → deploy Cloud Run |
| `destroy.yml` | Manual (env + confirm) | Destroy all infrastructure for a given environment (keeps the CI identity) |
| `db-reset.yml` | Manual (env + confirm) | Drop and recreate the database schema, optionally re-seed |
| `test-and-lint-backend.yml` | Push / PR to `backend/**` | Lint + test against a real Postgres service container |
| `test-and-lint-frontend.yml` | Push / PR to `frontend/**` | Lint + build |

## Infrastructure created

- **Workload Identity Federation** — keyless GCP auth for GitHub Actions (no stored credentials)
- **Artifact Registry** — Docker image storage
- **Cloud SQL (PostgreSQL 17)** — managed database
- **GCS bucket** — file/object storage
- **Secret Manager** — stores `db-password` and `db-url`
- **Cloud Run** — backend (port 3000) and frontend (port 8080), both public
- **IAM** — least-privilege service accounts for Cloud Run and GitHub Actions
