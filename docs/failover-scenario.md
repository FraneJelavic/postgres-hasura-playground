# Failover Scenario

The playground provides one controlled leadership exercise and one abrupt-loss
exercise. Both are destructive to existing database sessions and must be run only
against disposable local data.

## Controlled and abrupt behavior

| Property | `make switchover` | `make failover` |
|---|---|---|
| Trigger | Patroni controlled switchover | Immediate kill of the current primary container |
| Target | Preselected healthy replica | Any eligible member selected by Patroni |
| Former primary | Demoted while participating | Unavailable until the script restarts it |
| Data-risk intent | Planned role movement | Demonstrates asynchronous failure risk |
| Success condition | Candidate primary, writable route, API recovery, former member streaming | Different primary, writable route, API recovery, killed member streaming |

## Preconditions

Require a completely healthy baseline before either exercise:

```sh
make status
```

The command must report three healthy etcd voters, one Patroni primary, two
replicas, one matching `UP` HAProxy backend, writable SQL, strict Hasura health,
successful initializers, and an authenticated GraphQL query.

## Controlled switchover

```sh
make switchover
```

The workflow discovers the current primary, selects the first healthy replica,
asks Patroni to switch to that candidate, and waits for:

1. the candidate to be the sole primary;
2. HAProxy to route exclusively to that primary and a SQL query to confirm the
   route is writable;
3. strict Hasura health and the seeded GraphQL query to recover; and
4. the former primary to rejoin a one-primary/two-streaming-replica topology.

Use this scenario to understand planned maintenance behavior. Do not interrupt the
script after Patroni accepts the switchover.

## Abrupt primary loss

```sh
make failover
```

The workflow discovers and kills the current primary container, waits for a
different sole primary and the same writable/API checks, restarts the killed
member, and waits for it to rejoin as a streaming replica. If the workflow fails
after the kill, its error handler attempts to restart that member before exiting.

Leadership and client-path recovery are bounded by 60 seconds. Former-member
streaming rejoin is bounded by 120 seconds.

## Reconnection expectations

HAProxy removes a backend when Patroni no longer reports it as primary. Existing
TCP sessions attached to that backend can be closed. During either scenario:

- a long-lived `psql` session can fail and must be opened again;
- a pool must discard broken connections and reconnect to `127.0.0.1:5432`;
- SQL and GraphQL callers can observe transient errors during promotion;
- automatic retries need bounded backoff and must account for whether an operation
  is safe to repeat; and
- clients must use HAProxy rather than an internal member address.

An open TCP port does not by itself prove recovery. Run `make status` after the
exercise and require the complete topology, writable route, strict health, and
GraphQL result.

## Asynchronous replication boundary

Replication is asynchronous. A commit acknowledged by the former primary may not
yet exist on the promoted replica, so abrupt loss can lose recent writes. The
playground provides no zero-data-loss guarantee.

`make verify` reduces ambiguity in its test scenario by waiting for each marker row
to appear on all three members before disrupting leadership. That is an executable
test precondition, not a production durability guarantee. See the
[verification contract](verification-contract.md) for the full sequence.
