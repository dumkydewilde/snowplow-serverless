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

variable "ssh_key_pairs" {
  description = "The list of SSH key-pairs to add to the servers"
  default     = []
  type = list(object({
    user_name  = string
    public_key = string
  }))
}

variable "ssh_ip_allowlist" {
  description   = "The list of CIDR ranges to allow SSH traffic from"
  default       = ["0.0.0.0/0"]
  type          = list(any)
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

variable "labels" {
  description = "The labels to append to the resources in this module"
  default     = {}
  type        = map(string)
}