output "cf_media_key_id" {
  value = aws_cloudfront_public_key.cf_media_key.id
}

output "cf_preview_key_id" {
  value = aws_cloudfront_public_key.cf_preview_key.id
}

output "cf_media_keygroup_id" {
  value = aws_cloudfront_key_group.cf_media_keygroup.id
}

output "cloudfront_dist_media_id" {
  value = aws_cloudfront_distribution.media.id
}

output "media_cf_url" {
  value = "https://${aws_cloudfront_distribution.media.domain_name}"
}

output "media_oai_iam_arn" {
  value = aws_cloudfront_origin_access_identity.media.iam_arn
}

output "frontend_oai_iam_arn" {
  value = aws_cloudfront_origin_access_identity.frontend.iam_arn
}
