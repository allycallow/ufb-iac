resource "aws_elasticsearch_domain" "main" {
  domain_name = local.name

  elasticsearch_version = "7.10"

  cluster_config {
    instance_type  = "t3.small.elasticsearch"
    instance_count = 1
  }

  vpc_options {
    security_group_ids = [module.security_group_open_search.security_group_id]
    subnet_ids         = [module.vpc.private_subnets[0]]
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 10
    volume_type = "gp2"
  }

  advanced_options = {
    "rest.action.multi.allow_explicit_index" = "true"
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
  value = aws_elasticsearch_domain.main.endpoint
}
