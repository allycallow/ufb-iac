# Connecting to databases via Teleport

## Login

```
tsh login --proxy=teleport.upfrontbeats.com:443 --auth=local --user=alex production-ufb-teleport
```

## Redis (`elasticache-redis`)

No ACL users or auth token are configured on the replication group, so connect as the
default user:

```
tsh db connect elasticache-redis --db-user=default
```

Requires `redis-cli` (`brew install redis`).

## OpenSearch (`opensearch`)

This domain has no fine-grained access control, so Teleport authenticates by assuming
an IAM role named after `--db-user` (`arn:aws:iam::<account_id>:role/<db-user>`). The
role it should assume is `<name>-teleport-opensearch`, provisioned in
[opensearch.tf](./opensearch.tf) with a trust policy for the Teleport task role and
`es:ESHttp*` permissions on the domain.

Use a local tunnel and talk to it with `curl` rather than `tsh db connect` — the
`opensearchsql` CLI that `tsh db connect` shells out to is unmaintained and doesn't
work with current Python/setuptools:

```
tsh proxy db opensearch --tunnel --port=9201 --db-user=production-ufb-teleport-opensearch
```

In another terminal:

```
curl -sk https://localhost:9201/_cat/indices?v
```

(`-k` is needed because the local tunnel presents a self-signed cert.)

## Postgres (`rds-postgres`)

Teleport connects using IAM auth as the Postgres role named by `--db-user`
(`teleport_db_username`, default `teleport_svc` — see
[variables.tf](./variables.tf)):

```
tsh db connect rds-postgres --db-user=teleport_svc --db-name=ufb
```

One-time manual setup: that Postgres role must exist and have `rds_iam` granted —
Terraform only enables `iam_database_authentication_enabled` on the instance, it
doesn't create the role. If `tsh db connect` fails with `password authentication
failed for user "teleport_svc"`, run as the master user:

```sql
CREATE USER teleport_svc WITH LOGIN;
GRANT rds_iam TO teleport_svc;
```

The RDS security group only allows traffic from inside the VPC (no bastion/VPN), so
this has to be run from something already in the VPC — e.g. a one-off Fargate task
using the backend service's task-exec role, pulling the master credentials from the
same Secrets Manager secret the backend app uses.
