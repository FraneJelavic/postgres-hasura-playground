# Limitations

The playground demonstrates behavior, not a production-ready service. The
following constraints are deliberate and are not covered by the acceptance suite.

## Availability and durability

- All containers, networks, and named volumes share one Docker Engine or Colima
  host. Host, disk, runtime, and local-network failures remain single failure
  domains.
- HAProxy and Hasura each run as one process. Their restart policies help after a
  process exit but provide no redundant service endpoint.
- PostgreSQL replication is asynchronous. Abrupt primary loss can lose acknowledged
  writes that have not reached the promoted replica.
- There is no synchronous quorum policy, fencing beyond the local Patroni model,
  multi-region placement, or production split-brain remediation procedure.
- Database sessions are not preserved during leadership changes. Clients must
  reconnect and may need to retry.
- GraphQL WebSocket subscriptions and subscription reconnection across leadership
  changes are not covered or verified.

## Data protection and lifecycle

- No supported backup, restore, point-in-time recovery, archive storage, retention,
  or disaster-recovery workflow is included.
- Named volumes are local and unencrypted by the project.
- `make reset` permanently deletes all volumes for the selected Compose project.
- Schema rollback is limited to tracked down migrations; no application-level data
  rollback strategy is provided.

## Security

- Passwords and the Hasura admin secret are fixed development values.
- The Hasura console and development mode are enabled.
- There is no TLS, secret manager, external identity, network policy, fine-grained
  application authorization example, or production host hardening.
- Loopback port bindings assume a trusted local machine and trusted Docker access.

## Operations and observability

- No metrics collection, dashboards, alerting, log aggregation, tracing, audit
  export, on-call integration, or service-level objectives are included.
- No automated backup validation, capacity management, connection-pool tuning,
  rolling upgrade, certificate rotation, or dependency rollback exists.
- Resource limits and requests are not modeled. The Colima allocation is a
  development baseline, not workload sizing guidance.
- Verification covers the pinned versions and documented host architectures; it
  does not certify arbitrary version combinations or container runtimes.

## Scope

- The example application is one `todos` table and an admin-secret GraphQL flow.
- The environment does not model multiple tenants, complex authorization, large
  datasets, sustained load, long-running transactions, or schema changes during
  failover.
- Recovery time bounds in the verifier are acceptance thresholds on a local host,
  not production recovery objectives.

Use [Security Model](security-model.md) for the trust assumptions and
[Failover Scenario](failover-scenario.md) for the demonstrated recovery behavior.
