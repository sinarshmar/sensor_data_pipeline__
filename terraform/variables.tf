# =============================================================================
# TERRAFORM VARIABLES
# =============================================================================
# Input variables for GCP infrastructure.
# 
# Usage:
#   terraform apply -var="project_id=my-project" -var="db_password=secret"
#
# Or create terraform.tfvars:
#   project_id  = "my-project"
#   db_password = "secret"
# =============================================================================


# =============================================================================
# PROJECT CONFIGURATION
# =============================================================================

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  # No default - must be provided
}

variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "sensor_data"
}

variable "region" {
  description = "GCP region for resources"
  type        = string
  default     = "europe-west2" # London
}


# =============================================================================
# DATABASE CONFIGURATION
# =============================================================================

variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-f1-micro" # Smallest, cheapest (~$7/month)

  validation {
    condition     = can(regex("^db-", var.db_tier))
    error_message = "Database tier must start with 'db-'."
  }
}

variable "db_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true # Won't show in logs
  # No default - must be provided
}


# =============================================================================
# API CONFIGURATION
# =============================================================================

variable "api_image" {
  description = "Docker image for Flask API (gcr.io/PROJECT/IMAGE:TAG)"
  type        = string
  default     = "gcr.io/PROJECT_ID/sensor_data-api:latest" # Placeholder
}