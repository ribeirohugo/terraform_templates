terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "gcs" {
    # Supplied at init time:
    #   terraform init -backend-config="bucket=<bucket>" -backend-config="prefix=<app-name>/<env>"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "secretmanager.googleapis.com",
  ])

  service            = each.key
  disable_on_destroy = false
}

# GitHub Actions Workload Identity Federation
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.actor"            = "assertion.actor"
  }

  attribute_condition = "assertion.repository_owner == '${split("/", var.github_repository)[0]}' && attribute.repository == '${var.github_repository}'"
}

resource "google_service_account" "github_actions" {
  account_id   = "github-actions"
  display_name = "GitHub Actions CI/CD"
}

resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

resource "google_project_iam_member" "github_actions" {
  for_each = toset([
    "roles/artifactregistry.admin",
    "roles/run.admin",
    "roles/cloudsql.admin",
    "roles/storage.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/resourcemanager.projectIamAdmin",
    "roles/serviceusage.serviceUsageAdmin",
  ])

  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Artifact Registry
resource "google_artifact_registry_repository" "main" {
  repository_id = var.app_name
  format        = "DOCKER"
  location      = var.region
  description   = "Docker images for ${var.app_name} (${var.environment})"

  depends_on = [google_project_service.apis]
}

# Database
resource "random_id" "db_suffix" {
  byte_length = 4
}

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}?"
}

resource "google_sql_database_instance" "main" {
  name             = "${var.app_name}-${var.environment}-${random_id.db_suffix.hex}"
  database_version = "POSTGRES_17"
  region           = var.region

  deletion_protection = false

  settings {
    tier    = var.db_tier
    edition = "ENTERPRISE"

    backup_configuration {
      enabled = var.environment == "prod"
    }

    ip_configuration {
      ipv4_enabled = true
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "main" {
  name     = var.db_name
  instance = google_sql_database_instance.main.name

  depends_on = [google_sql_user.app]
}

resource "google_sql_user" "app" {
  name     = "app"
  instance = google_sql_database_instance.main.name
  password = random_password.db.result
}

# Storage
resource "google_storage_bucket" "app" {
  name                        = "${var.project_id}-${var.app_name}-${var.environment}"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  depends_on = [google_project_service.apis]
}

# IAM
resource "google_service_account" "cloud_run" {
  account_id   = "${var.app_name}-${var.environment}"
  display_name = "${var.app_name} Cloud Run (${var.environment})"
}

resource "google_project_iam_member" "cloud_run_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_storage_bucket_iam_member" "cloud_run_storage" {
  bucket = google_storage_bucket.app.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${google_service_account.cloud_run.email}"
}

# Secrets
locals {
  db_name_safe = replace(var.db_name, "-", "_")
  db_url        = "postgresql://app:${urlencode(random_password.db.result)}@/${local.db_name_safe}?host=/cloudsql/${google_sql_database_instance.main.connection_name}&schema=public"
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "db-password-${var.environment}"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}

resource "google_secret_manager_secret" "db_url" {
  secret_id = "db-url-${var.environment}"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_url" {
  secret      = google_secret_manager_secret.db_url.id
  secret_data = local.db_url
}

resource "google_secret_manager_secret_iam_member" "cloud_run_db_url" {
  secret_id = google_secret_manager_secret.db_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_secret_manager_secret_iam_member" "github_actions_db_password" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.github_actions.email}"
}

# Cloud Run — Backend
resource "google_cloud_run_v2_service" "backend" {
  name                = "${var.app_name}-backend-${var.environment}"
  location            = var.region
  deletion_protection = false

  template {
    service_account = google_service_account.cloud_run.email

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      image = var.backend_image

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_url.secret_id
            version = "latest"
          }
        }
      }

      env {
        name  = "JWT_SECRET"
        value = var.jwt_secret
      }

      env {
        name  = "JWT_EXPIRES_IN"
        value = "7d"
      }

      # Add application-specific environment variables below.

      ports {
        container_port = 3000
      }

      startup_probe {
        tcp_socket {
          port = 3000
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 60
        timeout_seconds       = 3
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_sql_database.main,
    google_sql_user.app,
    google_project_iam_member.cloud_run_sql_client,
    google_secret_manager_secret_iam_member.cloud_run_db_url,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "backend_public" {
  project  = google_cloud_run_v2_service.backend.project
  location = google_cloud_run_v2_service.backend.location
  name     = google_cloud_run_v2_service.backend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Run — Frontend
resource "google_cloud_run_v2_service" "frontend" {
  name                = "${var.app_name}-frontend-${var.environment}"
  location            = var.region
  deletion_protection = false

  template {
    service_account = google_service_account.cloud_run.email

    containers {
      image = var.frontend_image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  project  = google_cloud_run_v2_service.frontend.project
  location = google_cloud_run_v2_service.frontend.location
  name     = google_cloud_run_v2_service.frontend.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
