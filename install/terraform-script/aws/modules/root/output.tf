output "profile" {
  description = "The AWS profile being used"
  value       = var.profile
}

output "project_name" {
  description = "The name of the project"
  value       = var.project_name
}

output "environment" {
  description = "The deployment environment (e.g., dev, prod)"
  value       = var.environment
}

output "region" {
  description = "The AWS region where the resources are deployed"
  value       = var.region
}

output "vpc_cidr" {
  description = "The CIDR block for the VPC"
  value       = var.vpc_cidr
}

output "public_subnet_cidr" {
  description = "The CIDR blocks for the public subnets"
  value       = var.public_subnet_cidr
}

output "private_app_subnet_cidr" {
  description = "The CIDR blocks for the private application subnets"
  value       = var.private_app_subnet_cidr
}

output "private_db_subnet_cidr" {
  description = "The CIDR blocks for the private database subnets"
  value       = var.private_db_subnet_cidr
}

output "sendgrid_api_key" {
  description = "The SendGrid API Key for email services"
  value       = var.SENDGRID_API_KEY
  sensitive   = true
}

output "aws_account_id" {
  description = "The AWS account ID"
  value       = var.AWS_ACCOUNT_ID
}

output "SERVICE_CONFIG" {
  value = var.SERVICE_CONFIG
}


output "SCHEMA_FILE_SERVICE_CONFIG" {
  value = var.SCHEMA_FILE_SERVICE_CONFIG
}

output "AGENT_PROVISIONING_SERVICE" {
  value = var.AGENT_PROVISIONING_SERVICE
}

output "ALB_SG" {
  value = var.ALB_SG
}
output "platform_db" {
  value = var.platform_db
}
output "aries_db" {
  value = var.aries_db
}

output "crypto_private_key" {
  value = var.crypto_private_key
}

output "platform_seed" {
  value = var.platform_seed
}

output "PLATFORM_WALLET_PASSWORD" {
  value = var.PLATFORM_WALLET_PASSWORD
}