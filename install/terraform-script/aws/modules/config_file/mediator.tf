
resource "aws_s3_object" "mediator_env" {
  bucket = var.env_file_bucket_id
  key    = "${var.environment}-MEDIATOR.env"
  content = <<-EOT
POSTGRES_USER=${local.mediator_db_credentials.username}
USE_PUSH_NOTIFICATIONS=true
POSTGRES_HOST=${local.mediator_rds_proxy_credentials.endpoint}:${local.mediator_db_credentials.port}  
AGENT_NAME=${var.project_name}_mediator 
POSTGRES_PASSWORD=${local.mediator_db_credentials.password} 
WALLET_KEY=H<!F1BPhc*0E 
AGENT_ENDPOINTS=http://${var.alb_details["MEDIATOR"].dns} ,ws://${var.alb_details["MEDIATOR"].dns} 
POSTGRES_ADMIN_USER=${local.mediator_db_credentials.username}
AGENT_PORT=${var.SERVICE_CONFIG.WITH_PORT[3].PORT}
NOTIFICATION_WEBHOOK_URL=http://${var.alb_details["API_GATEWAY"].dns}/notification  
POSTGRES_ADMIN_PASSWORD=${local.mediator_db_credentials.password} 
WALLET_NAME="lower(${var.project_name})_mediator_db"
  EOT
}
