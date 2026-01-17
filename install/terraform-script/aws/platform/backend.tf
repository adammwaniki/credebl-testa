# store the terraform state file in s3
terraform {
  backend "s3" {
    bucket = "s3 bucket name"
    key    = "file.tfstate"
    region = "region"
  }
}