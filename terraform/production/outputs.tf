output "ecr_repository_urls" {
  description = "URLs of the created ECR repositories"
  value       = { for k, v in module.ecr_repositories : k => v.repository_url }
}

output "donation_sqs_url" {
  description = "The URL of the solidary-donations SQS queue"
  value       = module.donation_sqs.queue_url
}

output "donation_sqs_arn" {
  description = "The ARN of the solidary-donations SQS queue"
  value       = module.donation_sqs.queue_arn
}

output "volunteer_dynamodb_table_name" {
  description = "The name of the SolidaryTechVolunteers DynamoDB table"
  value       = module.volunteer_dynamodb.table_name
}

output "vpc_id" {
  description = "VPC ID of the main network"
  value       = module.vpc.vpc_id
}

output "eks_sg_id" {
  description = "Security Group ID where EKS nodes will be attached"
  value       = module.eks_sg.sg_id
}

output "ngo_db_connection_string" {
  description = "Postgres connection string for ngo-service-db"
  value       = "postgres://postgres:${var.db_password_ngo}@${module.rds_ngo.endpoint}/ngo_db?sslmode=require"
  sensitive   = true
}

output "donation_db_connection_string" {
  description = "Postgres connection string for donation-service-db"
  value       = "postgres://postgres:${var.db_password_donation}@${module.rds_donation.endpoint}/donation_db?sslmode=require"
  sensitive   = true
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster API Endpoint"
  value       = module.eks.cluster_endpoint
}

output "ingress_load_balancer_hostname" {
  value       = data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].hostname
  description = "The DNS name of the Ingress Load Balancer"
}
