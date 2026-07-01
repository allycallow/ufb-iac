resource "aws_dynamodb_table" "idempotency" {
  name         = "${var.stage}-ufb-idempotency"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  ttl {
    attribute_name = "expiration"
    enabled        = true
  }

  tags = merge(var.tags, {
    Name = "${var.stage}-ufb-idempotency"
  })
}
