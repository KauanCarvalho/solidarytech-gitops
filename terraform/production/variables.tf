variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "microservices" {
  description = "Lista dos nomes dos microsserviços para criação dos ECRs"
  type        = list(string)
}

variable "db_password_ngo" {
  type        = string
  sensitive   = true
  description = "Password for the NGO DB"
}

variable "db_password_donation" {
  type        = string
  sensitive   = true
  description = "Password for the Donation DB"
}

variable "aws_access_key" {
  description = "AWS Access Key for Lab credentials"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS Secret Key for Lab credentials"
  type        = string
  sensitive   = true
}

variable "aws_session_token" {
  description = "AWS Session Token for Lab credentials"
  type        = string
  sensitive   = true
}

variable "datadog_api_key" {
  description = "Datadog API Key"
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog Application Key"
  type        = string
  sensitive   = true
}

variable "discord_webhook_url" {
  description = "Discord Webhook URL for ChatOps alerts"
  type        = string
  sensitive   = true
}

variable "pagerduty_integration_key" {
  description = "PagerDuty Integration Key for incident alerts"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_dispatch_token" {
  description = "GitHub PAT (repo scope, ou fine-grained com Contents: read/write) usado pela Lambda de self-healing para chamar o endpoint repository_dispatch do solidarytech-app"
  type        = string
  sensitive   = true
}

variable "self_healing_webhook_token" {
  description = "Token compartilhado (gerado manualmente, ex.: openssl rand -hex 32) para validar que a chamada ao webhook de self-healing veio do Alertmanager"
  type        = string
  sensitive   = true
}
