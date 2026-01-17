output "repo_name" {
  value = aws_ecr_repository.ECR.name
}

output "repo_arn" {
  value = aws_ecr_repository.ECR.arn
}

output "repo_url" {
  value = aws_ecr_repository.ECR.repository_url
  
}