variable "name" {
  type        = string
  description = "ECR repository name."
}

variable "image_tag_mutability" {
  type        = string
  default     = "MUTABLE"
  description = "MUTABLE or IMMUTABLE. Keep MUTABLE when CI overrides the `latest` tag."
}

variable "scan_on_push" {
  type        = bool
  default     = true
  description = "Enable image vulnerability scanning when an image is pushed."
}

variable "force_delete" {
  type        = bool
  default     = true
  description = "Force delete the repository even if it contains images. Set false in prod once established."
}

variable "tags" {
  type    = map(string)
  default = {}
}
