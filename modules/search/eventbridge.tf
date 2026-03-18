data "aws_secretsmanager_secret" "backend_secrets" {
  arn = "arn:aws:secretsmanager:eu-west-2:081077757258:secret:/ufb/production/search-ec4ayE"
}

data "aws_secretsmanager_secret_version" "current" {
  secret_id = data.aws_secretsmanager_secret.backend_secrets.id
}

resource "aws_cloudwatch_event_rule" "search_created_events" {
  name           = "search-created-events"
  event_bus_name = var.event_bus_name
  event_pattern = jsonencode({
    source = ["app"]
    "detail-type" = [
      "track.created",
      "release.created",
      "artist.created",
      "label.created"
    ]
  })
}

resource "aws_cloudwatch_event_rule" "search_updated_events" {
  name           = "search-updated-events"
  event_bus_name = var.event_bus_name
  event_pattern = jsonencode({
    source = ["app"]
    "detail-type" = [
      "track.updated",
      "release.updated",
      "artist.updated",
      "label.updated"
    ]
  })
}


resource "aws_cloudwatch_event_rule" "search_deleted_events" {
  name           = "search-deleted-events"
  event_bus_name = var.event_bus_name
  event_pattern = jsonencode({
    source = ["app"]
    "detail-type" = [
      "track.deleted",
      "release.deleted",
      "artist.deleted",
      "label.deleted"
    ]
  })
}


resource "aws_cloudwatch_event_target" "search_events_create_api_destination" {
  rule           = aws_cloudwatch_event_rule.search_created_events.name
  event_bus_name = var.event_bus_name
  arn            = aws_cloudwatch_event_api_destination.search_created_api_destination.arn
  role_arn       = aws_iam_role.search_api_destination_role.arn
}

resource "aws_cloudwatch_event_target" "search_events_update_api_destination" {
  rule           = aws_cloudwatch_event_rule.search_updated_events.name
  event_bus_name = var.event_bus_name
  arn            = aws_cloudwatch_event_api_destination.search_update_api_destination.arn
  role_arn       = aws_iam_role.search_api_destination_role.arn
}

resource "aws_cloudwatch_event_target" "search_events_delete_api_destination" {
  rule           = aws_cloudwatch_event_rule.search_deleted_events.name
  event_bus_name = var.event_bus_name
  arn            = aws_cloudwatch_event_api_destination.search_delete_api_destination.arn
  role_arn       = aws_iam_role.search_api_destination_role.arn
}

resource "aws_cloudwatch_event_api_destination" "search_created_api_destination" {
  name                = "${var.name}-add-api-destination"
  invocation_endpoint = "https://search.upfrontbeats.com/api/search/add"
  http_method         = "POST"
  connection_arn      = aws_cloudwatch_event_connection.search_api_connection.arn
}

resource "aws_cloudwatch_event_api_destination" "search_update_api_destination" {
  name                = "${var.name}-update-api-destination"
  invocation_endpoint = "https://search.upfrontbeats.com/api/search/update"
  http_method         = "PUT"
  connection_arn      = aws_cloudwatch_event_connection.search_api_connection.arn
}

resource "aws_cloudwatch_event_api_destination" "search_delete_api_destination" {
  name                = "${var.name}-delete-api-destination"
  invocation_endpoint = "https://search.upfrontbeats.com/api/search/delete"
  http_method         = "DELETE"
  connection_arn      = aws_cloudwatch_event_connection.search_api_connection.arn
}

resource "aws_cloudwatch_event_connection" "search_api_connection" {
  name               = "${var.name}-api-connection"
  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "x-api-key"
      value = jsondecode(data.aws_secretsmanager_secret_version.current.secret_string)["API_KEY"]
    }
  }
}

resource "aws_iam_role" "search_api_destination_role" {
  name = "${var.name}-search-api-destination-role"
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


resource "aws_iam_role_policy" "search_api_invocation_policy" {
  name = "${var.name}-search-api-invocation-policy"
  role = aws_iam_role.search_api_destination_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "events:InvokeApiDestination"
        Effect = "Allow"
        # Best practice: Limit to your specific ARNs, or use "*" for testing
        Resource = [
          aws_cloudwatch_event_api_destination.search_created_api_destination.arn,
          aws_cloudwatch_event_api_destination.search_update_api_destination.arn,
          aws_cloudwatch_event_api_destination.search_delete_api_destination.arn
        ]
      }
    ]
  })
}
