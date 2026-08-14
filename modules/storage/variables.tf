variable "name" {
  type = string
}

variable "domain" {
  type = string
}

variable "s3_media_bucket_name" {
  type = string
}

variable "wav_archive_after_days" {
  description = "Days after upload before a processed WAV original (tagged archive-tier=source by audio-processing) transitions to Glacier Deep Archive"
  type        = number
  default     = 3
}
