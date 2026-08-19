#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

require_commands awk curl docker jq

switchover_stage='discover the current primary'
former_primary=''
candidate=''

stage() {
  switchover_stage=$1
  printf '\n[%s]\n' "$switchover_stage"
}

switchover_failed() {
  local exit_code=$?
  trap - ERR
  printf '\nSwitchover failed with exit code %s during: %s\n' \
    "$exit_code" "$switchover_stage" >&2
  diagnostics
  exit "$exit_code"
}
trap switchover_failed ERR

candidate_recovered() {
  primary_is "$candidate" \
    && haproxy_routes_only_to "$candidate" \
    && hasura_strict_healthy \
    && graphql_todo_visible "$SEED_TODO_TITLE"
}

restored_topology_ready() {
  former_member_streaming "$former_primary" \
    && topology_ready \
    && patronictl_topology_ready \
    && two_streaming_replicas
}

stage 'discover the current primary and select a healthy replica'
if ! former_primary=$(discover_primary); then
  printf 'Could not discover exactly one active primary.\n' >&2
  false
fi
if ! candidate=$(healthy_replica "$former_primary"); then
  printf 'Could not select a healthy replica for switchover.\n' >&2
  false
fi
printf 'Current primary: %s\nSelected candidate: %s\n' \
  "$former_primary" "$candidate"

stage "switch over from $former_primary to $candidate"
controlled_switchover "$former_primary" "$candidate"

stage 'wait for the candidate, HAProxy, strict Hasura, and GraphQL'
wait_until "$LEADERSHIP_TIMEOUT_SECONDS" \
  "$candidate to become the sole primary with exclusive writable HAProxy routing, strict Hasura health, and GraphQL recovery" \
  candidate_recovered

stage "wait for $former_primary and the full streaming topology"
wait_until "$REJOIN_TIMEOUT_SECONDS" \
  "$former_primary to rejoin with one primary and two streaming replicas" \
  restored_topology_ready

trap - ERR
printf '\nSwitchover complete: %s is the sole writable primary and %s rejoined as a streaming replica.\n' \
  "$candidate" "$former_primary"
