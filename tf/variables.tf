variable "prefix" {
  description = "prefix for naming in this deployment"
  default     = "webapp-poc-demo"
}

variable "location" {
  description = "default location for all Azure resources if not specified otherwise"
  default     = "West Europe"
}
