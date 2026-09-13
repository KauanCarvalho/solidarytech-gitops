resource "aws_kms_key" "terraform_state_kms_key" {
  description             = "KMS key for Terraform state S3 bucket encryption"
  deletion_window_in_days = 10

  tags = {
    Name        = "${var.s3_bucket_name}-kms-key"
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "terraform"
  }
}

resource "aws_kms_alias" "terraform_state_kms_alias" {
  name          = "alias/${var.s3_bucket_name}-key"
  target_key_id = aws_kms_key.terraform_state_kms_key.key_id
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = var.s3_bucket_name
  # Evita que o provider tente ler a configuração de Object Lock do bucket:
  # o AWS Academy Learner Lab bloqueia s3:GetBucketObjectLockConfiguration
  # via SCP com "explicit deny", o que faz o apply falhar mesmo sem o
  # projeto usar Object Lock.
  object_lock_enabled = false

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = var.s3_bucket_name
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_encryption" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.terraform_state_kms_key.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state_block_public" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
