# Grafana alerting resources. First Terraform-managed alert in this account -
# every existing rule (Airflow, Backend, Search, Recommendations) was
# provisioned by hand, each with its own dedicated PagerDuty contact point in
# its own folder. This follows the same per-service convention for DDEX.

resource "grafana_folder" "ddex_alerts" {
  title = "DDEX-Alerts"
}

resource "grafana_contact_point" "ddex_delivery" {
  name = "DDEX Delivery"

  pagerduty {
    integration_key = jsondecode(data.aws_secretsmanager_secret_version.grafana.secret_string)["pagerduty_ddex_integration_key"]
    # This account's PagerDuty org is EU-region - the provider/notifier
    # default is the US events endpoint, which would silently never deliver.
    url = "https://events.eu.pagerduty.com/v2/enqueue"
  }
}

resource "grafana_rule_group" "ddex_dlq" {
  name             = "ddex-dlq"
  folder_uid       = grafana_folder.ddex_alerts.uid
  interval_seconds = 60

  rule {
    name      = "DDEX - Delivery stuck in DLQ"
    condition = "C"
    for       = "1m"

    # A delivery only reaches the DLQ after 3 failed receives (see
    # modules/ddex-delivery/main.tf's redrive_policy) - anything visible
    # here already exhausted its retries and needs a human, not a
    # transient blip that'll clear on its own.
    data {
      ref_id         = "A"
      datasource_uid = "cloudwatch"
      query_type     = "metrics"

      relative_time_range {
        from = 600
        to   = 0
      }

      model = jsonencode({
        namespace  = "AWS/SQS"
        metricName = "ApproximateNumberOfMessagesVisible"
        statistic  = "Maximum"
        region     = "eu-west-2"
        dimensions = {
          QueueName = "production-ufb-ddex-delivery-dlq"
        }
        queryMode        = "Metrics"
        metricQueryType  = 0
        metricEditorMode = 0
        period           = "300"
        refId            = "A"
      })
    }

    # CloudWatch's query (A) returns time series, not a single value - a
    # threshold expression can only alert on reduced data, so this reduce
    # step (matching the Airflow rule's own A->B->C shape) has to sit
    # between the query and the threshold.
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
      contact_point = grafana_contact_point.ddex_delivery.name
    }
  }
}
