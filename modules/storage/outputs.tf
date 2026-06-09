output "media_bucket_id" {
  value = aws_s3_bucket.media.id
}

output "media_bucket_arn" {
  value = aws_s3_bucket.media.arn
}

output "media_bucket_name" {
  value = aws_s3_bucket.media.bucket
}

output "media_bucket_domain_name" {
  value = aws_s3_bucket.media.bucket_domain_name
}

output "events_bucket_id" {
  value = aws_s3_bucket.events.id
}

output "events_bucket_arn" {
  value = aws_s3_bucket.events.arn
}

output "frontend_bucket_id" {
  value = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  value = aws_s3_bucket.frontend.arn
}

output "data_warehouse_bucket_id" {
  value = aws_s3_bucket.data_warehouse.id
}

output "data_processed_bucket_id" {
  value = aws_s3_bucket.data_processed.id
}
