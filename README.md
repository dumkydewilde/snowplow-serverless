# Serverless Snowplow
A serverless Snowplow pipeline on Google Cloud Platform (GCP) for ~€0.02/day.

This repository is a Terraform template to run a fully serverless snowplow pipeline based on Google Cloud Run and BigQuery.
This allows you to run Snowplow at a minimal cost, especially for smaller sites and blogs. 

## Basic Setup
The basic idea is to run a serverless collector and all the other components on a schedule (e.g. three times a day). This allows you to scale
down to zero while allowing still run a near-realtime pipeline. 

The pipeline uses the following components
- Cloud Run Service for collecting hits 
- Pub/Sub for communication between components
- Cloud Run Job for enrichment
- Google Cloud Storage bucket for storing custom schemas (everything in the schemas/ folder is automatically uploaded to this bucket)
- Cloud Run Job for the BigQuery stream loader
- Cloud Run Jobs for creating, mutating the BigQuery table as well as repeating failed inserts.
- Cloud Run Job to run the Snowplow dbt packages. This currently fetches the dbt project inside this folder, but you can also supply 
it with your own dbt repo. 

The collector is serverless so it will scale to zero if there is no traffic. However if you do have continuous traffic, 
this might not be the best option for you as serverless instances work best for intermittent loads. The rest of the pipeline
runs on a schedule where it will process and load everything every three hours between 08:00-20:00 —who has the time for 
real-time data anyway, right?

## Cost
I've been running this setup for blog with ~15.000 visitors/month for 2 cents a day. If you still have your GCP credits, you should be good 
for the next 30 years or so... In any case you always want to set up cost controls and keep an eye on your spending. Don't say I didn't warn you.

## To Do
- Seperate service accounts for seperate services
- Automate table creation on initial run
- Add workflows in combination with schedule
- Gracefully shut down Cloud Run Jobs when everything is processed instead of letting them fail on timeout
- Create seperate storage bucket with enrichments to mount to enricher Cloud Run Job
