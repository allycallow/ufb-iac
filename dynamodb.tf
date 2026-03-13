resource "aws_dynamodb_table" "notifications" {
  name         = "${local.name}-notifications"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  ttl {
    attribute_name = "timeToExist"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "recommendations" {
  name         = "${local.name}-recommendations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  ttl {
    attribute_name = "timeToExist"
    enabled        = true
  }
}

output "notifications_table_name" {
  value = aws_dynamodb_table.notifications.name
}

output "recommendations_table_name" {
  value = aws_dynamodb_table.recommendations.name
}
