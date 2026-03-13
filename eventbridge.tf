module "eventbridge" {
  source   = "terraform-aws-modules/eventbridge/aws"
  bus_name = local.name
  rules    = {}
  targets  = {}
}

output "eventbridge_bus_name" {
  value = module.eventbridge.eventbridge_bus_name
}
