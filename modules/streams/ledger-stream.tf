# Change data capture for the ledger. The stream-ledger-qualified Lambda (ufb/services) reads the
# ledger's DynamoDB stream and sends one "Stream Qualified" event per new row to RudderStack, which
# loads it into the warehouse. DynamoDB retries a failing batch until it succeeds (the stream keeps
# records for 24 hours); batches that still fail after the Lambda's retries land in this queue
# instead of being dropped.
#
# The Lambda itself is deployed by the Serverless Framework from ufb/services, which cannot look up
# Terraform state, so the stream ARN is published through SSM and the queue follows the repo's
# ${stage}-ufb-<handler>-dlq naming (see serverless.yml's dlqArnPrefix).

resource "aws_sqs_queue" "ledger_stream_dlq" {
  name                      = "${var.name}-stream-ledger-dlq"
  message_retention_seconds = 1209600

  tags = merge(var.tags, {
    Name = "${var.name}-stream-ledger-dlq"
  })
}

resource "aws_ssm_parameter" "ledger_stream_arn" {
  name        = "/${var.name}/streams/ledger-stream-arn"
  description = "ARN of the royalty ledger's DynamoDB stream, read by ufb/services at deploy time"
  type        = "String"
  value       = aws_dynamodb_table.ledger.stream_arn

  tags = var.tags
}
