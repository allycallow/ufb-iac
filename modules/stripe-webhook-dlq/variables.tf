variable "stage" {
  description = "Deployment stage, matches serverless.yml's opt:stage (defaults to 'dev' there)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
