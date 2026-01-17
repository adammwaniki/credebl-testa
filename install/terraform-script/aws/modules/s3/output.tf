
# extracting bucket name 
output "env_file_bucket_id" {
  value = aws_s3_bucket.env_file_bucket.id

}

output "link_bucket_id" {
  value = aws_s3_bucket.url_link_bucket.id

}

output "org_logo_bucket_id" {

  value = aws_s3_bucket.organization_logo_store_bucket.id
}

output "env_file_bucket_arn" {
  value = aws_s3_bucket.env_file_bucket.arn
}

output "org_logo_bucket_arn" {
  value = aws_s3_bucket.env_file_bucket.arn
}

output "link_bucket_arn" {
  value = aws_s3_bucket.url_link_bucket.arn
}

output "org_logo_bucket_dns" {
  value = aws_s3_bucket.organization_logo_store_bucket.bucket_domain_name
}
