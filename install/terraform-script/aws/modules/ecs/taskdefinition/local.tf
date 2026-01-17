locals {
  SERVICE_CONFIG = {
    WITH_PORT = [
      for service in var.SERVICE_CONFIG.WITH_PORT : {
        SERVICE_NAME   = service.SERVICE_NAME
        PORT           = service.PORT
        health_check   = service.health_check
        
      }
    ]

    WITHOUT_PORT = var.SERVICE_CONFIG.WITHOUT_PORT

    NATS = var.SERVICE_CONFIG.NATS
  }
}

locals {
  image_url  = "public.ecr.aws/ayanworks-technologies/credebl"
}

locals {
  SCHEMA_FILE_SERVICE_CONFIG = {
    SERVICE_NAME   = var.SCHEMA_FILE_SERVICE_CONFIG.SERVICE_NAME
    PORT           = var.SCHEMA_FILE_SERVICE_CONFIG.PORT
    file_system_id = var.schema_file_service_efs_id
    health_check   = var.SCHEMA_FILE_SERVICE_CONFIG.health_check
  }
}


     
     