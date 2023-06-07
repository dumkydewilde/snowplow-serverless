output "bigquery_db_dataset_id" {
  description = "The ID of the BigQuery dataset where your data is being streamed"
  value       = join("", google_bigquery_dataset.bigquery_db.*.dataset_id)
}

output "bq_loader_dead_letter_bucket_name" {
  description = "The name of the GCS bucket for dead letter events emitted from the BigQuery loader"
  value       = join("", google_storage_bucket.bq_loader_dead_letter_bucket.*.name)
}

output "collector_server_url" {
  description = "The URL of the collector server"
  value       = google_cloud_run_v2_service.collector_server.uri
}