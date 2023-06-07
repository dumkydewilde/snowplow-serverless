### SETUP ###
provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable APIs
resource "google_project_service" "run_api" {
  service = "run.googleapis.com"
}

# Set up service account
resource "google_service_account" "cloud_run_sa" {
  account_id = "snowplow-ice-terra"
  display_name = "Snowplow Cloud Run Service Account"
}

resource "google_project_iam_member" "cloud_run_sa" {
  for_each = toset(["roles/pubsub.publisher", "roles/pubsub.editor", "roles/run.serviceAgent"])
  project = var.project_id
  role = each.value
  member = google_service_account.cloud_run_sa.member
}

### VARIABLES ###
locals {
    # Configs
    topic_names = ["raw-topic", "bad-1-topic", "enriched-topic", "bq-bad-rows-topic"]
    config_iglu_resolver = base64encode(file("${path.module}/configs/iglu_resolver.json"))

    # enrichments
    campaign_attribution     = file("${path.module}/configs/enricher/campaign_attribution.json")
    anonymise_ip             = file("${path.module}/configs/enricher/anon_ip.json")
    referer_parser           = file("${path.module}/configs/enricher/referer_parser.json")
    javascript_enrichment    = templatefile("${path.module}/configs/enricher/javascript_enrichment.json.tmpl", {
                                    javascript_script = base64encode(file("${path.module}/configs/enricher/javascript_enrichment_script.js"))
                                })

    enrichments_list = [
        local.campaign_attribution,
        local.anonymise_ip,
        local.referer_parser,
        local.javascript_enrichment
    ]
}

# 1. Deploy PubSub Topics & Subs
resource "google_pubsub_topic" "topics" {
  for_each = toset(local.topic_names)
  
  name = "${var.prefix}-${each.value}"
  labels = var.labels
}

resource "google_pubsub_subscription" "subscriptions" {
  for_each = toset(local.topic_names)
  name  = "${var.prefix}-${each.value}-sub"
  topic = "${var.prefix}-${each.value}"
  expiration_policy {
    ttl = ""
  }
  labels = var.labels
}

# 2. Collector
locals {
  config_collector = base64encode(templatefile("${path.module}/configs/collector/config.hocon.tmpl", {
    stream_good = "${var.prefix}-raw-topic"
    stream_bad = "${var.prefix}-bad-1-topic"
    google_project_id = var.project_id
  }))
}
resource "google_cloud_run_v2_service" "collector_server" {
    name = "${var.prefix}-collector-server"
    location = var.region
    project = var.project_id

    ingress = "INGRESS_TRAFFIC_ALL"

    template {
        revision = "${var.prefix}-collector-server-${formatdate("YYMMDDhhmmss", timestamp())}"
        service_account = google_service_account.cloud_run_sa.email
        scaling {
            max_instance_count = 1
        }
        containers {
            name = "${var.prefix}-collector-server"
            image = "snowplow/scala-stream-collector-pubsub:latest"
            command = [
                "/bin/sh",
                "-c",
                "echo '${local.config_collector}' | base64 -d > config.hocon && /home/snowplow/bin/snowplow-stream-collector --config=config.hocon"
            ]   
        }
    }

    traffic {
        type = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
        percent = 100
    }
    
    lifecycle {
      ignore_changes = [
        template.0.revision
      ]
    }

    depends_on = [google_project_service.run_api]
}

resource "google_cloud_run_service_iam_binding" "collector_server" {
  location = google_cloud_run_v2_service.collector_server.location
  service  = google_cloud_run_v2_service.collector_server.name
  role     = "roles/run.invoker"
  members = [
    "allUsers"
  ]
}

# 3. Deploy Enrichment
locals {
  config_enricher = base64encode(templatefile("${path.module}/configs/enricher/config.hocon.tmpl", {
    project_id = var.project_id
    enricher_input = google_pubsub_subscription.subscriptions["raw-topic"].id
    stream_enriched = "${var.prefix}-enriched-topic"
    stream_bad = "${var.prefix}-bad-1-topic"
  }))

  enrichments = base64encode(templatefile("${path.module}/configs/enricher/enrichments.json.tmpl", { enrichments = join(",", local.enrichments_list) }))
}

resource "google_cloud_run_v2_job" "enrichment_job" {
    name = "${var.prefix}-enrichment-job"
    location = var.region
    project = var.project_id

    template {
      template {
        timeout = "600s"
        service_account = google_service_account.cloud_run_sa.email
        containers {
            image = "snowplow/snowplow-enrich-pubsub:latest"
            args = [
              "--config=${local.config_enricher}",
              "--enrichments=${local.enrichments}",
              "--iglu-config=${local.config_iglu_resolver}",
            ]   
            resources {
              limits = {
                cpu = "2"
                memory = "1Gi"
              }
            }
        }
        max_retries = 1
      }
    }

    lifecycle {
      ignore_changes = [
        launch_stage,
      ]
    }

    depends_on = [google_project_service.run_api]
}



# 5. Deploy BigQuery Loader

resource "google_bigquery_dataset" "bigquery_db" {
  dataset_id = replace("${var.prefix}_snowplow", "-", "_")
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

#module "bigquery_loader" {
#  source  = "snowplow-devops/bigquery-loader-pubsub-ce/google"
#  version = "0.1.0"
#
#  name = "${var.prefix}-bq-loader-server"
#
#  network    = var.network
#  subnetwork = var.subnetwork
#  region     = var.region
#  project_id = var.project_id
#
#  ssh_ip_allowlist = var.ssh_ip_allowlist
#  ssh_key_pairs    = var.ssh_key_pairs
#
#  input_topic_name            = module.enriched_topic.name
#  bad_rows_topic_name         = join("", module.bad_rows_topic.*.name)
#  gcs_dead_letter_bucket_name = local.bq_loader_dead_letter_bucket_name
#  bigquery_dataset_id         = join("", google_bigquery_dataset.bigquery_db.*.dataset_id)
#
#  # Linking in the custom Iglu Server here
#  custom_iglu_resolvers = local.custom_iglu_resolvers
#
#  telemetry_enabled = var.telemetry_enabled
#  user_provided_id  = var.user_provided_id
#
#  labels = var.labels
#}