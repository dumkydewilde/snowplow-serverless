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

variable "network" {
  description = "The name of the network to deploy within"
  type        = string
}

variable "subnetwork" {
  description = "The name of the sub-network to deploy within"
  type        = string
}

variable "ssh_key_pairs" {
  description = "The list of SSH key-pairs to add to the servers"
  default     = []
  type = list(object({
    user_name  = string
    public_key = string
  }))
}

variable "ssh_ip_allowlist" {
  description = "The list of CIDR ranges to allow SSH traffic from"
  type        = list(any)
}

variable "iglu_server_dns_name" {
  description = "The DNS name of your Iglu Server"
  type        = string
}

variable "iglu_super_api_key" {
  description = "A UUIDv4 string to use as the master API key for Iglu Server management"
  type        = string
  sensitive   = true
}

variable "postgres_db_enabled" {
  description = "Whether to enable loading into a Postgres Database"
  default     = false
  type        = bool
}

variable "postgres_db_name" {
  description = "The name of the database to connect to"
  type        = string
}

variable "postgres_db_username" {
  description = "The username to use to connect to the database"
  type        = string
}

variable "postgres_db_password" {
  description = "The password to use to connect to the database"
  type        = string
  sensitive   = true
}

variable "postgres_db_authorized_networks" {
  description = "The list of CIDR ranges to allow access to the Pipeline Database over"
  default     = []
  type = list(object({
    name  = string
    value = string
  }))
}

variable "postgres_db_tier" {
  description = "The instance type to assign to the deployed Cloud SQL instance"
  type        = string
  default     = "db-g1-small"
}

variable "bigquery_db_enabled" {
  description = "Whether to enable loading into a BigQuery Dataset"
  default     = false
  type        = bool
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

variable "telemetry_enabled" {
  description = "Whether or not to send telemetry information back to Snowplow Analytics Ltd"
  type        = bool
  default     = true
}

variable "user_provided_id" {
  description = "An optional unique identifier to identify the telemetry events emitted by this stack"
  default     = ""
  type        = string
}

variable "ssl_information" {
  description = "The ID of an Google Managed certificate to bind to the load balancer"
  type = object({
    enabled        = bool
    certificate_id = string
  })
  default = {
    certificate_id = ""
    enabled        = false
  }
}

variable "labels" {
  description = "The labels to append to the resources in this module"
  default     = {}
  type        = map(string)
}