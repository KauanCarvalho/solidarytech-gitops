variable "cluster_id" {
  type = string
}

variable "description" {
  type = string
}

variable "node_type" {
  type    = string
  default = "cache.t3.micro"
}

variable "num_cache_clusters" {
  type    = number
  default = 1
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of VPC private subnet IDs"
}

variable "security_group_ids" {
  type        = list(string)
  description = "List of security group IDs governing the Redis cluster"
}
