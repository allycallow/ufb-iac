variable "name" {
  description = "Prefix for the names of resources created in this module"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
