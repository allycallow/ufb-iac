variable "s3_media_bucket_name" {
  type    = string
  default = "production-ufb-media"
}

variable "viewer_response_lambda_arn" {
  type    = string
  default = "arn:aws:lambda:us-east-1:081077757258:function:production-ufb-view-response:2"
}

variable "viewer_request_lambda_arn" {
  type    = string
  default = "arn:aws:lambda:us-east-1:081077757258:function:production-ufb-reviewer-request:6"
}

variable "origin_response_lambda_arn" {
  type    = string
  default = "arn:aws:lambda:us-east-1:081077757258:function:production-ufb-origin-response:66"
}

variable "google_client_id" {
  type    = string
  default = "804352256211-0ftsmn9fpvuje9v9t3v3cqhmga1v55sp.apps.googleusercontent.com"
}

variable "google_client_secret" {
  type    = string
  default = "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"
}

variable "apple_client_id" {
  type    = string
  default = "com.upfrontbeats.ufb"
}

variable "apple_team_id" {
  type    = string
  default = "7P673D9XNB"
}

variable "apple_key_id" {
  type    = string
  default = "GJ4TSYR776"
}

variable "apple_private_key" {
  type        = string
  description = "Contents of Apple private key (.p8) file"
  default     = "=-----BEGIN PRIVATE KEY-----\nMIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQgzb2UPrW7HuYc2CSu\nHXFBP1c3GPSYN+N8jBGzFz5k4oagCgYIKoZIzj0DAQehRANCAAQZNVmm6v39ic1E\nMN3Km8Qnxu2RRRbMnqv14h53fgmnj+Vmr+eKzeZubUb/WQLm7D+Fpz7hr+iyWIra\ns16Hnrxp\n-----END PRIVATE KEY-----"
}
