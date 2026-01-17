locals {
  private_route_table_ids = [var.private_db_route_table_id, var.private_app_route_table_id]
}
