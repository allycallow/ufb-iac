variable "name" {
  description = "Resource name prefix, e.g. production-ufb-temporal"
  type        = string
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

# ── Shared infrastructure handed in from the root stack ────────────────────────

variable "vpc_id" {
  type = string
}

variable "vpc_cidr_block" {
  type = string
}

variable "private_subnets" {
  description = "Private subnets for every Temporal task and for the internal ALB."
  type        = list(string)
}

variable "ecs_cluster_arn" {
  description = "ARN of the shared ECS cluster. Temporal runs alongside the other services."
  type        = string
}

variable "task_exec_policy_arn" {
  description = "Shared task-execution policy from the ecs-cluster module."
  type        = string
}

variable "worker_image_uri" {
  description = "ECR image URI for the Python Temporal worker."
  type        = string
}

# ── Existing RDS PostgreSQL (modules/database) ────────────────────────────────

variable "db_host" {
  description = <<-EOT
    Hostname of the existing RDS PostgreSQL instance, without the port.
    Pass `split(":", module.database.db_instance_endpoint)[0]`.
  EOT
  type        = string
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "db_secret_arn" {
  description = <<-EOT
    ARN of the RDS-managed master credentials secret
    (`module.database.db_instance_master_user_secret_arn`). Holds JSON with
    `username` and `password` keys; the ECS agent resolves them per task, so no
    credential ever lands in Terraform state or a task definition.
  EOT
  type        = string
}

variable "db_secret_kms_key_id" {
  description = "KMS key protecting db_secret_arn. Null means the aws/secretsmanager managed key."
  type        = string
  default     = null
}

variable "temporal_db_name" {
  description = "Database created on the existing instance for Temporal's core schema."
  type        = string
  default     = "temporal"
}

variable "temporal_visibility_db_name" {
  description = "Database created on the existing instance for Temporal's visibility schema."
  type        = string
  default     = "temporal_visibility"
}

variable "db_bootstrap_database" {
  description = "Existing database the migration task connects to in order to issue CREATE DATABASE."
  type        = string
  default     = "postgres"
}

variable "db_tls_enabled" {
  description = <<-EOT
    Connect to PostgreSQL over TLS. RDS PostgreSQL 15+ ships with
    `rds.force_ssl = 1`, so this must stay true for the existing PG 18 instance.
  EOT
  type        = bool
  default     = true
}

# ── Access control ────────────────────────────────────────────────────────────

variable "client_security_group_ids" {
  description = <<-EOT
    Security groups of other services (backend, airflow, teleport, ...) allowed
    to reach the Temporal frontend on 7233.
  EOT
  type        = list(string)
  default     = []
}

variable "ui_client_security_group_ids" {
  description = "Security groups allowed to reach the internal Web UI ALB."
  type        = list(string)
  default     = []
}

variable "ui_allowed_cidrs" {
  description = <<-EOT
    Extra CIDRs allowed to reach the internal Web UI ALB. The VPC CIDR is always
    permitted. Add VPN / Transit Gateway ranges here. The ALB is never public.
  EOT
  type        = list(string)
  default     = []
}

# ── Cloud Map ─────────────────────────────────────────────────────────────────
#
# Reuses the cluster-wide Cloud Map namespace created by modules/ecs-cluster
# (`<name>.internal`). Temporal registers plain A records there via ECS service
# discovery rather than Service Connect: ringpop membership requires the tasks'
# real ENI addresses, which a sidecar proxy mesh would hide.

variable "service_discovery_namespace_id" {
  description = "ID of the shared Cloud Map private DNS namespace."
  type        = string
}

variable "service_discovery_namespace_name" {
  description = <<-EOT
    Name of the shared Cloud Map namespace, e.g. `production-ufb.internal`.
    The frontend therefore resolves as
    `temporal-frontend.production-ufb.internal:7233`.
  EOT
  type        = string
}

# ── Images ────────────────────────────────────────────────────────────────────

variable "temporal_server_image" {
  description = "Official Temporal server image. Always pin a tag."
  type        = string
  default     = "temporalio/server:1.31.2"
}

variable "temporal_admin_tools_image" {
  description = <<-EOT
    Provides temporal-sql-tool and the temporal CLI for the migration and
    bootstrap tasks. Keep the version aligned with temporal_server_image —
    the schema this applies must match what the server expects.
  EOT
  type        = string
  default     = "temporalio/admin-tools:1.31.2"
}

variable "temporal_ui_image" {
  description = "Official Temporal Web UI image."
  type        = string
  default     = "temporalio/ui:2.52.1"
}

variable "temporal_schema_dir" {
  description = <<-EOT
    Root of the PostgreSQL schema files inside the admin-tools image. `v12` is
    the directory for every PostgreSQL 12 or newer. Verify against your pinned
    tag with:

      docker run --rm --entrypoint sh temporalio/admin-tools:1.31.2 \
        -c 'ls -d /etc/temporal/schema/postgresql/*/*/versioned'
  EOT
  type        = string
  default     = "/etc/temporal/schema/postgresql/v12"
}

# ── Temporal server topology ──────────────────────────────────────────────────

variable "temporal_log_level" {
  type    = string
  default = "info"
}

variable "server_cpu_architecture" {
  description = <<-EOT
    Architecture for the official Temporal images. ARM64 is ~20% cheaper per
    vCPU-hour on Fargate and the server, ui and admin-tools images all publish
    linux/arm64 manifests. If you pin an older tag, confirm it does too:

      docker manifest inspect temporalio/server:<tag> | grep architecture
  EOT
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.server_cpu_architecture)
    error_message = "server_cpu_architecture must be X86_64 or ARM64."
  }
}

variable "deployment_mode" {
  description = <<-EOT
    `multi-role`  — one ECS service per Temporal role, each independently
                    scalable. Production topology, and what you want once
                    workflow volume justifies it.

    `single-node` — all four roles in one container (SERVICES=frontend,history,
                    matching,worker), one task. Roughly one sixth of the cost,
                    at the price of high availability: a deploy or a task
                    replacement is a short full outage. Workflow state lives in
                    RDS, so nothing is lost — execution just pauses.

    Switching modes later is safe and needs no database change; the frontend
    keeps the same Cloud Map address in both.
  EOT
  type        = string
  default     = "multi-role"

  validation {
    condition     = contains(["multi-role", "single-node"], var.deployment_mode)
    error_message = "deployment_mode must be \"multi-role\" or \"single-node\"."
  }
}

variable "single_node_cpu" {
  description = "CPU units for the all-in-one task. Only used when deployment_mode is single-node."
  type        = number
  default     = 512
}

variable "single_node_memory" {
  description = "Memory (MiB) for the all-in-one task. Only used when deployment_mode is single-node."
  type        = number
  default     = 1024
}

variable "worker_cpu_architecture" {
  description = "Architecture for the worker image we build ourselves. ARM64 matches the other repo services."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.worker_cpu_architecture)
    error_message = "worker_cpu_architecture must be X86_64 or ARM64."
  }
}

variable "temporal_num_history_shards" {
  description = <<-EOT
    IMMUTABLE after the first schema setup. Changing this on a cluster that
    already holds data corrupts shard ownership — you would need a fresh
    database and a namespace migration. 512 suits most workloads.
  EOT
  type        = number
  default     = 512
}

variable "temporal_default_namespace" {
  type    = string
  default = "default"
}

variable "temporal_default_namespace_retention" {
  description = "Retention for the auto-registered default namespace."
  type        = string
  default     = "72h"
}

variable "server_roles" {
  description = <<-EOT
    Sizing and ports for the four Temporal server roles. The gRPC and membership
    ports follow the upstream docker-compose convention; changing them means
    changing every client address too. `service` is the value passed to the
    image's SERVICES env var and must stay one of frontend/history/matching/worker.
  EOT
  type = map(object({
    service         = string
    cpu             = number
    memory          = number
    desired_count   = number
    grpc_port       = number
    membership_port = number
  }))

  default = {
    frontend = {
      service         = "frontend"
      cpu             = 512
      memory          = 1024
      desired_count   = 2
      grpc_port       = 7233
      membership_port = 6933
    }
    history = {
      service         = "history"
      cpu             = 1024
      memory          = 2048
      desired_count   = 2
      grpc_port       = 7234
      membership_port = 6934
    }
    matching = {
      service         = "matching"
      cpu             = 512
      memory          = 1024
      desired_count   = 2
      grpc_port       = 7235
      membership_port = 6935
    }
    internal-worker = {
      service         = "worker"
      cpu             = 512
      memory          = 1024
      desired_count   = 1
      grpc_port       = 7239
      membership_port = 6939
    }
  }

  validation {
    condition     = contains(keys(var.server_roles), "frontend")
    error_message = "server_roles must contain a \"frontend\" key — the Cloud Map address every client uses is derived from it."
  }

  validation {
    condition = length(setsubtract(
      ["frontend", "history", "matching", "worker"],
      [for r in var.server_roles : r.service],
    )) == 0
    error_message = "server_roles must cover all four Temporal roles: frontend, history, matching, worker."
  }
}

variable "server_membership_port_range" {
  description = "Contiguous ringpop membership port range opened between server tasks."
  type = object({
    from = number
    to   = number
  })
  default = {
    from = 6933
    to   = 6939
  }
}

variable "server_grpc_port_range" {
  description = "Contiguous gRPC port range opened between server tasks."
  type = object({
    from = number
    to   = number
  })
  default = {
    from = 7233
    to   = 7239
  }
}

# ── Web UI ────────────────────────────────────────────────────────────────────

variable "ui_cpu" {
  type    = number
  default = 256
}

variable "ui_memory" {
  type    = number
  default = 512
}

variable "ui_desired_count" {
  type    = number
  default = 2
}

variable "ui_port" {
  description = "Web UI container port and internal ALB listener port."
  type        = number
  default     = 8080
}

variable "create_ui_alb" {
  description = <<-EOT
    Put the Web UI behind a dedicated internal ALB. An ALB costs ~$19/month in
    eu-west-2 before LCUs. With this false the UI is still deployed and
    registered in Cloud Map as `temporal-ui.<namespace>:8080` — reach it through
    Teleport application access or a port-forward instead.
  EOT
  type        = bool
  default     = true
}

variable "ui_certificate_arn" {
  description = <<-EOT
    ACM certificate for the internal ALB listener. When null the listener is
    plain HTTP, which is acceptable only because the ALB is internal and
    CIDR-restricted. Set it to terminate TLS in-VPC.
  EOT
  type        = string
  default     = null
}

variable "ui_alb_deletion_protection" {
  description = "The UI ALB holds no state, so this defaults off to keep teardown simple."
  type        = bool
  default     = false
}

# ── Python worker ─────────────────────────────────────────────────────────────

variable "worker_cpu" {
  type    = number
  default = 512
}

variable "worker_memory" {
  type    = number
  default = 1024
}

variable "worker_desired_count" {
  description = "Baseline worker count. Set to 0 on the first apply, before an image exists in ECR."
  type        = number
  default     = 2
}

variable "worker_min_capacity" {
  type    = number
  default = 2
}

variable "worker_max_capacity" {
  type    = number
  default = 20
}

variable "worker_cpu_target" {
  description = "Target average CPU utilisation (%) for worker target-tracking scaling."
  type        = number
  default     = 65
}

variable "worker_scale_in_cooldown" {
  description = <<-EOT
    Seconds before another scale-in. Keep this longer than your longest activity
    so long-polling workers are not culled mid-activity.
  EOT
  type        = number
  default     = 300
}

variable "worker_scale_out_cooldown" {
  type    = number
  default = 60
}

variable "worker_health_port" {
  description = "In-process health endpoint, reachable on localhost only."
  type        = number
  default     = 8080
}

variable "worker_readonly_root_filesystem" {
  description = <<-EOT
    Mount the worker's root filesystem read-only. The image sets
    PYTHONDONTWRITEBYTECODE and logs to stdout, so it needs no writable path.
    Fargate cannot mount a tmpfs, so set this to false if you add a dependency
    that requires scratch space.
  EOT
  type        = bool
  default     = true
}

variable "ui_readonly_root_filesystem" {
  description = "Mount the Web UI's root filesystem read-only. The UI serves embedded assets."
  type        = bool
  default     = true
}

variable "worker_task_queue" {
  type    = string
  default = "ufb-pipeline"
}

variable "worker_max_concurrent_activities" {
  type    = number
  default = 50
}

variable "worker_max_concurrent_workflow_tasks" {
  type    = number
  default = 50
}

variable "worker_use_spot" {
  description = "Run workers on Fargate Spot. They are stateless, so interruption is safe."
  type        = bool
  default     = true
}

variable "worker_spot_weight" {
  type    = number
  default = 4
}

variable "worker_on_demand_weight" {
  type    = number
  default = 1
}

variable "worker_on_demand_base" {
  description = "Tasks pinned to on-demand FARGATE before Spot weighting applies."
  type        = number
  default     = 1
}

variable "worker_environment" {
  description = "Extra plain environment variables for the worker container."
  type        = map(string)
  default     = {}
}

variable "worker_secrets" {
  description = "Extra Secrets Manager / SSM references for the worker, as name => valueFrom."
  type        = map(string)
  default     = {}
}

variable "worker_secret_arns" {
  description = "ARNs the worker task role may read."
  type        = list(string)
  default     = []
}

# ── Observability ─────────────────────────────────────────────────────────────

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "enable_execute_command" {
  description = "Allow `aws ecs execute-command` into tasks — used to run tctl against the cluster."
  type        = bool
  default     = true
}
