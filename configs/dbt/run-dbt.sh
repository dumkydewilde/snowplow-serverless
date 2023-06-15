#!/bin/bash
git clone -b dbt-job https://github.com/dumkydewilde/snowplow-serverless.git
cd snowplow-serverless/dbt
pip install dbt-bigquery
dbt debug
dbt deps
dbt run --selector snowplow_web