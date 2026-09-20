output "bucket_id" {
  value = aws_s3_bucket.this.id
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "receiver_url" {
  description = "Register this as the Web Receiver URL in the Google Cast SDK Developer Console"
  value       = "https://${aws_cloudfront_distribution.this.domain_name}/index.html"
}
