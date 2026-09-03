variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking"
  type        = string
}

variable "hash_key_name" {
  description = "The name of the hash key in the index"
  type        = string
  default     = "LockID"
}

variable "hash_key_type" {
  description = "The type of the hash key (S, N, or B)"
  type        = string
  default     = "S"
}
