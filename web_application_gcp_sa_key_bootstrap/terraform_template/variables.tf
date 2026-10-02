variable "app_name" {
  description = "Application name used to name all resources (e.g. my-app)"
  type        = string
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region (e.g. europe-west1)"
  type        = string
  default     = "europe-west1"
}

variable "environment" {
  description = "Environment label (dev | prod)"
  type        = string
  default     = "dev"
}

variable "backend_image" {
  description = "Fully-qualified backend container image reference (registry/repo/image:tag)"
  type        = string
}

variable "frontend_image" {
  description = "Fully-qualified frontend container image reference (registry/repo/image:tag)"
  type        = string
}

variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-f1-micro"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "app"
}

variable "jwt_secret" {
  description = "JWT signing secret for the backend"
  type        = string
  sensitive   = true
}
