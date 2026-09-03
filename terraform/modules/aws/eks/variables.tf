variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "role_arn" {
  type        = string
  description = "ARN of the IAM Role (e.g., AWS Academy LabRole) used by the cluster and node groups"
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of VPC Subnet IDs for EKS"
}

variable "eks_sg_id" {
  type        = string
  description = "Security Group ID of the EKS nodes"
}

variable "instance_types" {
  type        = list(string)
  default     = ["t3.medium"]
  description = "Instance types for the EKS nodes"
}

variable "desired_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 3
}

variable "min_size" {
  type    = number
  default = 1
}
