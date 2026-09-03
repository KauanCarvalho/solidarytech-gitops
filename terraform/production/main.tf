module "ecr_repositories" {
  source   = "../modules/aws/ecr"
  for_each = toset(var.microservices)

  repository_name = "solidarytech-${each.key}"
}

module "volunteer_dynamodb" {
  source              = "../modules/aws/dynamodb"
  dynamodb_table_name = "SolidaryTechVolunteers"
  hash_key_name       = "volunteer_id"
}

module "donation_sqs" {
  source                     = "../modules/aws/sqs"
  queue_name                 = "solidary-donations"
  receive_wait_time_seconds  = 20
  visibility_timeout_seconds = 60
}

module "vpc" {
  source   = "../modules/aws/vpc"
  vpc_name = "solidarytech-vpc"
  vpc_cidr = "10.0.0.0/16"
}

module "eks_sg" {
  source      = "../modules/aws/sg"
  sg_name     = "solidarytech-eks-sg"
  description = "Security group for EKS nodes"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_db_subnet_group" "rds" {
  name       = "solidarytech-rds-subnets"
  subnet_ids = module.vpc.private_subnets
}

module "rds_sg" {
  source      = "../modules/aws/sg"
  sg_name     = "solidarytech-rds-sg"
  description = "Security group for PostgreSQL RDS instances"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_security_group_rule" "rds_inbound_from_vpc" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = module.rds_sg.sg_id
  cidr_blocks       = ["10.0.0.0/16"]
  description       = "Allow traffic to RDS from VPC (EKS nodes)"
}

module "rds_ngo" {
  source             = "../modules/aws/rds"
  db_identifier      = "ngo-service-db"
  db_name            = "ngo_db"
  password           = var.db_password_ngo
  subnet_group_name  = aws_db_subnet_group.rds.name
  security_group_ids = [module.rds_sg.sg_id]
}

module "rds_donation" {
  source             = "../modules/aws/rds"
  db_identifier      = "donation-service-db"
  db_name            = "donation_db"
  password           = var.db_password_donation
  subnet_group_name  = aws_db_subnet_group.rds.name
  security_group_ids = [module.rds_sg.sg_id]
  # Caminho crítico: backups automáticos diários com retenção de 7 dias,
  # janela alinhada ao backup diário do Velero (03:00 UTC) — RPO documentado
  # em docs/PCN.md. rds_ngo fica sem isso (não é hot path e RPO frouxo é
  # aceitável, evita custo/complexidade desnecessária).
  backup_retention_period = 7
}

data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

module "eks" {
  source         = "../modules/aws/eks"
  cluster_name   = "solidarytech-cluster"
  role_arn       = data.aws_iam_role.lab_role.arn
  subnet_ids     = module.vpc.public_subnets
  eks_sg_id      = module.eks_sg.sg_id
  instance_types = ["t3.medium"]
  desired_size   = 3
  max_size       = 4
  min_size       = 2
}
