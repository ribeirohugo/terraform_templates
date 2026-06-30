output "github_actions_service_account" {
  description = "GitHub Actions service account email — create and download a key for this SA to use as GCP_SA_KEY"
  value       = google_service_account.github_actions.email
}

output "backend_url" {
  description = "Cloud Run backend service URL"
  value       = google_cloud_run_v2_service.backend.uri
}

output "frontend_url" {
  description = "Cloud Run frontend service URL"
  value       = google_cloud_run_v2_service.frontend.uri
}

output "db_connection_name" {
  description = "Cloud SQL instance connection name (PROJECT:REGION:INSTANCE)"
  value       = google_sql_database_instance.main.connection_name
}

output "artifact_registry" {
  description = "Artifact Registry repository path (use as image prefix)"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.main.repository_id}"
}
