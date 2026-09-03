output "repository_url" {
  description = "The URL of the created ECR repository"
  value       = aws_ecr_repository.ecr_repo.repository_url
}

output "repository_name" {
  description = "The name of the created ECR repository"
  value       = aws_ecr_repository.ecr_repo.name
}
