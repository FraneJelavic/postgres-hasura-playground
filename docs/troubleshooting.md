# Troubleshooting

Start with `make status`. It reports all service boundaries in one pass and exits
nonzero when any boundary is unhealthy. Failed startup and leadership commands also
print recent logs and endpoint diagnostics while preserving containers and volumes.

## Colima or Docker is unavailable

```sh
colima status
docker context show
docker info
docker compose version
```

Start Colima with at least 4 CPUs, 8 GiB memory, and 30 GiB disk. Confirm the active
Docker context points to the intended Colima VM. A Docker socket permission error
must be fixed on the host; do not run project scripts with broad elevated
privileges as a workaround.

## Startup times out or a container restarts

```sh
./scripts/compose.sh ps --all
./scripts/compose.sh logs --tail=150
```

On a cold image cache, allow time for image download and the custom Patroni build.
Check Colima resources and available disk. If the host is merely slow, increase
`COMPOSE_READINESS_TIMEOUT_SECONDS` consistently for `make up` and `make status`;
do not use a longer timeout to hide a repeatedly failing health check.

## A host port is already in use

Stop the conflicting process or choose unused ports for every invocation:

```sh
POSTGRES_HOST_PORT=55432 HASURA_HOST_PORT=18080 make up
POSTGRES_HOST_PORT=55432 HASURA_HOST_PORT=18080 make status
```

The remaining overrides are `HAPROXY_STATS_HOST_PORT`, `PATRONI1_HOST_PORT`,
`PATRONI2_HOST_PORT`, and `PATRONI3_HOST_PORT`. Preserve the same
`COMPOSE_PROJECT_NAME` and port environment across all commands.

## An initializer did not complete

```sh
./scripts/compose.sh ps --all database-init hasura-init
./scripts/compose.sh logs database-init hasura-init
```

Both services must be `exited` with code `0`.

- `database-init` failures usually mean there is no writable HAProxy route or SQL
  initialization failed.
- `hasura-init` failures usually mean ordinary Hasura health was not reached or a
  migration, metadata, or seed deployment failed.

Fix the first error in the relevant initializer log. Do not treat a running Hasura
container as ready when `hasura-init` failed.

## Patroni has no sole primary

Inspect each member:

```sh
curl --fail --silent http://127.0.0.1:8008/patroni | jq
curl --fail --silent http://127.0.0.1:8009/patroni | jq
curl --fail --silent http://127.0.0.1:8010/patroni | jq
./scripts/compose.sh logs --tail=150 postgres1 postgres2 postgres3
```

Also inspect the etcd section of `make status`. Do not manually promote a member
while another member might still accept writes. If the data is disposable and the
topology cannot recover, use the confirmed `make reset` followed by `make up`.

## HAProxy is not routing to the primary

```sh
curl --fail --silent 'http://127.0.0.1:7000/stats;csv'
make status
```

Exactly one `postgres_primary` backend must be `UP`, it must match Patroni's sole
primary, and SQL through HAProxy must report writable. During a leadership change,
allow the bounded recovery window before intervening. Never connect host clients to
an internal member address to bypass this check.

## Hasura ordinary health passes but strict health fails

```sh
curl --fail-with-body --silent --show-error \
  --header 'x-hasura-admin-secret: test' \
  'http://127.0.0.1:8080/healthz?strict=true'
./scripts/compose.sh logs --tail=150 hasura hasura-init
```

Ordinary health is only a bootstrap milestone. Strict failure indicates an
unhealthy source or inconsistent metadata. Confirm `hasura-init` exited zero and
that the writable PostgreSQL route is healthy before changing metadata.

## GraphQL returns an error

Confirm the request includes `x-hasura-admin-secret: test` and inspect the JSON
`errors` array even when the HTTP status is 200. Run the small authenticated query
in [Getting Started](getting-started.md), then inspect Hasura logs and strict
health. A missing `todos` field usually means the tracked project did not deploy
successfully.

## Leadership exercise fails

Run `make status` and retain the diagnostics from the failed command. The abrupt
workflow attempts to restart the member it killed. Confirm all three database
containers are running before repeating an exercise. Follow the recovery and
reconnection expectations in [Failover Scenario](failover-scenario.md).

## A clean disposable restart is required

```sh
make reset
make up
make status
```

Reset permanently deletes this Compose project's volumes and requires exact-name
confirmation. Use it only when the stored playground data can be discarded.
