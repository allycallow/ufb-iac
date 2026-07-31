# Temporal on ECS Fargate

Self-hosted Temporal Server and a stateless Python worker fleet, running on the
**existing** shared infrastructure in this repo.

## What this reuses vs. creates

| Reused (no new resource) | Created by this module |
| --- | --- |
| VPC, private subnets, NAT — `modules/networking` | 4 Temporal server ECS services |
| ECS cluster + capacity providers — `modules/ecs-cluster` | Cloud Map services for each role |
| Cloud Map namespace `<name>.internal` — `modules/ecs-cluster` | Web UI service + **internal** ALB |
| RDS PostgreSQL 18 + its Secrets Manager secret — `modules/database` | Python worker service + autoscaling |
| RDS security group (already allows 5432 from the VPC CIDR) | 4 security groups, IAM roles |
| ECR registry — `modules/container-registry` | 2 one-off task definitions (schema, admin) |

Two deliberate exceptions to "reuse everything":

- **The ALB is new and internal.** The root `alb.tf` is internet-facing. The Web
  UI is an unauthenticated console over every workflow in the cluster, so it gets
  its own internal-only ALB in the private subnets. Front it with the existing
  Teleport application access for per-user identity.
- **Cloud Map, not Service Connect.** Every other service in this repo uses
  Service Connect. Temporal's ringpop membership requires each server task's real
  ENI address — peers read it from the `cluster_membership` table and dial it
  directly — which a sidecar proxy mesh would hide. This module therefore
  registers plain A records in the same namespace.

## Cost

Verified against the AWS pricing API for **eu-west-2**, 730 h/month. Fargate
ARM64 is $0.03725/vCPU-h and $0.00409/GB-h — about 20% cheaper than x86, and all
three official images publish `linux/arm64`, so `server_cpu_architecture`
defaults to ARM64.

| Profile | Monthly | What you give up |
| --- | --- | --- |
| `multi-role`, ALB, 2 tasks/role (module defaults) | **~$214** | nothing |
| `single-node`, no ALB, 1 Spot worker (**current root config**) | **~$33** | HA; UI needs Teleport |
| as above with the server on Spot too | ~$15 | plus multi-minute stalls on reclaim |

Where the ~$33 goes: all-in-one server $16.58, UI $8.29, Spot worker $4.97,
logs + Cloud Map ~$3.

The four levers, by value:

1. **`deployment_mode = "single-node"`** — saves ~$170. Deploys still roll, but an
   unplanned task loss is a 1–2 minute outage.
2. **`create_ui_alb = false`** — saves ~$19. Best saving-to-downside ratio: the UI
   stays deployed at `temporal-ui.<namespace>:8080`, reached via Teleport.
3. **ARM64** — 20% off all compute, no downside. Already the default.
4. **`worker_on_demand_base = 0`** — the whole worker fleet on Spot, ~70% off.

RDS, NAT and the VPC are already paid for. Temporal does add load to the shared
`db.t4g.medium`: shard background scanners write even when no workflows run, and
that cost scales with `temporal_num_history_shards`. The root config uses 128
rather than 512 partly for this reason.

> `temporal_num_history_shards` is **immutable**. Changing it later requires a
> fresh database and loses all workflow history. The root stack sets 128.

To go back to the production topology, delete the cost-profile block in
`main.tf` — the module defaults are the HA ones, and switching modes needs no
database change because the frontend keeps the same Cloud Map address.

## Architecture

`single-node` (current root config):

```
   Teleport app access ──▶ temporal-ui.<ns>:8080   (1 task, no ALB)
                                    │ gRPC :7233
   Python worker ──long-poll :7233──▶ temporal-frontend.<ns>:7233
   (1 task, Fargate Spot,             │  ONE task running
    egress-only SG)                   │  SERVICES=frontend,history,matching,worker
                                      ▼
                       existing RDS PostgreSQL 18
                       databases: temporal, temporal_visibility
```

`multi-role` (module default):

```
                    ┌──────────────────── internal ALB :8080 ─────────┐
                    │  (private subnets, VPC + Teleport SG only)      │
                    └───────────────────────┬────────────────────────┘
                                            │
                                    temporal-ui  (ECS)
                                            │ gRPC :7233
   Python workers ──long-poll :7233──▶ temporal-frontend ◀── backend / airflow
   (Fargate Spot,                            │
    egress-only SG)              ┌───────────┴───────────┐
                                 ▼                       ▼
                        temporal-history         temporal-matching
                                 └───────────┬───────────┘
                                             │ ringpop :6933-6939
                                    temporal-internal-worker
                                             │
                                             ▼
                        existing RDS PostgreSQL 18
                        databases: temporal, temporal_visibility
```

The frontend's Cloud Map name is `temporal-frontend` in **both** modes, so no
client configuration changes when you switch.

All server roles share one security group so they can reach each other on the
membership and gRPC port ranges without a four-way dependency cycle.

Server tasks run on **on-demand** Fargate. History owns shard leases, and a Spot
reclaim forces a shard rebalance across the ring. Only the Python workers use
Spot, where an interruption costs nothing: the worker stops polling and Temporal
redelivers its tasks.

---

## Deployment

### 0. Prerequisites

```bash
export AWS_REGION=eu-west-2
export AWS_PROFILE=<your-profile>
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER=production-ufb          # matches local.name in main.tf
export PREFIX=production-ufb-temporal  # var.name passed to this module
terraform workspace select production
```

### 1. Create the ECR repository

The worker image repository is created by `modules/container-registry`, and the
worker service cannot start before an image exists. Create the registry first and
keep the worker at zero tasks:

```bash
terraform apply -target=module.container_registry
```

### 2. Build and push the worker image

The worker lives in its own repository: **`ufb-temporal-worker`**. Pushing to its
`main` branch runs lint and tests, then builds and deploys via the CircleCI orbs —
the same pattern as `ufb-track-metadata`.

For the very first deploy the ECS service does not exist yet, so `update_service`
has nothing to update. Push the image by hand once:

```bash
cd ../ufb-temporal-worker

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin \
      "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

REPO="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$CLUSTER-temporal-worker"

# ARM64 is required — the task definition requests it (var.worker_cpu_architecture)
# because it is ~20% cheaper per vCPU-hour. An x86 image will not start.
docker buildx build \
  --platform linux/arm64 \
  --tag "$REPO:latest" \
  --tag "$REPO:$(git rev-parse --short HEAD)" \
  --push .
```

After that, CircleCI owns deploys and you should not need this again.

> Prefer an immutable tag over `:latest` in production. Set
> `worker_image_uri` to the digest or the commit tag in `main.tf` so a rollback
> is a Terraform change rather than a registry mutation.

### 3. Apply the infrastructure

Bring everything up **except** the server services, so the schema exists before
any server task tries to read it. The deployment circuit breaker would otherwise
roll the services back while they crash-loop against a missing schema.

```bash
cd ..

terraform apply \
  -target=module.temporal.aws_ecs_task_definition.schema \
  -target=module.temporal.aws_iam_role_policy_attachment.task_exec_db_secret \
  -target=module.temporal.aws_security_group.schema \
  -target=module.temporal.aws_vpc_security_group_egress_rule.schema_all
```

### 4. Initialise the database schema

Creates the `temporal` and `temporal_visibility` databases on the existing RDS
instance and brings both schemas to the version the pinned server image expects.

```bash
# The stack emits a ready-made network configuration for the one-off tasks:
NETCFG=$(terraform output -raw temporal_run_task_network_configuration)

TASK_ARN=$(aws ecs run-task \
  --cluster "$CLUSTER" \
  --task-definition "$PREFIX-schema" \
  --launch-type FARGATE \
  --network-configuration "$NETCFG" \
  --query 'tasks[0].taskArn' --output text)

aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN"

# Exit code 0 means the migration succeeded.
aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].{exitCode:exitCode,reason:reason}'

# Full migration log:
aws logs tail "/aws/ecs/$PREFIX/schema" --since 10m
```

The task is **idempotent** — it tolerates existing databases and an
already-initialised schema, then runs `update-schema` to reach the latest
version. Re-run it before every server image upgrade.

### 5. Apply the rest

```bash
terraform apply
```

This starts the four server services, the Web UI, and the worker fleet. Watch the
frontend come up:

```bash
aws logs tail "/aws/ecs/$PREFIX/frontend" --follow
```

Each server task logs its resolved membership address on start:

```
temporal[frontend] advertising membership address 10.0.4.212
```

If that line is missing, the ringpop broadcast address failed to resolve and the
cluster will not form — see Troubleshooting.

### 6. Register the default namespace

Run once the frontend is healthy. The task waits up to five minutes for the
frontend, then creates the namespace if it does not exist.

```bash
NETCFG=$(terraform output -raw temporal_run_task_network_configuration)

TASK_ARN=$(aws ecs run-task \
  --cluster "$CLUSTER" \
  --task-definition "$PREFIX-admin" \
  --launch-type FARGATE \
  --network-configuration "$NETCFG" \
  --query 'tasks[0].taskArn' --output text)

aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN"
aws logs tail "/aws/ecs/$PREFIX/schema" --since 5m
```

### 7. Verify

```bash
# Web UI. With create_ui_alb = false this is a Cloud Map name that only resolves
# inside the VPC — reach it through Teleport application access.
terraform output -raw temporal_ui_url

# Cluster health, from an admin task shell:
aws ecs execute-command --cluster "$CLUSTER" \
  --task "$TASK_ARN" --container admin --interactive \
  --command "temporal operator cluster health"
```

Confirm all four roles are in the ring — you should see one entry per running
task:

```bash
aws ecs execute-command --cluster "$CLUSTER" --task "$TASK_ARN" \
  --container admin --interactive \
  --command "temporal operator cluster describe"
```

---

## Running a workflow

From any service whose security group is in `client_security_group_ids`:

```python
from temporalio.client import Client
from activities import TrackInput

client = await Client.connect(
    "temporal-frontend.production-ufb.internal:7233",
    namespace="default",
)

handle = await client.start_workflow(
    "TrackIngestionWorkflow",
    TrackInput(track_id="trk-001", source_uri="s3://production-ufb-media/source/a.wav"),
    id="ingest-trk-001",
    task_queue="ufb-pipeline",
)
print(await handle.result())
```

`id` is the idempotency key: starting the same workflow id twice while the first
is still running is rejected, which is usually what you want for ingestion.

---

## Upgrading the Temporal server

Schema first, then servers — never the other way round.

```bash
# 1. Bump the pinned tags together in main.tf:
#      temporal_server_image      = "temporalio/server:<new>"
#      temporal_admin_tools_image = "temporalio/admin-tools:<new>"

# 2. Register the new schema task definition only.
terraform apply -target=module.temporal.aws_ecs_task_definition.schema

# 3. Migrate.
aws ecs run-task --cluster "$CLUSTER" --task-definition "$PREFIX-schema" \
  --launch-type FARGATE --network-configuration "$NETCFG"

# 4. Roll the servers.
terraform apply
```

Never skip more than one minor version in a single hop, and never change
`temporal_num_history_shards` on a cluster that holds data — it is baked into
shard ownership and changing it requires a fresh database.

---

## Scaling

Workers scale on average CPU (`worker_cpu_target`, default 65%) between
`worker_min_capacity` and `worker_max_capacity`.

`worker_scale_in_cooldown` defaults to 300s and must stay **longer than your
longest activity**. Scale-in stops a task, and although the worker drains
gracefully for `WORKER_GRACEFUL_SHUTDOWN_SECONDS` (90s, inside the 120s
`stopTimeout`), an aggressive cooldown still churns long activities needlessly.

CPU is a proxy, not the real signal. Once you have workflow volume, scale on task
queue backlog instead — `temporal_worker_task_slots_available` or the
`ScheduleToStartLatency` metric — via a custom CloudWatch metric and a
`customized_metric_specification` in `autoscaling_policies`.

Server roles have fixed counts (`server_roles[*].desired_count`). Scale
`frontend` with client connection count and `history` with shard contention; do
not autoscale `history` reactively, since every change triggers a shard rebalance.

---

## Troubleshooting

**Server tasks crash-loop with `error creating sql connection`**
The schema step has not run, or the database is unreachable. Check the schema
task log, and confirm the RDS security group still permits 5432 from the VPC
CIDR.

**Cluster never forms; roles cannot see each other**
Look for the `advertising membership address` line in each role's log. If it is
absent, `hostname -i` returned nothing in that image and the metadata fallback
also failed. Confirm the shared security group allows 6933-6939 between server
tasks, and that all roles point at the same database.

**`FATAL: schema directory ... not found`**
The pinned admin-tools image lays out its schema files differently. The task
prints the available directories; set `temporal_schema_dir` accordingly.

**Web UI loads but shows no workflows**
The UI is reaching the frontend but the namespace does not exist. Run step 6.

**Worker health check fails but logs look fine**
The container health check probes `127.0.0.1:$WORKER_HEALTH_PORT`. It returns 503
while the worker is still connecting — expected during the 30s `startPeriod`, a
problem after it. `TEMPORAL_HOST` unreachable is the usual cause.

**Read-only root filesystem breaks the worker**
Both the UI and worker tasks set `readonlyRootFilesystem = true`, and Fargate
cannot mount a writable tmpfs. If a dependency you add needs scratch space, set
`worker_readonly_root_filesystem = false`.

---

## Security notes

- Database credentials are the RDS-managed Secrets Manager secret. The ECS agent
  resolves `username` and `password` per task; no credential enters a task
  definition, Terraform state, or a process argv — including in the migration
  script, which passes them via `SQL_USER` / `SQL_PASSWORD` environment
  variables rather than command-line flags.
- The worker security group is **egress-only**. The `:8080` health endpoint binds
  to `127.0.0.1` and is probed inside the task's own network namespace, so it
  needs no ingress rule at all.
- The Web UI ALB is internal, restricted to the VPC CIDR plus `ui_allowed_cidrs`
  and `ui_client_security_group_ids`. It has **no authentication of its own** —
  put Teleport or an OIDC-authenticating proxy in front of it before giving it to
  humans, and set `ui_certificate_arn` to terminate TLS in-VPC.
- Server-to-server gRPC is plaintext inside the VPC. For mTLS between roles, mount
  certificates and set the `TEMPORAL_TLS_*` variables the official image reads.
