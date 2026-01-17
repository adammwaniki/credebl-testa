resource "aws_s3_bucket" "env_file_bucket" {
  bucket = lower("${var.project_name}-${var.environment}-env-file-bucket")

  tags = {
    Name    = "env_file_storage"
    Project = var.project_name
  }

}
