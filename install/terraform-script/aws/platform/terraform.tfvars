# Generic Variables
region       = "region"
project_name = "TEST"
environment  = "DEV"
profile = "aws profile"


# VPC Variables
vpc_cidr                = "10.0.0.0/16"
public_subnet_cidr      = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnet_cidr = ["10.0.3.0/24", "10.0.4.0/24"]
private_db_subnet_cidr  = ["10.0.5.0/24", "10.0.6.0/24"]



SENDGRID_API_KEY = "sendgrid-key"
AWS_ACCOUNT_ID  = "account_id"


# databse info
aries_db = "db.t3.medium" 
platform_db = "db.t3.medium"
crypto_private_key = "generate key using https://generate-random.org/encryption-key-generator?count=2&bytes=32&cipher=aes-256-cbc&string=&password= key must be same in api-gateway and frontend env file"
platform_seed = "xxxxxxxxx" 
PLATFORM_WALLET_PASSWORD = "xxxxxxxxx Provide any random key"