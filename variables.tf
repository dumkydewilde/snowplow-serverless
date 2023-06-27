variable "prefix" {
  description = "Will be prefixed to all resource names. Use to easily identify the resources created"
  type        = string
}

variable "project_id" {
  description = "The project ID in which the stack is being deployed"
  type        = string
}

variable "region" {
  description = "The name of the region to deploy within"
  type        = string
}

variable "bigquery_loader_dead_letter_bucket_deploy" {
  description = "Whether this module should create a new bucket with the specified name - if the bucket already exists set this to false"
  default     = true
  type        = bool
}

variable "bigquery_loader_dead_letter_bucket_name" {
  description = "The name of the GCS bucket to use for dead-letter output of loader"
  default     = ""
  type        = string
}

variable "vendor" {
  description = "An unique identifier like 'com.snowplow.analytics for the vendor of this stack."
  type        = string
}

variable "labels" {
  description = "The labels to append to the resources in this module"
  default     = {}
  type        = map(string)
}

variable "dbt_snowplow__start_date" {
  description = "The labels to append to the resources in this module"
  default     = "2023-06-01"
  type        = string
}