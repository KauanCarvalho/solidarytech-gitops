output "state_bucket_id" {
  description = "The name of the S3 bucket for Terraform state"
  value       = module.s3.bucket_id
}

output "state_bucket_arn" {
  description = "The ARN of the S3 bucket for Terraform state"
  value       = module.s3.bucket_arn
}

output "kms_key_arn" {
  description = "The ARN of the KMS key used for S3 encryption"
  value       = module.s3.kms_key_arn
}

output "lock_table_name" {
  description = "The name of the DynamoDB state lock table"
  value       = module.dynamodb.table_name
}

output "lock_table_arn" {
  description = "The ARN of the DynamoDB state lock table"
  value       = module.dynamodb.table_arn
}
