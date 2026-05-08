resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.eu-west-2.dynamodb"
  vpc_endpoint_type   = "Gateway"
  route_table_ids     = module.vpc.private_route_table_ids
  private_dns_enabled = false
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.eu-west-2.s3"
  vpc_endpoint_type   = "Gateway"
  route_table_ids     = module.vpc.private_route_table_ids
  private_dns_enabled = false
}
