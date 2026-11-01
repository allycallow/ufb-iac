# Terraform-managed alerting for the OpenAI Batch DAGs (generate_track_tags,
# generate_artist_related_artists, generate_labels_related_artists). Follows
# the same per-service convention as grafana-alerts.tf's DDEX rule, but
# routes to the pre-existing "Airflow" PagerDuty service rather than a new
# one, since these failures are Airflow task failures.

resource "grafana_folder" "openai_batch_alerts" {
  title = "OpenAI-Batch-Alerts"
}

resource "grafana_contact_point" "openai_batch_failure" {
  name = "OpenAI Batch Failure"

  pagerduty {
    integration_key = jsondecode(data.aws_secretsmanager_secret_version.grafana.secret_string)["pagerduty_airflow_integration_key"]
    # This account's PagerDuty org is EU-region - the provider/notifier
    # default is the US events endpoint, which would silently never deliver.
    url = "https://events.eu.pagerduty.com/v2/enqueue"
  }
}

resource "grafana_rule_group" "openai_batch_failures" {
  name             = "openai-batch-failures"
  folder_uid       = grafana_folder.openai_batch_alerts.uid
  interval_seconds = 60

  rule {
    name      = "OpenAI Batch - job ended failed/expired/cancelled"
    condition = "C"
    for       = "1m"

    # One metric per DAG (dags/utils/openai_batch.py's OpenAIBatchCompletionSensor
    # increments openai_batch.<dag_id>.batch_failed right before raising) -
    # summed with "or vector(0)" since a counter series doesn't exist in
    # Prometheus until it's incremented at least once.
    data {
      ref_id         = "A"
      datasource_uid = "prometheus"
      query_type     = ""

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        expr    = <<-EOT
          (increase(openai_batch_generate_track_tags_batch_failed[10m]) or vector(0))
          + (increase(openai_batch_generate_artist_related_artists_batch_failed[10m]) or vector(0))
          + (increase(openai_batch_generate_labels_related_artists_batch_failed[10m]) or vector(0))
        EOT
        instant = true
        refId   = "A"
      })
    }

    # Prometheus's query (A) returns a vector, not a single value - a
    # threshold expression can only alert on reduced data, so this reduce
    # step (matching the DDEX rule's own A->B->C shape) has to sit between
    # the query and the threshold.
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      query_type     = ""

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        type       = "reduce"
        expression = "A"
        reducer    = "last"
        refId      = "B"
      })
    }

    data {
      ref_id         = "C"
      datasource_uid = "__expr__"
      query_type     = ""

      relative_time_range {
        from = 0
        to   = 0
      }

      model = jsonencode({
        type       = "threshold"
        expression = "B"
        conditions = [
          {
            evaluator = {
              type   = "gt"
              params = [0]
            }
          }
        ]
        refId = "C"
      })
    }

    no_data_state  = "Alerting"
    exec_err_state = "Alerting"

    notification_settings {
      contact_point = grafana_contact_point.openai_batch_failure.name
    }
  }
}
