#!/bin/bash
git clone "$1"
cd "$2"
pip install dbt-bigquery
dbt debug
dbt deps
dbt run --selector snowplow_web --vars "{snowplow__database: '$3',snowplow__atomic_schema: '$4',snowplow__start_date: '$5'}"