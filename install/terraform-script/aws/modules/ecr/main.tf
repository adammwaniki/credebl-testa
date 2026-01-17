resource "aws_ecr_repository" "ECR" {
  name = "${lower(var.project_name)}-${lower(var.environment)}-repo"  # Example name with lowercase and valid characters

  tags = {
    Name        = "${var.project_name}-${var.environment}-ECR"
    Environment = var.environment
  }
}
