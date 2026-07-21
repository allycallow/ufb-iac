variable "name" {
  type = string
}

variable "domain" {
  type = string
}

variable "media_bucket_domain_name" {
  type = string
}

variable "media_bucket_id" {
  type = string
}

variable "media_bucket_arn" {
  type = string
}

variable "frontend_bucket_id" {
  type = string
}

variable "frontend_bucket_arn" {
  type = string
}

variable "alb_dns_name" {
  type = string
}

variable "media_public_key_pem" {
  type = string
}

variable "preview_public_key_pem" {
  type = string
}

variable "viewer_response_lambda_arn" {
  type = string
}

variable "viewer_request_lambda_arn" {
  type = string
}

variable "origin_response_lambda_arn" {
  type = string
}
