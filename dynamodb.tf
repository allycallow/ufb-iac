resource "aws_dynamodb_table" "recommendations" {
  name                        = "${local.name}-recommendations"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = "PK"
  range_key                   = "SK"
  deletion_protection_enabled = true

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

output "recommendations_table_name" {
  value = aws_dynamodb_table.recommendations.name
}
