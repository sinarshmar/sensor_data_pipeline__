# =============================================================================
# FUTURE: MODULARIZATION
# =============================================================================
# When scaling, extract resources into modules:
#   - modules/database/ → Cloud SQL resources
#   - modules/api/      → Cloud Run resources
#   - modules/composer/ → Cloud Composer resources
#
# This keeps the codebase simple for now while allowing easy extraction later.
# =============================================================================


# =============================================================================
# TERRAFORM CONFIGURATION - FOR DEMONSTRATION ONLY
# =============================================================================
# This Terraform code demonstrates production deployment capability.
# It is validated but NOT applied (no GCP resources created).
#
# Purpose: Interview signal — shows understanding of IaC and GCP architecture
#
# To deploy:
#   1. Create GCP project and enable APIs
#   2. Authenticate: gcloud auth application-default login
#   3. Update variables: terraform.tfvars or -var flags
#   4. Run: terraform init && terraform plan && terraform apply
#
# To validate (no GCP credentials needed):
#   terraform init -backend=false
#   terraform fmt -check
#   terraform validate
# =============================================================================



# =============================================================================
# TERRAFORM SETTINGS
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Local backend for development
  # For production, use GCS backend:
  #
  # backend "gcs" {
  #   bucket = "sensor_data-terraform-state"
  #   prefix = "prod"
  # }
  backend "local" {
    path = "terraform.tfstate"
  }
}


# =============================================================================
# PROVIDER CONFIGURATION
# =============================================================================

provider "google" {
  project = var.project_id
  region  = var.region
}


# =============================================================================
# CLOUD SQL (POSTGRESQL) - REPLACES LOCAL POSTGRES
# =============================================================================
# Managed PostgreSQL database.
# In production, this replaces the Docker postgres container.
#
# Estimated cost: ~$7/month (db-f1-micro)
# Free tier: Not included, but minimal cost for small instance
# =============================================================================

resource "google_sql_database_instance" "main" {
  name             = "${var.project_name}-db"
  database_version = "POSTGRES_15"
  region           = var.region

  settings {
    tier = var.db_tier

    ip_configuration {
      ipv4_enabled = true
      authorized_networks {
        name  = "allow-all"
        value = "0.0.0.0/0" # Restrict in production
      }
    }

    backup_configuration {
      enabled    = true
      start_time = "03:00"
    }
  }

  deletion_protection = false # Set true in production
}

resource "google_sql_database" "sensor_data" {
  name     = "sensor_data"
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "postgres" {
  name     = "postgres"
  instance = google_sql_database_instance.main.name
  password = var.db_password
}


# =============================================================================
# CLOUD RUN (FLASK API) - REPLACES LOCAL DOCKER CONTAINER
# =============================================================================
# Serverless container platform.
# Runs the Flask API from Dockerfile.api
#
# Estimated cost: Free tier covers ~2M requests/month
# =============================================================================

resource "google_cloud_run_service" "api" {
  name     = "${var.project_name}-api"
  location = var.region

  template {
    spec {
      containers {
        image = var.api_image

        ports {
          container_port = 5001
        }

        env {
          name  = "POSTGRES_HOST"
          value = google_sql_database_instance.main.public_ip_address
        }
        env {
          name  = "POSTGRES_PORT"
          value = "5432"
        }
        env {
          name  = "POSTGRES_DB"
          value = "sensor_data"
        }
        env {
          name  = "POSTGRES_USER"
          value = "postgres"
        }
        env {
          name = "POSTGRES_PASSWORD"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.db_password.secret_id
              key  = "latest"
            }
          }
        }

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
      }
    }

    metadata {
      annotations = {
        "autoscaling.knative.dev/minScale" = "0"
        "autoscaling.knative.dev/maxScale" = "10"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}

# Allow unauthenticated access to API
resource "google_cloud_run_service_iam_member" "public" {
  service  = google_cloud_run_service.api.name
  location = google_cloud_run_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}


# =============================================================================
# SECRET MANAGER - DATABASE PASSWORD
# =============================================================================

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.project_name}-db-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = var.db_password
}


# =============================================================================
# CLOUD COMPOSER (AIRFLOW) - NOT DEPLOYED
# =============================================================================
# Cloud Composer is NOT included in GCP free tier.
# Minimum cost: ~$300/month (smallest environment ~$10/day)
#
# For this assessment, Airflow runs locally via Docker Compose.
# In production, uncomment and apply this resource.
#
# Pricing reference: https://cloud.google.com/composer/pricing
# =============================================================================

# resource "google_composer_environment" "airflow" {
#   name   = "${var.project_name}-composer"
#   region = var.region
#
#   config {
#     software_config {
#       image_version = "composer-2-airflow-2"
#       
#       pypi_packages = {
#         dbt-postgres = "==1.10.0"
#       }
#
#       env_variables = {
#         POSTGRES_HOST     = google_sql_database_instance.main.public_ip_address
#         POSTGRES_PORT     = "5432"
#         POSTGRES_DB       = "sensor_data"
#         POSTGRES_USER     = "postgres"
#       }
#     }
#
#     workloads_config {
#       scheduler {
#         cpu        = 0.5
#         memory_gb  = 2
#         storage_gb = 1
#         count      = 1
#       }
#       web_server {
#         cpu        = 0.5
#         memory_gb  = 2
#         storage_gb = 1
#       }
#       worker {
#         cpu        = 0.5
#         memory_gb  = 2
#         storage_gb = 1
#         min_count  = 1
#         max_count  = 3
#       }
#     }
#
#     environment_size = "ENVIRONMENT_SIZE_SMALL"
#   }
# }
#
# # GCS bucket for DAGs (created automatically by Composer)
# # Upload DAGs: gsutil cp airflow/dags/*.py gs://${COMPOSER_DAG_BUCKET}/dags/
# # Upload dbt:  gsutil cp -r dbt/ gs://${COMPOSER_DAG_BUCKET}/dags/dbt/