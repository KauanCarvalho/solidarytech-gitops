resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.cluster_id}-subnets"
  subnet_ids = var.subnet_ids
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = var.cluster_id
  description                = var.description
  node_type                  = var.node_type
  port                       = 6379
  automatic_failover_enabled = false
  num_cache_clusters         = var.num_cache_clusters
  engine_version             = "7.1"
  parameter_group_name       = "default.redis7"
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = var.security_group_ids

  tags = {
    Name        = var.cluster_id
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
    ManagedBy   = "terraform"
  }
}
