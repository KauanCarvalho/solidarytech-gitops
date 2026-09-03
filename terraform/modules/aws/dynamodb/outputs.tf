output "table_name" {
  description = "The name of the DynamoDB state lock table"
  value       = aws_dynamodb_table.terraform_state_lock.name
}

output "table_arn" {
  description = "The ARN of the DynamoDB state lock table"
  value       = aws_dynamodb_table.terraform_state_lock.arn
}
