resource "aws_service_discovery_http_namespace" "cluster_namespace" {
  name = lower(replace("${var.environment}-${var.project_name}-namespace", "_", "-"))  # Use cluster name, not ID
  description = "Service discovery for ${var.project_name} in ${var.environment}"
}
