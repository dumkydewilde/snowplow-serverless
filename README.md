A serverless Snowplow pipeline on Google Cloud Platform (GCP).

This repository is a Terraform template to run a fully serverless snowplow pipeline based on Google Cloud Run and BigQuery.
This allows you to run Snowplow at a minimal cost, especially for smaller sites and blogs.

## Basic Setup
The basic idea is to run a serverless collector and all the other components on a schedule (e.g. three times a day). This allows you to scale
down to zero while allowing still run a near-realtime pipeline. 

The pipeline uses the following components
- Cloud Run Service for collecting hits 
- Pub/Sub for communication between components
- Cloud Run Job for enrichment
- Cloud Run Job for the BigQuery stream loader
- Cloud Run Jobs for creating, mutating the BigQuery table as well as repeating failed inserts.

## To Do
- Seperate service accounts for seperate services
- Add schedules (Cloud Scheduler) and workflows
