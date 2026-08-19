#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

require_commands curl docker jq

startup_stage='initialization'

stage() {
  startup_stage=$1
  printf '\n[%s]\n' "$startup_stage"
}

startup_failed() {
  local exit_code=$?
  trap - ERR
  printf '\nStartup failed with exit code %s during: %s\n' \
    "$exit_code" "$startup_stage" >&2
  diagnostics
  exit "$exit_code"
}
trap startup_failed ERR

stage 'validate the Compose model'
compose config --quiet

stage 'build the shared PostgreSQL and Patroni image'
compose build --pull postgres1

stage 'start Hasura and its dependencies'
compose up --detach hasura

stage 'wait for database initialization'
wait_for_initializers "$COMPOSE_READINESS_TIMEOUT_SECONDS" database-init

stage 'wait for ordinary Hasura health'
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  'ordinary Hasura health before metadata deployment' hasura_healthy

stage 'deploy Hasura metadata, migrations, and seeds'
compose up --detach hasura-init
wait_for_initializers "$COMPOSE_READINESS_TIMEOUT_SECONDS" hasura-init

stage 'wait for strict Hasura health'
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  'strict Hasura health after metadata deployment' hasura_strict_healthy

stage 'wait for one primary and two replicas'
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  'one Patroni primary and two replicas' topology_ready
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  'one running leader and two streaming replicas in patronictl' patronictl_topology_ready
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  'two PostgreSQL streaming replicas' two_streaming_replicas

runner=$(first_running_postgres)
compose exec -T "$runner" patronictl list

trap - ERR
printf '\nPlayground is ready.\n'
printf 'Hasura console:  http://127.0.0.1:%s/console\n' "$HASURA_HOST_PORT"
printf 'GraphQL endpoint: http://127.0.0.1:%s/v1/graphql\n' "$HASURA_HOST_PORT"
printf 'PostgreSQL:       postgresql://postgres:test@127.0.0.1:%s/postgres\n' \
  "${POSTGRES_HOST_PORT:-5432}"
printf 'HAProxy stats:    http://127.0.0.1:%s/stats\n' "$HAPROXY_STATS_HOST_PORT"
printf 'Patroni APIs:     http://127.0.0.1:%s, http://127.0.0.1:%s, http://127.0.0.1:%s\n' \
  "$PATRONI1_HOST_PORT" "$PATRONI2_HOST_PORT" "$PATRONI3_HOST_PORT"
