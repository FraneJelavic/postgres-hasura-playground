# Verification Contract

`make verify` is this repository's executable acceptance contract. It validates the
complete Docker Compose environment; there is intentionally no unit-test framework
or second runtime test harness.

The verifier preserves containers and named volumes when an assertion fails. Its
error output identifies the active verification stage and prints Compose state and
logs, initializer status, each Patroni API, etcd cluster health, HAProxy statistics,
Hasura strict health, and the last GraphQL response.

## Time bounds

- Compose and initializer readiness: 240 seconds.
- Each leadership change, HAProxy reroute, and GraphQL recovery: 60 seconds.
- A former primary rejoining as a streaming replica: 120 seconds.

The controlled-switchover and abrupt-failover recovery checks include the new sole
primary, the exclusive HAProxy route, a writable SQL route, and a successful
authenticated GraphQL query in the same bounded wait. GraphQL transport failures
and GraphQL `errors` payloads are retryable only inside those recovery waits.

## Ordered scenario

The verifier performs these steps in order:

1. Validate the rendered Compose model, build the PostgreSQL/Patroni image, and
   start Hasura with its database dependencies. Require `database-init` to finish
   successfully and ordinary `GET /healthz` to succeed with `OK` or `WARN`.
2. Only after ordinary Hasura health succeeds, start `hasura-init`. Require it to
   finish successfully, then require post-deploy `GET /healthz?strict=true` to
   return `OK`.
3. Require three healthy etcd voters, exactly one Patroni primary, two streaming
   replicas, and exactly one `UP` HAProxy backend matching that primary. A SQL query
   through `haproxy:5432` must confirm the route is writable.
4. Require `wal_level=replica` and zero logical replication slots. Patroni-managed
   physical slots are expected and are not rejected.
5. Require `GET /healthz?strict=true` to return `OK`, then query the single seeded
   todo through authenticated GraphQL.
6. Insert and read a uniquely named todo through GraphQL, then query every
   PostgreSQL member directly until the row is present everywhere.
7. Select a healthy replica, run a non-interactive Patroni controlled switchover,
   and require the chosen candidate, HAProxy, writable SQL, and GraphQL to recover
   within 60 seconds. The former primary must stream again within 120 seconds.
8. Insert and read a second unique todo, then wait until all three members contain
   it before the destructive failure step.
9. Abruptly kill the current primary. Within 60 seconds, require a different sole
   primary, exclusive HAProxy rerouting, writable SQL, and a successful GraphQL
   query. Restart the killed member and require it to rejoin as a streaming replica
   within 120 seconds.
10. Run `docker compose down` without `--volumes`, then start the stack again from
    the preserved named volumes. Re-run both one-shot initializers in the same
    ordinary-health-then-strict-health order and require healthy topology, exactly
    one seed row, and both inserted todos to remain visible. This second successful
    initializer run is the executable idempotence check.

## Failure semantics

PostgreSQL replication is asynchronous. Before either leadership change, the
verifier waits for the relevant todo to exist on every member. This makes the test's
replication precondition explicit; it is not a production zero-data-loss guarantee.

Existing PostgreSQL or GraphQL requests can fail while Patroni promotes a member and
HAProxy closes connections to the demoted backend. The contract requires bounded
recovery, not uninterrupted requests. Clients are expected to retry or reconnect.

The fixed PostgreSQL passwords and Hasura admin secret are all `test`. They are
intentional local-development credentials and must not be interpreted as a
production security model.

## Direct invocation and customization

The normal entry point is:

```sh
make verify
```

The scripts default to project name `postgres-hasura-playground` and loopback ports
5432 (PostgreSQL through HAProxy), 7000 (HAProxy statistics), 8008-8010 (Patroni),
and 8080 (Hasura). Compose-supported environment overrides may change those ports.
`SEED_TODO_TITLE` may be overridden only when the tracked idempotent seed uses the
same title; its default is `Seeded playground todo`.
