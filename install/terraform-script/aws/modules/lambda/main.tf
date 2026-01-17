resource "aws_lambda_function" "nats_config_lambda" {
  function_name = "natsConfigWriter"
  runtime       = "python3.8"
  handler       = "lambda_function.lambda_handler"
  role          = aws_iam_role.lambda_role.arn
  memory_size   = 128

  filename         = "${path.module}/lambda.zip" # Ensure this ZIP file is correct
  source_code_hash = filebase64sha256("${path.module}/lambda.zip")

  file_system_config {
    arn              = var.nats_efs_access_point_arn
    local_mount_path = "/mnt/efs" # Mount EFS root
  }

  vpc_config {
    subnet_ids         = var.private_app_subnet_ids
    security_group_ids = values(var.nats_security_group_ids)
  }

  environment {
    variables = {
      FILE_PATH   = "/mnt/efs/nats.config", # Root location in EFS
      CLUSTER_IPS = join(",", local.cluster_ips),
      ENVIRONMENT = var.environment,
      SERVICES    = join(",", [for service in local.services : "${service}_NKEY"])
    }
  }

#  environment {
#     variables = merge(
#       {
#         FILE_PATH   = "/mnt/efs/nats.config", # Root location in EFS
#         CLUSTER_IPS = join(",", local.cluster_ips),
#         ENVIRONMENT = var.environment
#       },
#        {
#         for s in local.services : 
#         "${s}_NKEY"     => data.aws_secretsmanager_secret.service_pub_keys[s].secret_string
#       }
#     )
#   }
  lifecycle {
    # Ensure that the Lambda function is recreated when the file changes
    create_before_destroy = true
    ignore_changes        = [filename] # Ignore changes to 'filename' for state consistency
  }

  depends_on = [null_resource.generate_nkeys]
}



