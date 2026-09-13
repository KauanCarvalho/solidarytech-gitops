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


# ----- Bucket criado via AWS CLI, não via resource "aws_s3_bucket" -----
# O recurso nativo aws_s3_bucket SEMPRE chama GetObjectLockConfiguration ao
# ler o estado do bucket (create/refresh), e não tolera erro AccessDenied
# nessa chamada para a partition "aws" (só tolera NotFound/MethodNotAllowed/
# NotImplemented — ver internal/service/s3/bucket.go do provider). O AWS
# Academy Learner Lab bloqueia essa action via SCP com "explicit deny" a
# nível de Organização, o que não pode ser contornado por IAM. Por isso o
# bucket é criado por fora do provider aws, via AWS CLI.
resource "null_resource" "terraform_state_bucket" {
  triggers = {
    bucket_name = var.s3_bucket_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      if aws s3api head-bucket --bucket "${var.s3_bucket_name}" --region "${var.aws_region}" 2>/dev/null; then
        echo "Bucket ${var.s3_bucket_name} já existe, pulando criação."
      elif [ "${var.aws_region}" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "${var.s3_bucket_name}" --region "${var.aws_region}"
      else
        aws s3api create-bucket --bucket "${var.s3_bucket_name}" --region "${var.aws_region}" \
          --create-bucket-configuration LocationConstraint="${var.aws_region}"
      fi
    EOT
  }

  # Sem provisioner "when = destroy": o bucket de state não deve ser
  # apagado por um terraform destroy acidental (mesma intenção do antigo
  # lifecycle.prevent_destroy). Exclusão é manual/fora do Terraform.
}

resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = var.s3_bucket_name
  versioning_configuration {
    status = "Enabled"
  }

  depends_on = [null_resource.terraform_state_bucket]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_encryption" {
  bucket = var.s3_bucket_name

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.terraform_state_kms_key.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }

  depends_on = [null_resource.terraform_state_bucket]
}

resource "aws_s3_bucket_public_access_block" "terraform_state_block_public" {
  bucket                  = var.s3_bucket_name
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [null_resource.terraform_state_bucket]
}
