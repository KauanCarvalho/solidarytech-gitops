output "bucket_id" {
  description = "The ID (name) of the S3 bucket"
  value       = var.s3_bucket_name
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket"
  value       = "arn:aws:s3:::${var.s3_bucket_name}"
}

output "kms_key_arn" {
  description = "The ARN of the KMS key used for bucket encryption"
  value       = aws_kms_key.terraform_state_kms_key.arn
}
