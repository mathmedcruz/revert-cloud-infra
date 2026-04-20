variable "app_name" {
  type        = string
  description = "Application or project name. Used as the Application tag."
}

variable "environment" {
  type        = string
  description = "Deployment environment (e.g. dev, itg, prod). Used as the Environment tag."
}

variable "custom_tags" {
  type        = map(string)
  description = "Extra tags to merge on top of the defaults. Overrides defaults on key collision."
  default     = {}
}
