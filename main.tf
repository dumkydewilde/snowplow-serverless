provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_service_account" "cloud_run_sa" {
  account_id = "cloud-run-sa"
}

locals {
  custom_iglu_resolvers = [
    {
      name            = "Iglu Server"
      priority        = 0
      uri             = "${var.iglu_server_dns_name}/api"
      api_key         = var.iglu_super_api_key
      vendor_prefixes = []
    }
  ]

    # Configs
    config_iglu_resolver = base64encode(file("${path.module}/configs/iglu_resolver.json"))
    config_collector = base64encode(templatefile("${path.module}/configs/collector/config.hocon.tmpl", {
        stream_good = "${var.prefix}-good-topic"
        stream_bad = "${var.prefix}-raw-topic"
        google_project_id = var.project_id
    }))

    # enrichments
    campaign_attribution     = jsonencode(file("${path.module}/configs/enrichments/campaign_attribution.json"))
    anonymise_ip             = jsonencode(file("${path.module}/configs/enrichments/anon_ip.json"))
    referer_parser           = jsonencode(file("${path.module}/configs/enrichments/referer_parser.json"))
    javascript_enrichment    = jsonencode(templatefile("${path.module}/configs/enrichments/javascript_enrichment.json.tmpl", {
                                    javascript_script = base64encode(file("${path.module}/enrichments/javascript_enrichment_script.js"))
                                }))

    enrichments = base64encode(campaign_attribution)
}

# 1. Deploy PubSub Topics
module "raw_topic" {
  source  = "snowplow-devops/pubsub-topic/google"
  version = "0.1.0"

  name = "${var.prefix}-raw-topic"

  labels = var.labels
}

module "bad_1_topic" {
  source  = "snowplow-devops/pubsub-topic/google"
  version = "0.1.0"

  name = "${var.prefix}-bad-1-topic"

  labels = var.labels
}

module "enriched_topic" {
  source  = "snowplow-devops/pubsub-topic/google"
  version = "0.1.0"

  name = "${var.prefix}-enriched-topic"

  labels = var.labels
}

# 2. Deploy Collector stack
#module "collector_pubsub" {
#  source  = "snowplow-devops/collector-pubsub-ce/google"
#  version = "0.2.2"
#
#  name = "${var.prefix}-collector-server"
#
#  network    = var.network
#  subnetwork = var.subnetwork
#  region     = var.region
#
#  ssh_ip_allowlist = var.ssh_ip_allowlist
#  ssh_key_pairs    = var.ssh_key_pairs
#
#  topic_project_id = var.project_id
#  good_topic_name  = module.raw_topic.name
#  bad_topic_name   = module.bad_1_topic.name
#
#  telemetry_enabled = var.telemetry_enabled
#  user_provided_id  = var.user_provided_id
#
#  associate_public_ip_address = false
#
#  labels = var.labels
#}

# ---- Cloud Run service
resource "google_cloud_run_v2_service" "collector_server" {
    name = "${var.prefix}-collector-server"
    location = var.region
    project = var.project_id

    ingress = "INGRESS_TRAFFIC_ALL"

    template {
        service_account_name = google_service_account.cloud_run_sa.email

        scaling {
            max_instance_count = 2
        }
        
        containers {
            image = "snowplow/scala-stream-collector-pubsub:latest"
            args = [
                "--config", "${local.config_collector}",
                "--iglu-config", "${local.config_iglu_resolver}",
                "--enrichments", "${local.enrichments}"
            ]
        }
        
    }

    traffic {
        type = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
        percent = 100
    }
}

# 3. Deploy Enrichment
module "enrich_pubsub" {
  source  = "snowplow-devops/enrich-pubsub-ce/google"
  version = "0.1.2"

  name = "${var.prefix}-enrich-server"

  network    = var.network
  subnetwork = var.subnetwork
  region     = var.region

  ssh_ip_allowlist = var.ssh_ip_allowlist
  ssh_key_pairs    = var.ssh_key_pairs

  raw_topic_name = module.raw_topic.name
  good_topic_id  = module.enriched_topic.id
  bad_topic_id   = module.bad_1_topic.id

  # Linking in the custom Iglu Server here
  custom_iglu_resolvers = local.custom_iglu_resolvers

  telemetry_enabled = var.telemetry_enabled
  user_provided_id  = var.user_provided_id

  associate_public_ip_address = false

  labels = var.labels
}


# 5. Deploy BigQuery Loader
module "bad_rows_topic" {
  source  = "snowplow-devops/pubsub-topic/google"
  version = "0.1.0"

  name = "${var.prefix}-bq-bad-rows-topic"

  labels = var.labels
}

resource "google_bigquery_dataset" "bigquery_db" {
  dataset_id = replace("${var.prefix}_snowplow_db", "-", "_")
  location   = var.region

  labels = var.labels
}

resource "google_storage_bucket" "bq_loader_dead_letter_bucket" {
  count = var.bigquery_loader_dead_letter_bucket_deploy ? 1 : 0

  name          = var.bigquery_loader_dead_letter_bucket_name
  location      = var.region
  force_destroy = true

  labels = var.labels
}

locals {
  bq_loader_dead_letter_bucket_name = coalesce(
    join("", google_storage_bucket.bq_loader_dead_letter_bucket.*.name),
    var.bigquery_loader_dead_letter_bucket_name,
  )
}

module "bigquery_loader" {
  source  = "snowplow-devops/bigquery-loader-pubsub-ce/google"
  version = "0.1.0"

  name = "${var.prefix}-bq-loader-server"

  network    = var.network
  subnetwork = var.subnetwork
  region     = var.region
  project_id = var.project_id

  ssh_ip_allowlist = var.ssh_ip_allowlist
  ssh_key_pairs    = var.ssh_key_pairs

  input_topic_name            = module.enriched_topic.name
  bad_rows_topic_name         = join("", module.bad_rows_topic.*.name)
  gcs_dead_letter_bucket_name = local.bq_loader_dead_letter_bucket_name
  bigquery_dataset_id         = join("", google_bigquery_dataset.bigquery_db.*.dataset_id)

  # Linking in the custom Iglu Server here
  custom_iglu_resolvers = local.custom_iglu_resolvers

  telemetry_enabled = var.telemetry_enabled
  user_provided_id  = var.user_provided_id

  labels = var.labels
}