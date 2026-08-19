#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

require_commands awk curl docker jq || exit 1

status_failed=0

section() {
  printf '\n[%s]\n' "$1"
}

boundary_ok() {
  printf 'OK: %s\n' "$1"
}

boundary_failed() {
  printf 'FAIL: %s\n' "$1" >&2
  status_failed=1
}

section 'Compose services'
if compose ps --all; then
  compose_services_healthy=1
  for service in etcd1 etcd2 etcd3 postgres1 postgres2 postgres3 haproxy hasura; do
    details=$(compose_service_details "$service")
    state=$(jq -r '.State // "missing"' <<<"$details")
    health=$(jq -r '.Health // "missing"' <<<"$details")
    if [[ "$state" != running || "$health" != healthy ]]; then
      printf 'Unhealthy service: %s (state=%s, health=%s)\n' \
        "$service" "$state" "$health" >&2
      compose_services_healthy=0
    fi
  done
  if ((compose_services_healthy == 1)); then
    boundary_ok 'all long-running Compose services are running and healthy'
  else
    boundary_failed 'one or more long-running Compose services are unhealthy'
  fi
else
  boundary_failed 'Compose service state is unavailable'
fi

section 'etcd cluster'
if etcd_health=$(compose exec -T etcd1 etcdctl \
  --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 \
  endpoint health --cluster 2>&1); then
  printf '%s\n' "$etcd_health"
  boundary_ok 'all etcd cluster endpoints are healthy'
else
  printf '%s\n' "$etcd_health" >&2
  boundary_failed 'etcd cluster health check failed'
fi

section 'Patroni members'
primary=''
primary_count=0
replica_count=0
patroni_members_healthy=1
for service in postgres1 postgres2 postgres3; do
  port=$(patroni_port "$service")
  if member_response=$(curl --connect-timeout 1 --max-time 3 --fail --silent \
    "http://127.0.0.1:${port}/patroni"); then
    member_state=$(jq -r '.state // "unknown"' <<<"$member_response")
    if patroni_endpoint_ready "$service" primary; then
      member_role=primary
      primary=$service
      primary_count=$((primary_count + 1))
    elif patroni_endpoint_ready "$service" replica; then
      member_role=replica
      replica_count=$((replica_count + 1))
    else
      member_role=unknown
      patroni_members_healthy=0
    fi
    printf '%s: state=%s role=%s\n' "$service" "$member_state" "$member_role"
    if [[ "$member_state" != running ]]; then
      patroni_members_healthy=0
    fi
  else
    printf '%s: API unavailable\n' "$service" >&2
    patroni_members_healthy=0
  fi
done

if ((patroni_members_healthy == 1 && primary_count == 1 && replica_count == 2)); then
  boundary_ok "Patroni has sole primary $primary and two replicas"
else
  boundary_failed \
    "Patroni topology is unhealthy (primaries=$primary_count, replicas=$replica_count)"
fi

section 'HAProxy primary route'
haproxy_route_healthy=1
up_backends=()
if stats=$(haproxy_stats 2>&1); then
  awk -F, '
    $1 == "postgres_primary" && $2 ~ /^postgres[123]$/ {
      printf "%s: status=%s\n", $2, $18
    }
  ' <<<"$stats"
  while IFS= read -r backend; do
    [[ -n "$backend" ]] && up_backends+=("$backend")
  done < <(
    awk -F, '
      $1 == "postgres_primary" && $2 ~ /^postgres[123]$/ && $18 == "UP" {
        print $2
      }
    ' <<<"$stats"
  )
  if ((${#up_backends[@]} != 1)) || [[ "${up_backends[0]:-}" != "$primary" ]]; then
    haproxy_route_healthy=0
  fi
else
  printf '%s\n' "$stats" >&2
  haproxy_route_healthy=0
fi

if writable=$(sql_via_haproxy -Atc 'SELECT NOT pg_is_in_recovery();' 2>/dev/null); then
  printf 'SQL route writable: %s\n' "$writable"
  [[ "$writable" == t ]] || haproxy_route_healthy=0
else
  printf 'SQL route unavailable\n' >&2
  haproxy_route_healthy=0
fi

if ((haproxy_route_healthy == 1)); then
  boundary_ok "HAProxy routes exclusively to writable primary $primary"
else
  boundary_failed 'HAProxy does not route exclusively to the writable Patroni primary'
fi

section 'Hasura strict health'
if strict_health=$(curl --connect-timeout 1 --max-time 5 --fail --silent \
  --header "x-hasura-admin-secret: $HASURA_ADMIN_SECRET" \
  "http://127.0.0.1:${HASURA_HOST_PORT}/healthz?strict=true" 2>&1) \
  && [[ "$strict_health" == OK ]]; then
  printf 'Response: %s\n' "$strict_health"
  boundary_ok 'Hasura strict health check passed'
else
  printf 'Response: %s\n' "${strict_health:-unavailable}" >&2
  boundary_failed 'Hasura strict health check failed'
fi

section 'Initializer state'
initializers_healthy=1
for service in database-init hasura-init; do
  details=$(compose_service_details "$service")
  state=$(jq -r '.State // "missing"' <<<"$details")
  exit_code=$(jq -r '.ExitCode // "missing"' <<<"$details")
  printf '%s: state=%s exit_code=%s\n' "$service" "$state" "$exit_code"
  if [[ "$state" != exited || "$exit_code" != 0 ]]; then
    initializers_healthy=0
  fi
done
if ((initializers_healthy == 1)); then
  boundary_ok 'database-init and hasura-init completed successfully'
else
  boundary_failed 'one or more initializers did not complete successfully'
fi

section 'Authenticated todos query'
todos_payload=$(jq -cn '{
  query: "query StatusTodos { todos(limit: 3, order_by: {id: asc}) { id title completed } }"
}')
if todos_response=$(graphql_request "$todos_payload" 2>/dev/null) \
  && jq -e '.data.todos | type == "array"' <<<"$todos_response" >/dev/null; then
  jq -c '.data.todos' <<<"$todos_response"
  boundary_ok 'authenticated todos query succeeded'
else
  boundary_failed 'authenticated todos query failed'
fi

printf '\n'
if ((status_failed == 0)); then
  printf 'Status passed: every service boundary is healthy.\n'
else
  printf 'Status failed: one or more service boundaries are unhealthy.\n' >&2
fi
exit "$status_failed"
