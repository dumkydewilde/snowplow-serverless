### SETUP ###
provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable APIs
resource "google_project_service" "run_api" {
  service = "run.googleapis.com"
}
resource "google_project_service" "schedule_api" {
  service = "cloudscheduler.googleapis.com"
}

# Set up service account and permissions
resource "google_service_account" "cloud_run_sa" {
  account_id = "snowplow-ice-terra"
  display_name = "Snowplow Cloud Run Service Account"
}

resource "google_project_iam_member" "cloud_run_sa" {
  for_each = toset([
    "roles/bigquery.dataEditor", 
    "roles/bigquery.jobUser", 
    "roles/pubsub.editor", 
    "roles/run.serviceAgent",
    "roles/run.invoker",
    "roles/logging.logWriter",
    "roles/storage.objectViewer"
    ])
  project = var.project_id
  role = each.value
  member = google_service_account.cloud_run_sa.member
}

### VARIABLES ###
locals {
    job_timeout = "300s"

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

### IGLU SCHEMAS ###
resource "random_string" "six_chars" {
  length  = 6
  special = false
  upper   = false
}

resource "google_storage_bucket" "iglu_resolver_bucket" {
  name = "${var.prefix}-iglu-schemas-${random_string.six_chars.result}"
  location = var.region
  project = var.project_id
  uniform_bucket_level_access = true
  force_destroy = true
}

resource "google_storage_bucket_iam_member" "member" {
  bucket = google_storage_bucket.iglu_resolver_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

locals {
  config_iglu_resolver = base64encode(templatefile("${path.module}/configs/iglu_resolver.json.tmpl", {
    VENDOR      = var.vendor
    BUCKET_NAME = google_storage_bucket.iglu_resolver_bucket.name
    BUCKET_PATH = ""
    })
  )
}


### PIPELINE ###

# 1. Deploy PubSub Topics & Subs
locals {
    # Configs
    topic_names = ["raw", "bad", "enriched", "bq-bad-rows", "loader-types", "failed-inserts"]
}
resource "google_pubsub_topic" "topics" {
  for_each = toset(local.topic_names)
  
  name = "${var.prefix}-${each.value}-topic"
  labels = var.labels
}

resource "google_pubsub_subscription" "subscriptions" {
  for_each = toset(local.topic_names)
  name  = "${var.prefix}-${each.value}-sub"
  topic =  google_pubsub_topic.topics[each.value].name
  expiration_policy {
    ttl = ""
  }
  labels = var.labels

  depends_on = [ google_pubsub_topic.topics ]
}

# 2. Collector
locals {
  config_collector = base64encode(templatefile("${path.module}/configs/collector/config.hocon.tmpl", {
    stream_good = google_pubsub_topic.topics["raw"].name
    stream_bad =  google_pubsub_topic.topics["bad"].name
    google_project_id = var.project_id
  }))
}
resource "google_cloud_run_v2_service" "collector_server" {
    name = "${var.prefix}-collector-server"
    location = var.region
    project = var.project_id

    ingress = "INGRESS_TRAFFIC_ALL"

    template {
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
    enricher_input = google_pubsub_subscription.subscriptions["raw"].id
    stream_enriched =  google_pubsub_topic.topics["enriched"].name
    stream_bad =  google_pubsub_topic.topics["bad"].name
  }))

  enrichments = base64encode(templatefile("${path.module}/configs/enricher/enrichments.json.tmpl", { enrichments = join(",", local.enrichments_list) }))
}

resource "google_cloud_run_v2_job" "enrichment_job" {
    name = "${var.prefix}-enrichment-job"
    location = var.region
    project = var.project_id

    template {
      template {
        timeout = local.job_timeout
        service_account = google_service_account.cloud_run_sa.email
        containers {
            image = "snowplow/snowplow-enrich-pubsub:latest-distroless"
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
}



# 4. Deploy BigQuery Loader


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
  labels        = var.labels
}

resource "google_storage_bucket_iam_binding" "dead_letter_storage_object_admin_binding" {
  bucket = google_storage_bucket.bq_loader_dead_letter_bucket[0].name
  role   = "roles/storage.objectAdmin"
  members = [google_service_account.cloud_run_sa.member]
}

resource "google_bigquery_dataset_iam_member" "dataset_bigquery_data_editor_binding" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.bigquery_db.dataset_id
  role       = "roles/bigquery.dataEditor"
  member    = google_service_account.cloud_run_sa.member
}

locals {
  bq_loader_dead_letter_bucket_name = coalesce(
    join("", google_storage_bucket.bq_loader_dead_letter_bucket.*.name),
    var.bigquery_loader_dead_letter_bucket_name,
  )

  config_loader = base64encode(templatefile("${path.module}/configs/loader/config.hocon.tmpl", {
    project_id = var.project_id
    loader_input = google_pubsub_subscription.subscriptions["enriched"].name 
    dataset_id = google_bigquery_dataset.bigquery_db.dataset_id
    table_id = "${var.prefix}_events"
    bad_topic =  google_pubsub_topic.topics["bad"].name
    failed_inserts_topic =  google_pubsub_topic.topics["failed-inserts"].name
    failed_inserts_sub = google_pubsub_subscription.subscriptions["failed-inserts"].name 
    mutator_types_topic =  google_pubsub_topic.topics["loader-types"].name
    mutator_types_sub = google_pubsub_subscription.subscriptions["loader-types"].name 
    dead_letter_bucket = google_storage_bucket.bq_loader_dead_letter_bucket[0].url
  }))
}

# Mutator 
resource "google_cloud_run_v2_job" "mutator_create_job" {
    name = "${var.prefix}-mutator-create-job"
    location = var.region
    project = var.project_id

    template {
      template {
        timeout = local.job_timeout
        service_account = google_service_account.cloud_run_sa.email
        containers {
            image = "snowplow/snowplow-bigquery-mutator:latest-distroless"
            args = [
              "create", 
              "--config=${local.config_loader}",
              "--resolver=${local.config_iglu_resolver}",
              "--partitionColumn=load_tstamp"
            ]   
        }
        max_retries = 1
      }
    }

    lifecycle {
      ignore_changes = [
        launch_stage,
      ]
    }
}

resource "google_cloud_run_v2_job" "mutator_listen_job" {
    name = "${var.prefix}-mutator-listen-job"
    location = var.region
    project = var.project_id

    template {
      template {
        timeout = local.job_timeout
        service_account = google_service_account.cloud_run_sa.email
        containers {
            image = "snowplow/snowplow-bigquery-mutator:latest-distroless"
            args = [
              "listen", 
              "--config=${local.config_loader}",
              "--resolver=${local.config_iglu_resolver}",
            ]   
        }
        max_retries = 1
      }
    }

    lifecycle {
      ignore_changes = [
        launch_stage,
      ]
    }
}

resource "google_cloud_run_v2_job" "streamloader" {
    name = "${var.prefix}-streamloader-job"
    location = var.region
    project = var.project_id

    template {
      template {
        timeout = local.job_timeout
        service_account = google_service_account.cloud_run_sa.email
        containers {
            image = "snowplow/snowplow-bigquery-streamloader:latest"
            args = [
              "--config=${local.config_loader}",
              "--resolver=${local.config_iglu_resolver}",
            ]   
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

resource "google_cloud_run_v2_job" "repeater" {
    name = "${var.prefix}-repeater-job"
    location = var.region
    project = var.project_id

    template {
      template {
        timeout = local.job_timeout
        service_account = google_service_account.cloud_run_sa.email
        containers {
            image = "snowplow/snowplow-bigquery-repeater:latest-distroless"
            args = [
              "--config=${local.config_loader}",
              "--resolver=${local.config_iglu_resolver}",
              "--bufferSize=20",
              "--timeout=20",
              "--backoffPeriod=500"
            ]   
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


resource "google_cloud_scheduler_job" "jobs_scheduler" {
  for_each = toset([ "repeater-job", "streamloader-job", "mutator-listen-job", "enrichment-job" ])
  region           = "europe-west1"
  name             = "${var.prefix}-${each.value}-scheduler"
  description      = "Trigger for ${each.value}"
  schedule         = "23 8-21/3 * * *"
  time_zone        = "Europe/Amsterdam"
  attempt_deadline = "320s"

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${var.prefix}-${each.value}:run"
    oauth_token {
      service_account_email = google_service_account.cloud_run_sa.email
      scope = "https://www.googleapis.com/auth/cloud-platform"
    }
  }
}