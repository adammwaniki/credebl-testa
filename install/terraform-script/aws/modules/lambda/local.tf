locals {
  cluster_count = var.nats_count
  cluster_ips = [
    for i in range(local.cluster_count) : format(
      "nats://nats-%d-%d.%s-namespace:%d",
      i + 1,
      var.SERVICE_CONFIG.NATS.PORT[3],                                    # Index for each NATS instance (7, 2, ...)
      lower(replace("${var.environment}-${var.project_name}", "_", "-")), # Cluster name with "_" replaced by "-"
      var.SERVICE_CONFIG.NATS.PORT[3]                                     # The desired port from the service config
    )
  ]
}

locals {
  services = [
   "USER_SERVICE",
    "API_GATEWAY_SERVICE",
    "ORGANIZATION_SERVICE",
    "AGENT_PROVISIONING_SERVICE",
    "AGENT_SERVICE_SERVICE",
    "VERIFICATION_SERVICE",
    "LEDGER_SERVICE",
    "ISSUANCE_SERVICE",
    "CONNECTION_SERVICE",
    "ECOSYSTEM_SERVICE",
    "CREDENTAILDEFINITION_SERVICE",
    "SCHEMA_SERVICE",
    "WEBHOOK_SERVICE",
    "UTILITIES_SERVICE",
    "NOTIFICATION_SERVICE",
    "GEOLOCATION_SERVICE",
    "CLOUD_WALLET_SERVICE"
  ]
}

