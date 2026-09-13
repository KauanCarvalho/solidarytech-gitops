variable "s3_bucket_name" {
  description = "Name of the S3 bucket to store Terraform state files"
  type        = string
}

variable "aws_region" {
  description = "AWS region where the state bucket is created (usado pelo AWS CLI no null_resource)"
  type        = string
}
