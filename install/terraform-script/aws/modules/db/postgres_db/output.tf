

output "database_info_by_service" {
  value = {
    for db, config in aws_db_instance.rds_instance : lower(db) => {
      endpoint = config.address
      db_name  = config.db_name
      username = config.username
      password = random_string.db_passwords[db].result
      port     = config.port
    }
  }
  description = "Database connection details organized by service name"
  sensitive   = true
}


output "rds_proxy_info_by_service" {
  value = {
    for db, config in aws_db_proxy.rds_proxy : lower(db) => {
      endpoint = config.endpoint
    }
  }
  description = "Database connection details organized by service name"
  sensitive   = true
}
