# Server-side record of royalty-bearing streams. Written only by the backend, never the client:
# a session is opened when GetStreamingAccess authorises a full-track stream, and confirmed once
# the client has listened long enough. Both tables share the PK/SK shape used by recently-played:
#   PK = USER#<user id>, SK = SESSION#<session id> (sessions) / STREAM#<session id> (ledger)

# Short-lived: a session that is never confirmed (skipped, abandoned, or a preview-length listen)
# just expires. Confirmed streams are copied into the ledger below before then.
resource "aws_dynamodb_table" "sessions" {
  name         = "${var.name}-stream-sessions"
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

  tags = merge(var.tags, {
    Name = "${var.name}-stream-sessions"
  })
}

# Append-only ledger of qualified streams that royalties are calculated from. No TTL, and the
# table can't be deleted by an apply; the backend's IAM policy also omits UpdateItem/DeleteItem
# (see modules/backend/ecs.tf). Point-in-time recovery covers accidental or malicious writes.
# A conditional put on SK = STREAM#<session id> is what makes a confirmation happen only once.
resource "aws_dynamodb_table" "ledger" {
  name                        = "${var.name}-streams"
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

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(var.tags, {
    Name = "${var.name}-streams"
  })
}
