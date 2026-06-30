# Web Application Template — GCP SA Key

Startup template for web applications deployed on **Google Cloud Run** with **PostgreSQL (Cloud SQL)**, **GCS storage**, and **GitHub Actions CI/CD** authenticated via a **GCP Service Account Key** (`GCP_SA_KEY`).

## Structure

```
web_application_gcp_sa_key/
├── terraform_template/          # GCP infrastructure
│   ├── main.tf                  # Resources: Cloud Run, Cloud SQL, GCS, Artifact Registry
│   ├── variables.tf             # All input variables
│   ├── outputs.tf               # Key outputs (URLs, SA email, registry path)
│   └── environments/
│       ├── dev.tfvars           # Dev environment values
│       └── prod.tfvars          # Prod environment values
└── workflows_template/          # GitHub Actions
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
| `project_id` | Your GCP project ID |
| `region` | GCP region (default `europe-west1`) |
| `backend_image` / `frontend_image` | Initial placeholder image references |
| `db_name` | PostgreSQL database name (default `app`) |
| `jwt_secret` | **Set via GitHub secret instead — do not commit real values** |

### 3. Bootstrap Terraform (first deploy only)

Run the initial `terraform init` locally or let the `deploy.yml` workflow handle it. The state bucket is created automatically on first run.

### 4. Create the service account key and add GitHub secrets

After the first `terraform apply`, create a key for the GitHub Actions service account:

```bash
SA_EMAIL=$(terraform output -raw github_actions_service_account)
gcloud iam service-accounts keys create sa-key.json --iam-account="$SA_EMAIL"
```

Then add the following under `Settings → Secrets and variables → Actions → Secrets`:

| Name | Description |
|---|---|
| `GCP_SA_KEY` | Contents of `sa-key.json` (the full JSON) |
| `JWT_SECRET` | JWT signing key for the backend |

Add any additional application secrets here and reference them in the `Terraform Apply` steps inside `deploy.yml` and `destroy.yml`.

### 5. Extend for your application

**Add backend environment variables** — edit `main.tf` inside the `google_cloud_run_v2_service.backend` container block (look for the comment `# Add application-specific environment variables below`).

**Add Terraform variables** — add new entries to `variables.tf` and the corresponding `-var=` flags in the workflow `Terraform Apply` steps.

**Add frontend build args** — extend the `build-args` block in the `build-frontend` job inside `deploy.yml`.

**Remove frontend or backend** — if your app is API-only or static-only, delete the unused Cloud Run service block from `main.tf` and remove the corresponding build/deploy jobs from `deploy.yml`.

## Workflow overview

| Workflow | Trigger | What it does |
|---|---|---|
| `deploy.yml` | Manual (env choice) | Provision infra → build images → run migrations → deploy Cloud Run |
| `destroy.yml` | Manual (env + confirm) | Destroy all infrastructure for a given environment |
| `db-reset.yml` | Manual (env + confirm) | Drop and recreate the database schema, optionally re-seed |
| `test-and-lint-backend.yml` | Push / PR to `backend/**` | Lint + test against a real Postgres service container |
| `test-and-lint-frontend.yml` | Push / PR to `frontend/**` | Lint + build |

## Infrastructure created

- **Artifact Registry** — Docker image storage
- **Cloud SQL (PostgreSQL 17)** — managed database
- **GCS bucket** — file/object storage
- **Secret Manager** — stores `db-password` and `db-url`
- **Cloud Run** — backend (port 3000) and frontend (port 8080), both public
- **IAM** — least-privilege service accounts for Cloud Run and GitHub Actions
