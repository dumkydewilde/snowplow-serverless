output "collector_ip_address" {
  description = "The IP address for the Pipeline Collector"
  value       = module.collector_lb.ip_address
}

output "postgres_db_ip_address" {
  description = "The IP address of the database where your data is being streamed"
  value       = join("", module.postgres_db.*.first_ip_address)
}

output "postgres_db_port" {
  description = "The port of the database where your data is being streamed"
  value       = join("", module.postgres_db.*.port)
}

output "bigquery_db_dataset_id" {
  description = "The ID of the BigQuery dataset where your data is being streamed"
  value       = join("", google_bigquery_dataset.bigquery_db.*.dataset_id)
}

output "bq_loader_dead_letter_bucket_name" {
  description = "The name of the GCS bucket for dead letter events emitted from the BigQuery loader"
  value       = join("", google_storage_bucket.bq_loader_dead_letter_bucket.*.name)
}

output "bq_loader_bad_rows_topic_name" {
  description = "The name of the topic for bad rows emitted from the BigQuery loader"
  value       = join("", module.bad_rows_topic.*.name)
}