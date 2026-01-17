resource "aws_db_subnet_group" "db_sg_group" {
  name       = lower("${var.project_name}-${var.environment}-sg-group") 
  subnet_ids = var.private_db_subnet_ids 

  tags = {
    Name        = "${var.project_name}-${var.environment}-sg-group"
    Environment = var.environment
    Project     = var.project_name
  }
}
