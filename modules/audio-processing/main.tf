resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600

  tags = merge(var.tags, {
    Name = "${var.name}-dlq"
  })
}

resource "aws_sqs_queue" "main" {
  name                       = var.name
  visibility_timeout_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.main.arn]
  })
}


resource "aws_s3_bucket_notification" "media_upload_events" {
  bucket = var.media_bucket_id

  queue {
    queue_arn     = aws_sqs_queue.main.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "audio/"
    filter_suffix = ".mp3"
  }

  depends_on = [aws_sqs_queue_policy.allow_s3]
}
