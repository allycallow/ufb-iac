resource "aws_dynamodb_table" "recommendations" {
  name                        = var.name
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

  tags = merge(var.tags, {
    Name = var.name
  })
}
