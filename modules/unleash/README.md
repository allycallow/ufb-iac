# Unleash on ECS Fargate

Self-hosted [Unleash](https://www.getunleash.io/) feature-flag server, on the
**existing** shared infrastructure in this repo — one ECS Fargate service, its
own database on the existing RDS instance, exposed on the shared public ALB.

Unlike Temporal, there is no separate schema-migration task: Unleash runs its
own Knex migrations against its database on every container boot.

## Why public

The app and website evaluate flags directly against Unleash's **Frontend
API** rather than through the backend, so the server has to be reachable from
the internet. The admin UI rides the same ALB listener — Unleash enforces its
own login on every admin route, the same posture this repo already accepts
for Airflow and the monitoring stack.

## One-off setup

### 1. Create the database role

`module.unleash.db_secret_arn` only generates a password in Secrets Manager —
it does not create the Postgres role. This module registers a one-off task
definition (`db-bootstrap.tf`) that connects as the RDS master user and
creates the `unleash` role/database idempotently, matching the password in
that secret. Run it once, before the first `terraform apply` that starts the
service:

```bash
NETCFG=$(terraform output -raw unleash_run_task_network_configuration)

TASK_ARN=$(aws ecs run-task \
  --cluster "$CLUSTER" \
  --task-definition "$(terraform output -raw unleash_db_bootstrap_task_definition_family)" \
  --launch-type FARGATE \
  --network-configuration "$NETCFG" \
  --query 'tasks[0].taskArn' --output text)

aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN"
aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" \
  --query 'tasks[0].containers[0].{exitCode:exitCode,reason:reason}'
```

It's idempotent — safe to re-run (e.g. after rotating `module.unleash.db_secret_arn`
by hand, which also needs `ALTER ROLE ... PASSWORD` on the live role, a step
this task's "already exists" branch handles too).

### 2. Point DNS at the ALB

Like `airflow.upfrontbeats.com` and `monitoring.upfrontbeats.com`, the
`unleash.upfrontbeats.com` record is **not** managed by this Terraform — create
a CNAME/alias to the ALB's DNS name (`module.alb.dns_name`) the same way the
others were created.

### 3. Apply and log in

```bash
terraform apply
```

First boot seeds Unleash's built-in default admin account
(`admin`/`unleash4all`) since the users table starts empty. Log in with it
once at `https://unleash.upfrontbeats.com`, **immediately create your own
admin user through the UI, and change/retire the default account** — those
are public, well-documented credentials on an internet-facing server.

### 4. Wire up the app and website

Create a Frontend API token through the UI (Admin → API access → Frontend
API). That token is what the client-safe SDKs (`@unleash/proxy-client-react`,
`unleash-proxy-client-swift`/Kotlin for the app, `unleash-proxy-client` for
the website) authenticate with, pointed at
`https://unleash.upfrontbeats.com/api/frontend`. It can only read flag state
for the project/environment it was issued for — never use an admin token
client-side.

## Architecture

```
            app / website ──https──▶ unleash.upfrontbeats.com (shared public ALB)
                                              │ :4242
                                      Unleash (1 task, Fargate)
                                              │
                         existing RDS PostgreSQL 18, database "unleash"
```

Also registered in Cloud Map via Service Connect as `unleash:4242`, so
in-cluster services (monitoring's Prometheus scrape, a future backend
integration) reach it without round-tripping through the public ALB.

## Security notes

- The admin UI and admin API are public, authenticated only by Unleash's own
  login / admin tokens. There is no IP allowlisting or WAF in front of it —
  add one if that's not an acceptable posture.
- First boot seeds the well-known default admin account (`admin`/`unleash4all`)
  — this module deliberately does **not** override it with a generated
  password, so step 3 above (create your own admin user, retire the default
  one) is not optional on a fresh environment.
- `DATABASE_SSL` is set with `rejectUnauthorized: false`: encrypted in
  transit, not verifying the RDS CA chain. Matches the TLS posture already
  accepted for Temporal in this repo.
- The dedicated `unleash` database secret is **not auto-rotated** — rotating
  it means updating the Postgres role's password and redeploying the service,
  the same deliberate (not automatic) process used for Temporal's DB secret.
