resource "aws_s3_bucket" "tempo_traces" {
  bucket        = "${var.name}-tempo-traces"
  force_destroy = false

  tags = {
    Name        = "Tempo Traces Storage"
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

# 2. Block All Public Access (Crucial for security)
resource "aws_s3_bucket_public_access_block" "tempo_traces_security" {
  bucket = aws_s3_bucket.tempo_traces.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 3. Ensure Bucket Ownership Controls default to Bucket Owner Enforced (disables ACLs)
resource "aws_s3_bucket_ownership_controls" "tempo_traces_ownership" {
  bucket = aws_s3_bucket.tempo_traces.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# 4. Enable Server-Side Encryption (Best practice)
resource "aws_s3_bucket_server_side_encryption_configuration" "tempo_traces_encryption" {
  bucket = aws_s3_bucket.tempo_traces.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
