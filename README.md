# Terraform Templates

A collection of ready-to-use Terraform templates for common infrastructure setups.
The goal is to avoid starting from scratch on every project:
 copy a template, fill in your values, and have a working, production-grade infrastructure in minutes.

## Templates

### `terraform_template` — GCP Web App

Provisions the full infrastructure for a containerised web application on Google Cloud Platform.

**What it creates:**

| Resource | Details |
|---|---|
| Cloud Run (backend) | Publicly accessible, connected to Cloud SQL via Unix socket |
| Cloud Run (frontend) | Static site served by nginx |
| Cloud SQL (PostgreSQL 17) | Auto-generates DB, user, and password |
| Artifact Registry | Docker registry for your images |
| GCS Bucket | File storage with configurable retention |
| Secret Manager | Stores DB URL, DB password, and session secret |
| Service Account | Scoped IAM identity for Cloud Run with least-privilege roles |
| GCS Backend | Remote state in a GCS bucket |

**Required variables:**

| Variable | Description |
|---|---|
| `app_name` | App name used as a prefix for all resources (keep ≤ 20 chars) |
| `project_id` | GCP project ID |
| `backend_image` | Fully-qualified backend container image |
| `frontend_image` | Fully-qualified frontend container image |
| `session_secret` | Secret used to sign session cookies |

See `variables.tf` for the full list and defaults.

**Outputs:** `backend_url`, `frontend_url`, `artifact_registry`, `files_bucket`, `db_connection_name`, `cloud_run_service_account`.

---

### [`web_application`](web_application/README.md) — GCP Web App + CI/CD

Same GCP infrastructure as above plus GitHub Actions workflows for CI, deployment, and database management.

Each template folder has its own `README.md` with setup instructions and a `PROMPTS.md` with ready-to-paste prompts for common extensions.
