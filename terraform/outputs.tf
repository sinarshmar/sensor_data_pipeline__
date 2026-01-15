# =============================================================================
# TERRAFORM OUTPUTS
# =============================================================================
# Values displayed after terraform apply.
# Useful for connecting services and debugging.
# =============================================================================


# =============================================================================
# DATABASE OUTPUTS
# =============================================================================

output "database_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.main.name
}

output "database_public_ip" {
  description = "Cloud SQL public IP address"
  value       = google_sql_database_instance.main.public_ip_address
}

output "database_connection_name" {
  description = "Cloud SQL connection name (for Cloud Run)"
  value       = google_sql_database_instance.main.connection_name
}


# =============================================================================
# API OUTPUTS
# =============================================================================

output "api_url" {
  description = "Cloud Run service URL"
  value       = google_cloud_run_service.api.status[0].url
}

output "api_service_name" {
  description = "Cloud Run service name"
  value       = google_cloud_run_service.api.name
}


# =============================================================================
# CONNECTION STRINGS
# =============================================================================

output "connection_string" {
  description = "PostgreSQL connection string (password redacted)"
  value       = "postgresql://postgres:****@${google_sql_database_instance.main.public_ip_address}:5432/sensor_data"
}


# =============================================================================
# USEFUL COMMANDS
# =============================================================================

output "next_steps" {
  description = "Commands to run after deployment"
  value       = <<-EOT
    
    # Connect to database:
    psql -h ${google_sql_database_instance.main.public_ip_address} -U postgres -d sensor_data
    
    # Run init script:
    psql -h ${google_sql_database_instance.main.public_ip_address} -U postgres -d sensor_data -f scripts/init_db.sql
    
    # Test API:
    curl ${google_cloud_run_service.api.status[0].url}/health
    
  EOT
}