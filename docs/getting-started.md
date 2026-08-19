# Getting Started

This guide takes a new user from an empty local checkout to a healthy GraphQL and
PostgreSQL playground.

## Prerequisites

- Docker Engine 27 or newer.
- Docker Compose plugin 2.30 or newer (`docker compose`, not `docker-compose`).
- Bash, `curl`, `jq`, and Make.
- 4 CPUs, 8 GiB memory, and 30 GiB disk available to the container runtime.

On macOS, Colima 0.8 or newer is the supported local runtime. Start it with the
validated baseline:

```sh
colima start --cpu 4 --memory 8 --disk 30
docker version
docker compose version
```

ShellCheck and `yamllint` are additionally required by `make check`. See the
[compatibility matrix](compatibility.md) for pinned component versions and
architectures.

## Start the playground

```sh
git clone <repository-url>
cd postgres-hasura-playground
make up
make status
```

The first start builds the Patroni image and downloads pinned upstream images, so
it can take a few minutes. `make up` does not return successfully until database
initialization, Hasura project deployment, and the one-primary/two-replica
topology are ready. `make status` then verifies every live service boundary.

The tracked values are intentionally simple and local-only:

- PostgreSQL superuser: `postgres`
- PostgreSQL password: `test`
- Hasura admin secret: `test`

They are not production secrets. Do not expose the playground to untrusted users
or networks.

## Open the console and endpoints

Open `http://127.0.0.1:8080/console` and enter `test` when the console asks for the
admin secret.

| Interface | Default address |
|---|---|
| PostgreSQL write route | `postgresql://postgres:test@127.0.0.1:5432/postgres` |
| Hasura console | `http://127.0.0.1:8080/console` |
| GraphQL endpoint | `http://127.0.0.1:8080/v1/graphql` |
| Strict Hasura health | `http://127.0.0.1:8080/healthz?strict=true` |
| HAProxy statistics | `http://127.0.0.1:7000/stats` |
| Patroni member APIs | `http://127.0.0.1:8008/patroni` through port `8010` |

All published ports bind to loopback. etcd ports and individual PostgreSQL member
database ports remain inside the Compose network.

Connect through the stable SQL route:

```sh
PGPASSWORD=test psql -h 127.0.0.1 -p 5432 -U postgres -d postgres
```

## Query and mutate todos

Query the idempotent seed through authenticated GraphQL:

```sh
curl --fail-with-body --silent --show-error \
  --header 'content-type: application/json' \
  --header 'x-hasura-admin-secret: test' \
  --data '{"query":"query { todos(limit: 5, order_by: {id: asc}) { id title completed } }"}' \
  http://127.0.0.1:8080/v1/graphql | jq
```

Insert a todo with a GraphQL variable:

```sh
jq -cn --arg title 'Created from curl' '{
  query: "mutation AddTodo($title: String!) { insert_todos_one(object: {title: $title}) { id title completed } }",
  variables: {title: $title}
}' | curl --fail-with-body --silent --show-error \
  --header 'content-type: application/json' \
  --header 'x-hasura-admin-secret: test' \
  --data @- \
  http://127.0.0.1:8080/v1/graphql | jq
```

An HTTP 200 response can still contain GraphQL `errors`; inspect the JSON response,
not only curl's exit status.

## Command reference

| Command | Effect |
|---|---|
| `make up` | Build, initialize, start, and wait for readiness |
| `make status` | Report all health boundaries and exit nonzero if one fails |
| `make switchover` | Move leadership to a healthy replica and wait for rejoin |
| `make failover` | Kill the primary, verify promotion, restart it, and wait for rejoin |
| `make verify` | Run the full destructive acceptance scenario |
| `make logs` | Follow recent logs from all services |
| `make down` | Remove containers and the network while preserving named volumes |
| `make reset` | Confirm, then delete this project's containers and named volumes |
| `make check` | Run static, policy, Compose, YAML, and shell checks |
| `make diagrams` | Regenerate the tracked C4 PNGs |
| `make check-diagrams` | Check that tracked C4 PNGs match their source |

`make reset` is irreversible for data in the playground volumes. Interactive use
requires typing the exact Compose project name. Automation must opt in explicitly:

```sh
CONFIRM_RESET=YES make reset
```

## Port and timeout overrides

Host ports can be changed with `POSTGRES_HOST_PORT`, `HAPROXY_STATS_HOST_PORT`,
`PATRONI1_HOST_PORT`, `PATRONI2_HOST_PORT`, `PATRONI3_HOST_PORT`, and
`HASURA_HOST_PORT`. `COMPOSE_PROJECT_NAME` changes the resource namespace.

Readiness and recovery waits use `COMPOSE_READINESS_TIMEOUT_SECONDS`,
`LEADERSHIP_TIMEOUT_SECONDS`, and `REJOIN_TIMEOUT_SECONDS`, with defaults of 240,
60, and 120 seconds. Pass the same environment to every command that targets a
given stack.

Next, read the [Hasura project guide](hasura-project.md), the
[operations runbook](operations.md), and the
[failover scenario](failover-scenario.md).
