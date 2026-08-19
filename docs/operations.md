# Operations

This runbook covers the supported local lifecycle. Run commands from the repository
root and use the same port and Compose project environment for every command.

For host setup, Colima allocation, endpoint examples, and first use, follow
[Getting Started](getting-started.md).

## Start and inspect

```sh
make up
make status
```

Startup can take several minutes on a cold image cache. `make up` waits up to 240
seconds for Compose and initializer readiness. It preserves the stack for diagnosis
if a stage fails.

`make status` is the primary health command. It reports:

- every long-running Compose service and both one-shot initializers;
- all three etcd endpoint health results;
- each Patroni member and the sole primary;
- the exclusive HAProxy backend and a writable SQL query through it;
- strict Hasura health; and
- a small authenticated `todos` GraphQL query.

Any failed boundary makes the command exit nonzero.

Useful direct observations:

```sh
make logs
curl --fail --silent http://127.0.0.1:8008/patroni | jq
curl --fail --silent http://127.0.0.1:8009/patroni | jq
curl --fail --silent http://127.0.0.1:8010/patroni | jq
curl --fail --silent 'http://127.0.0.1:7000/stats;csv'
```

Strict Hasura health is authenticated:

```sh
curl --fail --silent \
  --header 'x-hasura-admin-secret: test' \
  'http://127.0.0.1:8080/healthz?strict=true'
```

## Leadership exercises

Before `make switchover` or `make failover`, require `make status` to pass. Both
commands can close existing sessions and are intended only for disposable local
data. The exact controlled-versus-abrupt behavior, time bounds, asynchronous data
risk, and reconnection rules are in [Failover Scenario](failover-scenario.md).

## Stop, restart, and reset

Preserve all data:

```sh
make down
make up
```

Delete all data owned by this Compose project:

```sh
make reset
```

Interactive reset requires typing the exact Compose project name. Automation must
opt in explicitly:

```sh
CONFIRM_RESET=YES make reset
```

Reset is irreversible unless the Docker volumes were backed up externally. The
playground has no supported backup or restore workflow.

## Full verification

```sh
make verify
```

The verifier is destructive to running database leadership and temporarily takes
the stack down, but it preserves named volumes. It creates uniquely named test
todos. Read the [verification contract](verification-contract.md) for the ordered
scenario, assertions, and time bounds.

## Troubleshooting

Use the focused [Troubleshooting](troubleshooting.md) guide for Docker and Colima,
resource and port conflicts, initializer state, Patroni topology, HAProxy routing,
strict Hasura health, GraphQL errors, and disposable recovery.
