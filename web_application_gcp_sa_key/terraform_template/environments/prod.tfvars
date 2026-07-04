app_name   = "your-app-name"
region      = "europe-west1"
environment = "prod"

backend_image  = "europe-west1-docker.pkg.dev/your-gcp-project-id/your-app-name/backend:latest"
frontend_image = "europe-west1-docker.pkg.dev/your-gcp-project-id/your-app-name/frontend:latest"

db_tier   = "db-custom-1-3840"
db_name   = "app"

jwt_secret = "CHANGE_ME"
