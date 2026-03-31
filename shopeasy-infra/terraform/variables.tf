variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "admin"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "shopeasy_dev"
}
