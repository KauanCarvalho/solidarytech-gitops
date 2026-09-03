resource "aws_secretsmanager_secret" "db_ngo" {
  name = "solidarytech/ngo/db_url"
}

resource "aws_secretsmanager_secret_version" "db_ngo" {
  secret_id     = aws_secretsmanager_secret.db_ngo.id
  secret_string = "postgres://postgres:${var.db_password_ngo}@${module.rds_ngo.endpoint}/${module.rds_ngo.db_name}"
}

resource "aws_secretsmanager_secret" "db_donation" {
  name = "solidarytech/donation/db_url"
}

resource "aws_secretsmanager_secret_version" "db_donation" {
  secret_id     = aws_secretsmanager_secret.db_donation.id
  secret_string = "postgres://postgres:${var.db_password_donation}@${module.rds_donation.endpoint}/${module.rds_donation.db_name}"
}

resource "aws_secretsmanager_secret" "donation_sqs_url" {
  name = "solidarytech/donation/sqs_url"
}

resource "aws_secretsmanager_secret_version" "donation_sqs_url" {
  secret_id     = aws_secretsmanager_secret.donation_sqs_url.id
  secret_string = module.donation_sqs.queue_url
}

resource "aws_secretsmanager_secret" "donation_access_key" { name = "solidarytech/donation/access_key" }
resource "aws_secretsmanager_secret_version" "donation_access_key" {
  secret_id     = aws_secretsmanager_secret.donation_access_key.id
  secret_string = var.aws_access_key
}

resource "aws_secretsmanager_secret" "donation_secret_key" { name = "solidarytech/donation/secret_key" }
resource "aws_secretsmanager_secret_version" "donation_secret_key" {
  secret_id     = aws_secretsmanager_secret.donation_secret_key.id
  secret_string = var.aws_secret_key
}

resource "aws_secretsmanager_secret" "donation_session_token" { name = "solidarytech/donation/session_token" }
resource "aws_secretsmanager_secret_version" "donation_session_token" {
  secret_id     = aws_secretsmanager_secret.donation_session_token.id
  secret_string = var.aws_session_token
}

resource "aws_secretsmanager_secret" "volunteer_access_key" { name = "solidarytech/volunteer/access_key" }
resource "aws_secretsmanager_secret_version" "volunteer_access_key" {
  secret_id     = aws_secretsmanager_secret.volunteer_access_key.id
  secret_string = var.aws_access_key
}

resource "aws_secretsmanager_secret" "volunteer_secret_key" { name = "solidarytech/volunteer/secret_key" }
resource "aws_secretsmanager_secret_version" "volunteer_secret_key" {
  secret_id     = aws_secretsmanager_secret.volunteer_secret_key.id
  secret_string = var.aws_secret_key
}

resource "aws_secretsmanager_secret" "volunteer_session_token" { name = "solidarytech/volunteer/session_token" }
resource "aws_secretsmanager_secret_version" "volunteer_session_token" {
  secret_id     = aws_secretsmanager_secret.volunteer_session_token.id
  secret_string = var.aws_session_token
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [module.eks]
}

resource "kubernetes_secret_v1" "aws_creds" {
  metadata {
    name      = "aws-creds"
    namespace = "external-secrets"
  }

  data = {
    access-key    = var.aws_access_key
    secret-key    = var.aws_secret_key
    session-token = var.aws_session_token
  }

  depends_on = [helm_release.external_secrets]
}
