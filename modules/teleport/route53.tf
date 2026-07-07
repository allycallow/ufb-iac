resource "aws_route53_record" "teleport" {
  zone_id = var.zone_id
  name    = var.public_addr
  type    = "A"

  alias {
    name                   = aws_lb.teleport.dns_name
    zone_id                = aws_lb.teleport.zone_id
    evaluate_target_health = true
  }
}
