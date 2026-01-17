variable "region" {
  type    = string
  default = "us-east-1"
}
variable "project_name" {}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}


variable "public_subnet_cidr" {
  type        = list(string)
  description = "Public subnet CIDR "
  # default     = ["10.0.1.0/24", "10.0.2.0/24"]
}



variable "private_app_subnet_cidr" {
  type        = list(string)
  description = "Private subnet CIDR"
  # default     = ["10.0.2.0/24", "10.0.4.0/24"]
}




variable "private_db_subnet_cidr" {
  type        = list(string)
  description = "Private subnet CIDR"
  # default     = ["10.0.5.0/24", "10.0.6.0/24"]
}



variable "environment" {}

