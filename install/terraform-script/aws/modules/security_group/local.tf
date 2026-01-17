locals {
  EFS_PORT = 2049
}

locals {
  REDIS_CONFIG = {

    SERVICE_NAME   = "REDIS"
    PORT           = 6379
    file_system_id = ""

  }
}
