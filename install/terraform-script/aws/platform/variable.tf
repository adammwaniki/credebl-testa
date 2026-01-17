# aws credentials
variable "profile" {}
variable "project_name" {}
variable "environment" {}

# vpc credentials
variable "region" {}
variable "vpc_cidr" {}
variable "public_subnet_cidr" {
  type = list(string)
}
variable "private_app_subnet_cidr" {
  type = list(string)
}

variable "private_db_subnet_cidr" {
  type = list(string)
}

variable "SENDGRID_API_KEY" {}
variable "AWS_ACCOUNT_ID" {}


#db info
variable "aries_db" {}
variable "platform_db" {}
variable "crypto_private_key" {}
variable "platform_seed" {}
variable "PLATFORM_WALLET_PASSWORD" {} 