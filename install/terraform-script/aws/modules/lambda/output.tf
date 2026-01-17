# # Generate key-value pairs for output in the desired format
# locals {
#   seed_secrets_map = {
#     for service, secret in aws_secretsmanager_secret.seed_secrets :
#     "${service}_NKEY_SEED" => aws_secretsmanager_secret_version.seed_secrets_version[service].secret_string
#   }
# }

# # Output the key-value pairs
# output "seed_secrets_output" {
#   value = local.seed_secrets_map
# }

output "nats_seed_key" {
  value = local.services
}