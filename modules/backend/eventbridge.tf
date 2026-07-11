data "aws_secretsmanager_secret" "backend_api_key" {
  arn = var.secret_prefix
}

data "aws_secretsmanager_secret_version" "backend_api_key" {
  secret_id = data.aws_secretsmanager_secret.backend_api_key.id
}

resource "aws_cloudwatch_event_rule" "audio_track_events" {
  name           = "${var.name}-audio-track-events"
  event_bus_name = var.event_bus_name
  event_pattern = jsonencode({
    source = ["ufb.audio-processing"]
    "detail-type" = [
      "AudioTrack.Started",
      "AudioTrack.Downloading",
      "AudioTrack.Encoding",
      "AudioTrack.Packaging",
      "AudioTrack.Uploading",
      "AudioTrack.Completed",
      "AudioTrack.Failed"
    ]
  })
}

resource "aws_cloudwatch_event_target" "audio_track_events_api_destination" {
  rule           = aws_cloudwatch_event_rule.audio_track_events.name
  event_bus_name = var.event_bus_name
  arn            = aws_cloudwatch_event_api_destination.audio_track_destination.arn
  role_arn       = aws_iam_role.audio_track_events_role.arn
}

resource "aws_cloudwatch_event_api_destination" "audio_track_destination" {
  name                = "${var.name}-audio-track-destination"
  invocation_endpoint = "https://new-admin.upfrontbeats.com/api/track-processing-events/"
  http_method         = "POST"
  connection_arn      = aws_cloudwatch_event_connection.audio_track_connection.arn
}

resource "aws_cloudwatch_event_connection" "audio_track_connection" {
  name               = "${var.name}-audio-track-connection"
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "x-api-key"
      value = jsondecode(data.aws_secretsmanager_secret_version.backend_api_key.secret_string)["API_KEY"]
    }
  }
}

resource "aws_iam_role" "audio_track_events_role" {
  name = "${var.name}-audio-track-events-role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Effect" : "Allow",
      "Principal" : {
        "Service" : "events.amazonaws.com"
      },
      "Action" : "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "audio_track_events_policy" {
  name = "${var.name}-audio-track-events-policy"
  role = aws_iam_role.audio_track_events_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = "events:InvokeApiDestination"
        Effect   = "Allow"
        Resource = [aws_cloudwatch_event_api_destination.audio_track_destination.arn]
      }
    ]
  })
}
