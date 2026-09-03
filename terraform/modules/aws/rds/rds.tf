resource "aws_db_instance" "this" {
  identifier                  = var.db_identifier
  engine                      = "postgres"
  engine_version              = "16"
  instance_class              = var.instance_class
  allocated_storage           = 20
  db_name                     = var.db_name
  username                    = "postgres"
  password                    = var.password
  port                        = 5432
  publicly_accessible         = false
  multi_az                    = false
  db_subnet_group_name        = var.subnet_group_name
  vpc_security_group_ids      = var.security_group_ids
  skip_final_snapshot         = true
  apply_immediately           = true
  allow_major_version_upgrade = false
  auto_minor_version_upgrade  = true
  backup_retention_period     = var.backup_retention_period

  tags = {
    Name        = var.db_identifier
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "terraform"
  }
}
