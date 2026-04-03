resource "aws_opensearch_domain" "main" {
  domain_name    = "ufb-production"
  engine_version = "OpenSearch_2.11"

  cluster_config {
    instance_type  = "t3.small.search"
    instance_count = 1
  }

  vpc_options {
    security_group_ids = [module.security_group_open_search.security_group_id]
    subnet_ids         = [module.vpc.private_subnets[0]]
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
    volume_type = "gp3"
    iops        = 3000
    throughput  = 125
  }

  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
    "indices.fielddata.cache.size"           = "20"
    "indices.query.bool.max_clause_count"    = "1024"
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-PFS-2023-10"
  }
}

output "opensearch_domain_endpoint" {
  value = aws_opensearch_domain.main.endpoint
}
