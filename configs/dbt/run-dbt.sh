#!/bin/bash
git clone "$1"
cd "$2"
pip install dbt-bigquery
dbt debug
dbt deps
dbt run --selector snowplow_web