data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.s3_bucket_name}-${data.aws_caller_identity.current.account_id}"
}

module "s3" {
  source         = "../modules/aws/s3"
  s3_bucket_name = local.bucket_name
}

module "dynamodb" {
  source              = "../modules/aws/dynamodb"
  dynamodb_table_name = var.dynamodb_table_name
}
