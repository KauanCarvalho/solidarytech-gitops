variable "queue_name" {
  description = "The name of the SQS queue"
  type        = string
}

variable "receive_wait_time_seconds" {
  description = "The time for which a ReceiveMessage call will wait for a message to arrive (enabling long-polling)"
  type        = number
  default     = 0
}

variable "visibility_timeout_seconds" {
  description = "The visibility timeout for the queue"
  type        = number
  default     = 30
}
