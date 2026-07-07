# Schemas match Teleport's documented DynamoDB backend requirements:
# https://goteleport.com/docs/reference/backends/#dynamodb

resource "aws_dynamodb_table" "teleport_state" {
  name         = "${var.name}-teleport-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "HashKey"
  range_key    = "FullPath"

  attribute {
    name = "HashKey"
    type = "S"
  }

  attribute {
    name = "FullPath"
    type = "S"
  }

  ttl {
    attribute_name = "Expires"
    enabled        = true
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  tags = merge(var.tags, { Name = "${var.name}-teleport-state" })
}

resource "aws_dynamodb_table" "teleport_events" {
  name         = "${var.name}-teleport-events"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "SessionID"
  range_key    = "EventIndex"

  attribute {
    name = "SessionID"
    type = "S"
  }

  attribute {
    name = "EventIndex"
    type = "N"
  }

  attribute {
    name = "EventNamespace"
    type = "S"
  }

  attribute {
    name = "CreatedAtDate"
    type = "S"
  }

  global_secondary_index {
    name            = "timesearchV2"
    hash_key        = "EventNamespace"
    range_key       = "CreatedAtDate"
    projection_type = "ALL"
  }

  ttl {
    attribute_name = "Expires"
    enabled        = true
  }

  tags = merge(var.tags, { Name = "${var.name}-teleport-events" })
}
