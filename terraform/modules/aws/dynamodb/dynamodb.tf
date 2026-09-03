resource "aws_dynamodb_table" "terraform_state_lock" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = var.hash_key_name

  attribute {
    name = var.hash_key_name
    type = var.hash_key_type
  }

  tags = {
    Name        = var.dynamodb_table_name
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "terraform"
  }
}
