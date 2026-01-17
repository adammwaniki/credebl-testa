
output "database_info_by_service" {
  value = module.postgres_db.database_info_by_service
}

output "rds_proxy_info_by_service" {
  value = module.postgres_db.rds_proxy_info_by_service
}