#!/bin/bash
git clone -b dbt-job "$1"
cd "$2"
pip install dbt-bigquery
dbt debug
dbt deps
dbt run --selector snowplow_web