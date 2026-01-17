# Generate an IAM policy document for the ECS task role
data "aws_iam_policy_document" "ecs_task_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Create the IAM role for ECS tasks
resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.project_name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_role_policy.json
}

# Define a custom policy with necessary permissions for ECS tasks
data "aws_iam_policy_document" "ecs_task_permissions_policy" {
  statement {
    actions = [
      # Permissions for ECS and Cluster Management
      "ecs:CreateCluster",
      "ecs:DescribeClusters",
      "ecs:RegisterTaskDefinition",
      "ecs:RunTask",
      "ecs:UpdateService",
      "ecs:DescribeTasks",

      # Permissions for S3 Access
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",

      # Permissions for EC2 Auto Scaling
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:UpdateAutoScalingGroup",

      # Permissions for Load Balancing
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",

      # Database Access - Adjust based on your DB type
      "rds:DescribeDBInstances",
      "rds:Connect"
    ]
    resources = ["*"]
  }
}

# Attach custom policy to the IAM role
resource "aws_iam_policy" "ecs_task_policy" {
  name   = "${var.project_name}-ecs-task-policy"
  policy = data.aws_iam_policy_document.ecs_task_permissions_policy.json
}

# Create a map for attaching policies to the ECS task role
resource "aws_iam_role_policy_attachment" "ecs_task_role_attachment" {
  for_each = {
    "custom_policy" = aws_iam_policy.ecs_task_policy.arn
    "admin_access"  = "arn:aws:iam::aws:policy/AdministratorAccess"
  }

  role       = aws_iam_role.ecs_task_role.name
  policy_arn = each.value
}
