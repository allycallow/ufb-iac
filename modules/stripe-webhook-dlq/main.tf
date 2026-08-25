data "aws_caller_identity" "current" {}

# Dead-letter queues for the Stripe-triggered Lambdas in ufb/services (serverless.yml).
# Each function's native `eventBridge` event references its queue via
# `deadLetterQueueArn`, built there from the same ${stage}-ufb-<name>-dlq naming
# convention used here — there's no cross-repo state lookup.
#
# The queue policy scopes to aws:SourceAccount rather than the specific rule ARN:
# Serverless Framework auto-generates the underlying AWS::Events::Rule for each
# `eventBridge` event and doesn't expose a stable logical ID to reference here.

locals {
  dlq_names = [
    "invoice-created",
    "invoice-paid",
    "invoice-payment-failed",
    "customer-subscription-trial-ended",
    "customer-subscription-canceled-payment-failed",
    "payment-method-attached",
    "customer-subscription-deleted",
  ]
}

resource "aws_sqs_queue" "dlq" {
  for_each = toset(local.dlq_names)

  name                      = "${var.stage}-ufb-${each.value}-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = merge(var.tags, {
    Name = "${var.stage}-ufb-${each.value}-dlq"
  })
}

resource "aws_sqs_queue_policy" "dlq" {
  for_each = aws_sqs_queue.dlq

  queue_url = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridge"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = each.value.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}
