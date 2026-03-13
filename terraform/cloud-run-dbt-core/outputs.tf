output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "cloud_run_job_name" {
  value = google_cloud_run_v2_job.dbt.name
}

output "dbt_runtime_service_account" {
  value = google_service_account.dbt_runtime.email
}

output "scheduler_invoker_service_account" {
  value = google_service_account.scheduler_invoker.email
}

output "cloud_scheduler_job_name" {
  value = google_cloud_scheduler_job.run_dbt.name
}
