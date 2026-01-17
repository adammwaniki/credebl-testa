data "external" "generate_jwt_secret" {
  program = ["bash", "${path.module}/generate_jwt_secret.sh"]
}

resource "aws_s3_object" "schema_file_server_env" {
    bucket = var.env_file_bucket_id
    key    = "${var.environment}-${var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME}.env"
  content = <<-EOT
    APP_PORT=${var.SCHEMA_FILE_SERVICE_CONFIG.PORT}
    # Dynamically generated JWT Token Secret
    JWT_TOKEN_SECRET=${data.external.generate_jwt_secret.result.jwt_token_secret}
    ISSUER=${var.project_name}
  EOT
}



