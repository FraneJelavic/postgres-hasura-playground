#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

require_commands awk curl docker jq

verification_stage='initialization'

stage() {
  verification_stage=$1
  printf '\n[%s]\n' "$verification_stage"
}

verification_failed() {
  local exit_code=$?
  trap - ERR
  printf '\nVerification failed with exit code %s during: %s\n' \
    "$exit_code" "$verification_stage" >&2
  diagnostics
  exit "$exit_code"
}
trap verification_failed ERR

leadership_and_graphql_ready() {
  local expected_primary=$1 todo_title=$2
  primary_is "$expected_primary" \
    && haproxy_routes_only_to "$expected_primary" \
    && graphql_todo_visible "$todo_title"
}

start_and_initialize_stack() {
  compose up --detach hasura
  wait_for_initializers "$COMPOSE_READINESS_TIMEOUT_SECONDS" database-init
  wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
    'ordinary Hasura health before metadata deployment' hasura_healthy

  compose up --detach hasura-init
  wait_for_initializers "$COMPOSE_READINESS_TIMEOUT_SECONDS" hasura-init
  wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
    'strict Hasura health after metadata deployment' hasura_strict_healthy
}

different_primary_and_graphql_ready() {
  local former_primary=$1 todo_title=$2 candidate
  candidate=$(discover_primary 2>/dev/null || true)
  [[ -n "$candidate" && "$candidate" != "$former_primary" ]] \
    && haproxy_routes_only_to "$candidate" \
    && graphql_todo_visible "$todo_title"
}

stage 'validate the Compose model, build the Patroni image, and start the stack'
compose config --quiet
compose build --pull postgres1
start_and_initialize_stack

stage 'verify etcd, Patroni, streaming replication, and HAProxy routing'
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  'one Patroni primary and two replicas' topology_ready
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  'one running leader and two streaming replicas in patronictl' patronictl_topology_ready
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  'two PostgreSQL streaming replicas' two_streaming_replicas
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  'three healthy etcd voters' etcd_cluster_healthy
initial_primary=$(discover_primary)
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  "HAProxy to route exclusively to $initial_primary" \
  haproxy_routes_only_to "$initial_primary"

stage 'verify replica WAL configuration and absence of logical slots'
wal_level=$(sql_via_haproxy -Atc 'SHOW wal_level;')
[[ "$wal_level" == replica ]]
logical_slot_count=$(sql_via_haproxy -Atc \
  "SELECT count(*) FROM pg_replication_slots WHERE slot_type = 'logical';")
[[ "$logical_slot_count" == 0 ]]

stage 'verify post-deploy strict Hasura health and the idempotent seed'
hasura_strict_healthy
graphql_todo_visible "$SEED_TODO_TITLE"
seed_count=$(graphql_todo_count "$SEED_TODO_TITLE")
[[ "$seed_count" == 1 ]]

stage 'insert a todo through GraphQL and wait for all PostgreSQL members'
pre_switchover_todo=$(unique_todo_title pre-switchover)
graphql_insert_todo "$pre_switchover_todo"
graphql_todo_visible "$pre_switchover_todo"
wait_until "$LEADERSHIP_TIMEOUT_SECONDS" \
  "todo '$pre_switchover_todo' to reach all PostgreSQL members" \
  todo_on_all_members "$pre_switchover_todo"

stage 'perform a controlled switchover and recover GraphQL within 60 seconds'
switchover_former_primary=$(discover_primary)
switchover_candidate=$(healthy_replica "$switchover_former_primary")
controlled_switchover "$switchover_former_primary" "$switchover_candidate"
wait_until "$LEADERSHIP_TIMEOUT_SECONDS" \
  "controlled switchover to $switchover_candidate with HAProxy and GraphQL recovery" \
  leadership_and_graphql_ready "$switchover_candidate" "$pre_switchover_todo"
wait_until "$REJOIN_TIMEOUT_SECONDS" \
  "$switchover_former_primary to stream after controlled switchover" \
  former_member_streaming "$switchover_former_primary"
wait_until "$REJOIN_TIMEOUT_SECONDS" \
  'the restored one-primary/two-replica topology after controlled switchover' \
  topology_ready

stage 'insert another todo and make asynchronous catch-up explicit'
pre_failover_todo=$(unique_todo_title pre-failover)
graphql_insert_todo "$pre_failover_todo"
graphql_todo_visible "$pre_failover_todo"
wait_until "$LEADERSHIP_TIMEOUT_SECONDS" \
  "todo '$pre_failover_todo' to reach all PostgreSQL members" \
  todo_on_all_members "$pre_failover_todo"

stage 'kill the active primary and recover HAProxy and GraphQL within 60 seconds'
failed_primary=$(discover_primary)
abrupt_primary_kill "$failed_primary"
wait_until "$LEADERSHIP_TIMEOUT_SECONDS" \
  "promotion away from $failed_primary with HAProxy and GraphQL recovery" \
  different_primary_and_graphql_ready "$failed_primary" "$pre_failover_todo"
failover_primary=$(discover_primary)

stage 'restart the killed member and require streaming-replica rejoin'
compose start "$failed_primary" >/dev/null
wait_until "$REJOIN_TIMEOUT_SECONDS" \
  "$failed_primary to rejoin as a streaming replica" \
  former_member_streaming "$failed_primary"
wait_until "$LEADERSHIP_TIMEOUT_SECONDS" \
  'the restored one-primary/two-replica topology' topology_ready
wait_until "$LEADERSHIP_TIMEOUT_SECONDS" \
  "pre-switchover todo '$pre_switchover_todo' on all members after rejoin" \
  todo_on_all_members "$pre_switchover_todo"
wait_until "$LEADERSHIP_TIMEOUT_SECONDS" \
  "pre-failover todo '$pre_failover_todo' on all members after rejoin" \
  todo_on_all_members "$pre_failover_todo"

stage 'take the stack down without deleting volumes, then rerun both initializers'
compose down
start_and_initialize_stack

stage 'prove topology, initialization, GraphQL metadata, seeds, and todos persisted'
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  'topology after non-destructive restart' topology_ready
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  'streaming replication after non-destructive restart' two_streaming_replicas
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  'three healthy etcd voters after non-destructive restart' etcd_cluster_healthy
restart_primary=$(discover_primary)
wait_until "$COMPOSE_READINESS_TIMEOUT_SECONDS" \
  "HAProxy to route exclusively to $restart_primary after restart" \
  haproxy_routes_only_to "$restart_primary"
hasura_strict_healthy
graphql_todo_visible "$SEED_TODO_TITLE"
[[ $(graphql_todo_count "$SEED_TODO_TITLE") == 1 ]]
graphql_todo_visible "$pre_switchover_todo"
graphql_todo_visible "$pre_failover_todo"

trap - ERR
printf '\nVerification passed: controlled switchover %s -> %s; abrupt failover %s -> %s; rejoin and persistence succeeded.\n' \
  "$switchover_former_primary" "$switchover_candidate" \
  "$failed_primary" "$failover_primary"
