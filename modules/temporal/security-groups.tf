# ──────────────────────────────────────────────────────────────────────────────
# Security groups
#
# Unlike the other service modules, these are declared here rather than left to
# terraform-aws-modules/ecs//modules/service. The four Temporal server roles
# must reach *each other* on the ringpop membership and gRPC ports, and four
# module-created groups cross-referencing one another would be a dependency
# cycle. One shared group with self-referencing rules is both correct and
# simpler to reason about.
#
# The existing RDS group (modules/networking.security_group_rds) already allows
# 5432 from the whole VPC CIDR, so no database rules are added here.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_security_group" "server" {
  name        = "${var.name}-server"
  description = "Temporal server roles: frontend, history, matching, internal worker"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-server" })

  lifecycle {
    create_before_destroy = true
  }
}

# Ringpop gossip between server tasks. Membership is discovered through the
# cluster_membership table, then peers dial each other directly on these ports.
resource "aws_vpc_security_group_ingress_rule" "server_membership_self" {
  security_group_id            = aws_security_group.server.id
  referenced_security_group_id = aws_security_group.server.id
  ip_protocol                  = "tcp"
  from_port                    = var.server_membership_port_range.from
  to_port                      = var.server_membership_port_range.to
  description                  = "Ringpop membership between Temporal server tasks"
}

# Role-to-role gRPC: frontend -> history/matching, history -> matching, etc.
resource "aws_vpc_security_group_ingress_rule" "server_grpc_self" {
  security_group_id            = aws_security_group.server.id
  referenced_security_group_id = aws_security_group.server.id
  ip_protocol                  = "tcp"
  from_port                    = var.server_grpc_port_range.from
  to_port                      = var.server_grpc_port_range.to
  description                  = "Internal gRPC between Temporal server roles"
}

resource "aws_vpc_security_group_ingress_rule" "server_frontend_from_worker" {
  security_group_id            = aws_security_group.server.id
  referenced_security_group_id = aws_security_group.worker.id
  ip_protocol                  = "tcp"
  from_port                    = local.frontend_grpc_port
  to_port                      = local.frontend_grpc_port
  description                  = "Long-poll from the Python worker fleet"
}

resource "aws_vpc_security_group_ingress_rule" "server_frontend_from_ui" {
  security_group_id            = aws_security_group.server.id
  referenced_security_group_id = aws_security_group.ui.id
  ip_protocol                  = "tcp"
  from_port                    = local.frontend_grpc_port
  to_port                      = local.frontend_grpc_port
  description                  = "Web UI to frontend gRPC"
}

resource "aws_vpc_security_group_ingress_rule" "server_frontend_from_schema" {
  security_group_id            = aws_security_group.server.id
  referenced_security_group_id = aws_security_group.schema.id
  ip_protocol                  = "tcp"
  from_port                    = local.frontend_grpc_port
  to_port                      = local.frontend_grpc_port
  description                  = "admin-tools / tctl to frontend gRPC"
}

# Other services in the cluster that start workflows (backend, airflow, ...).
resource "aws_vpc_security_group_ingress_rule" "server_frontend_from_clients" {
  for_each = { for idx, sg in var.client_security_group_ids : tostring(idx) => sg }

  security_group_id            = aws_security_group.server.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = local.frontend_grpc_port
  to_port                      = local.frontend_grpc_port
  description                  = "Temporal client traffic from an in-cluster service"
}

resource "aws_vpc_security_group_ingress_rule" "server_metrics_from_clients" {
  for_each = { for idx, sg in var.metrics_client_security_group_ids : tostring(idx) => sg }

  security_group_id            = aws_security_group.server.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.metrics_port
  to_port                      = var.metrics_port
  description                  = "Prometheus scrape of the Temporal server metrics endpoint"
}

resource "aws_vpc_security_group_egress_rule" "server_all" {
  security_group_id = aws_security_group.server.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Postgres, ECR, Secrets Manager, CloudWatch Logs, peer tasks"
}

# ── Web UI ────────────────────────────────────────────────────────────────────

resource "aws_security_group" "ui" {
  name        = "${var.name}-ui"
  description = "Temporal Web UI tasks"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-ui" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ui_from_alb" {
  count = var.create_ui_alb ? 1 : 0

  security_group_id            = aws_security_group.ui.id
  referenced_security_group_id = module.alb[0].security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.ui_port
  to_port                      = var.ui_port
  description                  = "Internal ALB to Web UI"
}

# Direct access to the UI tasks. Required when there is no ALB, and useful
# alongside one for a Teleport-fronted or port-forwarded connection.
resource "aws_vpc_security_group_ingress_rule" "ui_from_clients" {
  for_each = { for idx, sg in var.ui_client_security_group_ids : tostring(idx) => sg }

  security_group_id            = aws_security_group.ui.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.ui_port
  to_port                      = var.ui_port
  description                  = "Web UI direct from an in-cluster service"
}

resource "aws_vpc_security_group_egress_rule" "ui_all" {
  security_group_id = aws_security_group.ui.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Frontend gRPC, ECR, CloudWatch Logs"
}

# ── Python worker ─────────────────────────────────────────────────────────────
#
# Egress-only by design. The worker dials out to the frontend and long-polls;
# nothing ever connects to it. The :8080 health endpoint is served in-process and
# probed over the loopback interface by the container health check, which shares
# the task's network namespace and so needs no security group rule at all.

resource "aws_security_group" "worker" {
  name        = "${var.name}-worker"
  description = "Temporal Python worker fleet (egress only)"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-worker" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "worker_all" {
  security_group_id = aws_security_group.worker.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Frontend gRPC, ECR, Secrets Manager, CloudWatch Logs, AWS APIs, Kafka broker, backend webhook"
}

# ── Schema migration / admin-tools one-off tasks ───────────────────────────────

resource "aws_security_group" "schema" {
  name        = "${var.name}-schema"
  description = "Temporal schema migration and admin-tools one-off tasks"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-schema" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "schema_all" {
  security_group_id = aws_security_group.schema.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Postgres, ECR, Secrets Manager, CloudWatch Logs"
}
