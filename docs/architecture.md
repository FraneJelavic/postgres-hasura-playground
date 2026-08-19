# Architecture

This playground demonstrates a highly available PostgreSQL write route behind a
Hasura GraphQL API on one development host. It favors explicit, inspectable
behavior over production breadth.

## System context

![System context](c4/context.png)

A developer uses Make commands, SQL clients, or HTTP clients from the host. Docker
Compose owns the application network, services, and named volumes. Only loopback
interfaces needed for development and inspection are published.

## Containers

![Container view](c4/containers.png)

| Component | Count | Responsibility | Persistent state |
|---|---:|---|---|
| PostgreSQL + Patroni | 3 | Database process, leader participation, streaming replication, member API | One named data volume per member |
| etcd | 3 | Patroni distributed configuration and leader state | One named data volume per voter |
| HAProxy | 1 | Route database connections only to the Patroni primary | None |
| Database initializer | 1 one-shot | Create application and metadata roles and databases idempotently | Changes PostgreSQL state |
| Hasura GraphQL Engine | 1 | Serve the console, health endpoints, and GraphQL API | Metadata stored in PostgreSQL |
| Hasura initializer | 1 one-shot | Apply tracked migrations, metadata, and seeds | Changes application and metadata databases |

## Startup and initialization

`make up` enforces this order:

1. Validate the rendered Compose model and build the shared Patroni image.
2. Start three etcd voters and three PostgreSQL members.
3. Wait until HAProxy sees exactly one primary backend.
4. Run `database-init` and require exit code zero.
5. Start Hasura and wait for ordinary health.
6. Run `hasura-init` to deploy migrations, metadata, and seeds; require exit code
   zero.
7. Require strict Hasura health, one Patroni primary, two streaming replicas, and
   two PostgreSQL replication senders.

The initializer SQL and seed are idempotent. Re-running the one-shot containers
against preserved volumes must succeed without duplicating the seeded todo.
The database separation and tracked layout are detailed in
[Hasura Project](hasura-project.md).

## Request paths

### SQL

A host SQL client connects to HAProxy at `127.0.0.1:5432`. HAProxy checks each
member's Patroni `/primary` endpoint. It marks exactly the current primary `UP` and
closes connections to a member that stops being primary. The individual member
database ports are available only inside the Compose network.

### GraphQL

An HTTP client connects directly to Hasura at `127.0.0.1:8080`. Hasura's metadata
database and tracked `app` source both use HAProxy as their PostgreSQL host. Hasura
therefore follows the same writable route after a promotion. Strict health checks
both metadata consistency and source reachability.

### Control plane

Patroni members use the internal etcd endpoints for leader state. The three etcd
voters' client and peer ports are not published to the host. Patroni member APIs
are published on loopback ports 8008 through 8010 for inspection and HA exercises.

## Leadership and replication

Patroni permits one primary and two replicas. PostgreSQL streaming replication is
asynchronous. A controlled switchover asks Patroni to promote a healthy replica and
demote the old primary. An abrupt exercise kills the current primary and lets the
remaining quorum elect and promote a replacement.

HAProxy health polling eventually removes the former primary and admits the new
one. Connections attached to the old backend are closed. Hasura and other clients
must establish a new connection; transient failures are therefore part of the
documented recovery model. The repository requires recovery within 60 seconds and
former-member rejoin within 120 seconds in its acceptance workflow.

Because replication is asynchronous, successful commit acknowledgement does not
mean every replica has received the write. This topology does not guarantee zero
data loss after abrupt primary loss. See [Failover Scenario](failover-scenario.md)
for operator steps and client reconnection expectations.

## Storage and lifecycle

Six named volumes persist the three etcd data directories and three PostgreSQL data
directories. Hasura metadata and application data live in PostgreSQL, so Hasura
containers themselves are stateless.

`make down` removes containers and the network but preserves named volumes. A later
`make up` reuses the cluster and re-runs idempotent initialization. `make reset`
removes only volumes labeled for this Compose project after explicit confirmation.

## Trust boundaries

All published ports bind to `127.0.0.1`, while etcd and individual member database
ports remain internal. This is not a hardened sandbox. The complete assumptions are
in [Security Model](security-model.md).

## Deliberate exclusions

Cross-host availability, synchronous durability, data protection, production
security, observability, upgrades, and capacity controls are intentionally out of
scope. See [Limitations](limitations.md) for the complete boundary.
