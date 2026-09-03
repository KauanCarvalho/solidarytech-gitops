output "bucket_id" {
  description = "The ID (name) of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = aws_s3_bucket.terraform_state.arn
}

output "kms_key_arn" {
  description = "The ARN of the KMS key used for bucket encryption"
  value       = aws_kms_key.terraform_state_kms_key.arn
}
