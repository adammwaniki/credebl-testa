resource "aws_ecr_lifecycle_policy" "tagged_image_policy" {
  repository = aws_ecr_repository.ECR.name

  count = length(distinct(local.image_tags))

  policy = jsonencode({
    rules = [
      for i in range(length(distinct(local.image_tags))) : {
        rulePriority = i + 1
        description  = "Keep last 30 images for tag ${distinct(local.image_tags)[i]}"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = [distinct(local.image_tags)[i]]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}