#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

require_commands awk curl docker jq

failover_stage='discover the current primary'
failed_primary=''
new_primary=''
killed_member=0
member_restarted=0

stage() {
  failover_stage=$1
  printf '\n[%s]\n' "$failover_stage"
}

restart_killed_member() {
  if ((killed_member == 1 && member_restarted == 0)); then
    printf '\nRestarting killed member %s before exit.\n' "$failed_primary" >&2
    if compose start "$failed_primary" >/dev/null; then
      member_restarted=1
    else
      printf 'Could not restart killed member %s.\n' "$failed_primary" >&2
    fi
  fi
}

failover_failed() {
  local exit_code=$?
  trap - ERR
  printf '\nFailover failed with exit code %s during: %s\n' \
    "$exit_code" "$failover_stage" >&2
  diagnostics
  restart_killed_member
  exit "$exit_code"
}
trap failover_failed ERR

different_primary_recovered() {
  local candidate
  candidate=$(discover_primary 2>/dev/null || true)
  [[ -n "$candidate" && "$candidate" != "$failed_primary" ]] \
    && haproxy_routes_only_to "$candidate" \
    && hasura_strict_healthy \
    && graphql_todo_visible "$SEED_TODO_TITLE"
}

restored_topology_ready() {
  former_member_streaming "$failed_primary" \
    && topology_ready \
    && patronictl_topology_ready \
    && two_streaming_replicas
}

stage 'discover the current primary'
if ! failed_primary=$(discover_primary); then
  printf 'Could not discover exactly one active primary.\n' >&2
  false
fi
printf 'Current primary: %s\n' "$failed_primary"

stage "kill $failed_primary abruptly"
abrupt_primary_kill "$failed_primary"
killed_member=1
printf 'Killed primary: %s\n' "$failed_primary"

stage 'wait for a different primary, HAProxy, strict Hasura, and GraphQL'
wait_until "$LEADERSHIP_TIMEOUT_SECONDS" \
  "promotion away from $failed_primary with exclusive writable HAProxy routing, strict Hasura health, and GraphQL recovery" \
  different_primary_recovered
new_primary=$(discover_primary)
printf 'Promoted primary: %s\n' "$new_primary"

stage "restart $failed_primary and wait for full streaming topology"
compose start "$failed_primary" >/dev/null
member_restarted=1
wait_until "$REJOIN_TIMEOUT_SECONDS" \
  "$failed_primary to rejoin with one primary and two streaming replicas" \
  restored_topology_ready

trap - ERR
printf '\nFailover complete: %s was killed, %s became the sole writable primary, and %s rejoined as a streaming replica.\n' \
  "$failed_primary" "$new_primary" "$failed_primary"
