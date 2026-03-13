variable "project_id" {
  description = "GCP project id"
  type        = string
}

variable "region" {
  description = "GCP region (e.g. asia-northeast1)"
  type        = string
}

variable "job_name" {
  description = "Cloud Run Job name"
  type        = string
  default     = "dbt-core"
}

variable "container_image" {
  description = "Container image URI for running dbt core"
  type        = string
}

variable "container_command" {
  description = "Override container command (optional)"
  type        = list(string)
  default     = []
}

variable "container_args" {
  description = "Container args (e.g. [\"dbt\", \"build\"])"
  type        = list(string)
  default     = ["dbt", "build"]
}

variable "schedule" {
  description = "Cron schedule for Cloud Scheduler"
  type        = string
  default     = "0 2 * * *"
}

variable "time_zone" {
  description = "Time zone for Cloud Scheduler"
  type        = string
  default     = "Asia/Tokyo"
}

variable "timeout_seconds" {
  description = "Cloud Run Job timeout seconds"
  type        = number
  default     = 3600
}

variable "max_retries" {
  description = "Cloud Run Job max retries"
  type        = number
  default     = 1
}

variable "bigquery_project_roles" {
  description = "Project-level roles for the dbt runtime service account. Prefer dataset-level IAM in production."
  type        = list(string)
  default = [
    "roles/bigquery.jobUser",
    "roles/bigquery.dataViewer"
  ]
}

variable "enable_apis" {
  description = "Enable required APIs (run, cloudscheduler)."
  type        = bool
  default     = true
}

variable "create_profiles_secret" {
  description = "If true, create a Secret Manager secret placeholder for dbt profiles (value is NOT managed by Terraform)."
  type        = bool
  default     = false
}

variable "profiles_secret_id" {
  description = "Secret id to create when create_profiles_secret is true."
  type        = string
  default     = "dbt-profiles-yml"
}
