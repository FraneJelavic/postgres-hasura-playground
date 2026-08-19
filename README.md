# PostgreSQL Hasura Playground

A local, single-host playground for a highly available PostgreSQL write path and
Hasura GraphQL API. Docker Compose runs three Patroni-managed PostgreSQL members,
three etcd voters, HAProxy, and a tracked Hasura project. The repository includes
repeatable startup, health reporting, controlled switchover, abrupt-failure, and
end-to-end verification workflows.

This is a development and learning environment, not a production deployment.
Every redundant container still depends on one Docker or Colima host.

## Architecture

![System context](docs/c4/context.png)

![Container view](docs/c4/containers.png)

The write path is deliberately narrow:

1. Patroni uses the three-member etcd cluster for leader election and cluster
   state.
2. Exactly one PostgreSQL member accepts writes; two members receive asynchronous
   physical replication.
3. HAProxy checks Patroni's primary endpoint and exposes only the current writable
   member on `127.0.0.1:5432`.
4. Hasura connects to PostgreSQL through HAProxy. The tracked project deploys the
   `todos` schema, metadata, and an idempotent seed.

See [Architecture](docs/architecture.md) for component responsibilities, startup
ordering, storage, and failure behavior.

## Quick start

```sh
git clone <repository-url>
cd postgres-hasura-playground
make up
make status
```

`make up` validates the Compose model, builds the Patroni image, starts the stack,
waits for the database initializer, deploys the Hasura project and seed, and then
requires one primary and two streaming replicas. A first build downloads several
images and can take a few minutes.

Use Docker Engine 27+, Docker Compose 2.30+, and 4 CPUs, 8 GiB memory, and 30 GiB
disk. macOS users should follow the validated Colima command, prerequisites, local
test values, GraphQL query and mutation examples, and reset instructions in
[Getting Started](docs/getting-started.md).

## Endpoints

All published ports bind only to loopback. The primary entry points are:

| Interface | Default address | Purpose |
|---|---|---|
| PostgreSQL through HAProxy | `postgresql://postgres:test@127.0.0.1:5432/postgres` | Sole writable database route |
| Hasura console | `http://127.0.0.1:8080/console` | Local API console |
| GraphQL | `http://127.0.0.1:8080/v1/graphql` | Authenticated application API |

The complete endpoint list and supported overrides are in
[Getting Started](docs/getting-started.md).

## Commands

| Command | Effect |
|---|---|
| `make up` | Build, initialize, start, and wait for a healthy topology |
| `make status` | Report every service boundary; exit nonzero if any is unhealthy |
| `make switchover` | Move leadership to a healthy replica and wait for full rejoin |
| `make failover` | Kill the current primary, wait for promotion, restart it, and wait for rejoin |
| `make verify` | Run the complete destructive acceptance scenario |
| `make down` | Stop containers while preserving named volumes |
| `make reset` | Confirm, then remove this project's containers and named volumes |

See [Getting Started](docs/getting-started.md) for the complete command reference
and the non-interactive reset opt-in.

## Leadership changes and client behavior

Use `make switchover` for planned role movement and `make failover` for abrupt
primary loss. Existing sessions can be closed, clients must reconnect, and
asynchronous replication does not guarantee zero data loss. Read the
[Failover Scenario](docs/failover-scenario.md) before running either command. See
[Operations](docs/operations.md) for the lifecycle runbook and
[Verification Contract](docs/verification-contract.md) for exact assertions and
timeouts.

## Production boundary

This single-host environment has fixed development values, no TLS, asynchronous
replication, no backup workflow, no verified GraphQL WebSocket subscription
reconnection, and no production hardening or observability. Read the complete
[Security Model](docs/security-model.md) and
[Limitations](docs/limitations.md).

## Project documentation

- [Architecture](docs/architecture.md)
- [Getting started](docs/getting-started.md)
- [Hasura project](docs/hasura-project.md)
- [Operations](docs/operations.md)
- [Failover scenario](docs/failover-scenario.md)
- [Security model](docs/security-model.md)
- [Limitations](docs/limitations.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Compatibility](docs/compatibility.md)
- [Verification contract](docs/verification-contract.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Support](SUPPORT.md)
- [Provenance](PROVENANCE.md) and [third-party notices](THIRD_PARTY_NOTICES.md)

## License

Repository-authored material is licensed under the
[Apache License 2.0](LICENSE). Upstream components retain their own licenses; see
[Third-Party Notices](THIRD_PARTY_NOTICES.md).
