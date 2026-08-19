#!/usr/bin/env bash

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

: "${COMPOSE_PROJECT_NAME:=postgres-hasura-playground}"
: "${COMPOSE_READINESS_TIMEOUT_SECONDS:=240}"
: "${LEADERSHIP_TIMEOUT_SECONDS:=60}"
: "${REJOIN_TIMEOUT_SECONDS:=120}"
: "${PATRONI1_HOST_PORT:=8008}"
: "${PATRONI2_HOST_PORT:=8009}"
: "${PATRONI3_HOST_PORT:=8010}"
: "${HAPROXY_STATS_HOST_PORT:=7000}"
: "${HASURA_HOST_PORT:=8080}"
: "${HASURA_ADMIN_SECRET:=test}"
: "${POSTGRES_SUPERUSER_PASSWORD:=test}"
: "${SEED_TODO_TITLE:=Seeded playground todo}"

export COMPOSE_PROJECT_NAME

graphql_response_file=${GRAPHQL_RESPONSE_FILE:-"$root_dir/.state/last-graphql-response.json"}

require_commands() {
  local missing=0 command_name
  for command_name in "$@"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      printf 'Missing required command: %s\n' "$command_name" >&2
      missing=1
    fi
  done
  ((missing == 0))
}

compose() {
  docker compose \
    --project-directory "$root_dir" \
    --project-name "$COMPOSE_PROJECT_NAME" \
    "$@"
}

wait_until() {
  local timeout_seconds=$1 description=$2
  shift 2
  local deadline=$((SECONDS + timeout_seconds))

  while true; do
    # Readiness predicates are expected to fail transiently. Run each probe in a
    # subshell without the caller's ERR trap so an intermediate curl/psql error
    # becomes a retry instead of aborting the enclosing verification script.
    if (
      trap - ERR
      set +e
      set +E
      "$@"
    ); then
      return 0
    fi
    if ((SECONDS >= deadline)); then
      printf 'Timed out after %ss waiting for %s.\n' "$timeout_seconds" "$description" >&2
      return 1
    fi
    sleep 2
  done
}

compose_service_details() {
  local service=$1
  compose ps --all --format json "$service" 2>/dev/null \
    | jq -sr '[.[] | if type == "array" then .[] else . end] | .[0] // {}'
}

wait_for_initializers() {
  local timeout_seconds=$1
  shift
  local deadline=$((SECONDS + timeout_seconds))
  local all_complete details exit_code service state

  while true; do
    all_complete=1
    for service in "$@"; do
      details=$(compose_service_details "$service")
      state=$(jq -r '.State // empty' <<<"$details")
      exit_code=$(jq -r '.ExitCode // empty' <<<"$details")

      if [[ "$state" == exited ]]; then
        if [[ "$exit_code" != 0 ]]; then
          printf 'Initializer %s exited with code %s.\n' "$service" "$exit_code" >&2
          return 1
        fi
      else
        all_complete=0
      fi
    done

    ((all_complete == 1)) && return 0
    if ((SECONDS >= deadline)); then
      printf 'Timed out after %ss waiting for initializers: %s\n' \
        "$timeout_seconds" "$*" >&2
      return 1
    fi
    sleep 2
  done
}

patroni_port() {
  case "$1" in
    postgres1) printf '%s\n' "$PATRONI1_HOST_PORT" ;;
    postgres2) printf '%s\n' "$PATRONI2_HOST_PORT" ;;
    postgres3) printf '%s\n' "$PATRONI3_HOST_PORT" ;;
    *) return 1 ;;
  esac
}

patroni_endpoint_ready() {
  local service=$1 endpoint=$2 port
  port=$(patroni_port "$service")
  curl --connect-timeout 1 --max-time 2 --fail --silent \
    "http://127.0.0.1:${port}/${endpoint}" >/dev/null 2>&1
}

discover_primary() {
  local service primary=''
  for service in postgres1 postgres2 postgres3; do
    if patroni_endpoint_ready "$service" primary; then
      if [[ -n "$primary" ]]; then
        printf 'Multiple primaries detected: %s and %s\n' "$primary" "$service" >&2
        return 1
      fi
      primary=$service
    fi
  done
  [[ -n "$primary" ]] || return 1
  printf '%s\n' "$primary"
}

primary_is() {
  local expected=$1 actual
  actual=$(discover_primary 2>/dev/null || true)
  [[ "$actual" == "$expected" ]]
}

first_running_postgres() {
  local running service
  running=$(compose ps --status running --services 2>/dev/null || true)
  for service in postgres1 postgres2 postgres3; do
    if grep -qx "$service" <<<"$running"; then
      printf '%s\n' "$service"
      return 0
    fi
  done
  return 1
}

sql_via_haproxy() {
  local runner
  runner=$(first_running_postgres)
  compose exec -T \
    --env "PGPASSWORD=$POSTGRES_SUPERUSER_PASSWORD" \
    "$runner" psql -X -v ON_ERROR_STOP=1 \
    -h haproxy -p 5432 -U postgres -d postgres "$@"
}

topology_ready() {
  local primary_count=0 replica_count=0 service
  for service in postgres1 postgres2 postgres3; do
    if patroni_endpoint_ready "$service" primary; then
      primary_count=$((primary_count + 1))
    elif patroni_endpoint_ready "$service" replica; then
      replica_count=$((replica_count + 1))
    fi
  done
  [[ $primary_count -eq 1 && $replica_count -eq 2 ]]
}

patronictl_topology_ready() {
  local runner topology
  runner=$(first_running_postgres) || return 1
  topology=$(compose exec -T "$runner" patronictl list --format json 2>/dev/null) || return 1
  jq -e '
    length == 3
    and ([.[] | select(.Role == "Leader" and .State == "running")] | length == 1)
    and ([.[] | select(.Role == "Replica" and .State == "streaming")] | length == 2)
  ' <<<"$topology" >/dev/null
}

two_streaming_replicas() {
  [[ $(sql_via_haproxy -Atc \
    "SELECT count(*) FROM pg_stat_replication
     WHERE state = 'streaming'
       AND application_name IN ('postgres1', 'postgres2', 'postgres3');" \
    2>/dev/null) == 2 ]]
}

etcd_cluster_healthy() {
  compose exec -T etcd1 etcdctl \
    --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 \
    endpoint health --cluster >/dev/null 2>&1
}

haproxy_stats() {
  curl --connect-timeout 1 --max-time 3 --fail --silent \
    "http://127.0.0.1:${HAPROXY_STATS_HOST_PORT}/stats;csv"
}

haproxy_routes_only_to() {
  local expected_primary=$1 writable
  haproxy_stats 2>/dev/null \
    | awk -F, -v expected="$expected_primary" '
        $1 == "postgres_primary" && $2 ~ /^postgres/ && $18 == "UP" {
          up++
          if ($2 == expected) {
            expected_up++
          }
        }
        END { exit !(up == 1 && expected_up == 1) }
      ' || return 1

  writable=$(sql_via_haproxy -Atc 'SELECT NOT pg_is_in_recovery();' 2>/dev/null) || return 1
  [[ "$writable" == t ]]
}

hasura_strict_healthy() {
  local response
  response=$(curl --connect-timeout 1 --max-time 5 --fail --silent \
    --header "x-hasura-admin-secret: $HASURA_ADMIN_SECRET" \
    "http://127.0.0.1:${HASURA_HOST_PORT}/healthz?strict=true" 2>/dev/null) || return 1
  [[ "$response" == OK ]]
}

hasura_healthy() {
  local response
  response=$(curl --connect-timeout 1 --max-time 5 --fail --silent \
    --header "x-hasura-admin-secret: $HASURA_ADMIN_SECRET" \
    "http://127.0.0.1:${HASURA_HOST_PORT}/healthz" 2>/dev/null) || return 1
  [[ "$response" == OK || "$response" == WARN ]]
}

hasura_databases_and_roles_ready() {
  local expected_owners expected_roles owners roles runner role database current_user

  expected_owners=$'app:hasura_app\nhasura_metadata:hasura_metadata'
  owners=$(sql_via_haproxy -Atc \
    "SELECT datname || ':' || pg_get_userbyid(datdba)
     FROM pg_database
     WHERE datname IN ('app', 'hasura_metadata')
     ORDER BY datname;" 2>/dev/null) || return 1
  [[ "$owners" == "$expected_owners" ]] || return 1

  expected_roles=$'hasura_app:true\nhasura_metadata:true'
  roles=$(sql_via_haproxy -Atc \
    "SELECT rolname || ':' || rolcanlogin
     FROM pg_roles
     WHERE rolname IN ('hasura_app', 'hasura_metadata')
     ORDER BY rolname;" 2>/dev/null) || return 1
  [[ "$roles" == "$expected_roles" ]] || return 1

  runner=$(first_running_postgres) || return 1
  while IFS=: read -r role database; do
    current_user=$(compose exec -T --env "PGPASSWORD=test" "$runner" \
      psql -XAt -v ON_ERROR_STOP=1 -h haproxy -p 5432 \
      -U "$role" -d "$database" -c 'SELECT current_user;' 2>/dev/null) || return 1
    [[ "$current_user" == "$role" ]] || return 1
  done <<'EOF'
hasura_app:app
hasura_metadata:hasura_metadata
EOF
}

graphql_response_has_no_errors() {
  jq -e 'type == "object" and ((.errors // []) | length == 0)' \
    "$graphql_response_file" >/dev/null 2>&1
}

graphql_request() {
  local payload=$1
  mkdir -p "$(dirname "$graphql_response_file")"
  curl --connect-timeout 1 --max-time 10 --fail-with-body --silent --show-error \
    --header 'content-type: application/json' \
    --header "x-hasura-admin-secret: $HASURA_ADMIN_SECRET" \
    --data "$payload" \
    --output "$graphql_response_file" \
    "http://127.0.0.1:${HASURA_HOST_PORT}/v1/graphql" || return 1
  graphql_response_has_no_errors || return 1
  cat "$graphql_response_file"
}

graphql_todo_payload() {
  local title=$1
  jq -cn --arg title "$title" '{
    query: "query TodoByTitle($title: String!) { todos(where: {title: {_eq: $title}}) { id title completed } }",
    variables: {title: $title}
  }'
}

graphql_todo_visible() {
  local title=$1 payload response
  payload=$(graphql_todo_payload "$title")
  response=$(graphql_request "$payload") || return 1
  jq -e --arg title "$title" \
    '.data.todos | length >= 1 and all(.[]; .title == $title)' \
    <<<"$response" >/dev/null
}

graphql_todo_count() {
  local title=$1 payload response
  payload=$(graphql_todo_payload "$title")
  response=$(graphql_request "$payload") || return 1
  jq -r '.data.todos | length' <<<"$response"
}

graphql_insert_todo() {
  local title=$1 payload response
  payload=$(jq -cn --arg title "$title" '{
    query: "mutation InsertTodo($title: String!) { insert_todos_one(object: {title: $title}) { id title completed } }",
    variables: {title: $title}
  }')
  response=$(graphql_request "$payload") || return 1
  jq -e --arg title "$title" \
    '.data.insert_todos_one.title == $title and .data.insert_todos_one.completed == false' \
    <<<"$response" >/dev/null
}

unique_todo_title() {
  local marker=${1:-verification}
  printf 'verify-%s-%s-%s-%s\n' \
    "$marker" "$(date -u +%Y%m%dT%H%M%SZ)" "$$" "$RANDOM"
}

todo_on_service() {
  local service=$1 title=$2 count
  count=$(printf "SELECT count(*) FROM public.todos WHERE title = :'todo_title';\n" \
    | compose exec -T --env "PGPASSWORD=$POSTGRES_SUPERUSER_PASSWORD" \
      "$service" psql -XAt -v ON_ERROR_STOP=1 \
      --set=todo_title="$title" -U postgres -d app 2>/dev/null || true)
  [[ "$count" == 1 ]]
}

todo_on_all_members() {
  local title=$1 service
  for service in postgres1 postgres2 postgres3; do
    todo_on_service "$service" "$title" || return 1
  done
}

healthy_replica() {
  local excluded=${1:-} service
  for service in postgres1 postgres2 postgres3; do
    if [[ "$service" != "$excluded" ]] && patroni_endpoint_ready "$service" replica; then
      printf '%s\n' "$service"
      return 0
    fi
  done
  return 1
}

controlled_switchover() {
  local current_primary=$1 candidate=$2
  compose exec -T "$current_primary" \
    patronictl switchover --candidate "$candidate" --force >/dev/null
}

abrupt_primary_kill() {
  compose kill "$1" >/dev/null
}

former_member_streaming() {
  local service=$1 recovery receiver
  patroni_endpoint_ready "$service" replica || return 1
  recovery=$(compose exec -T --env "PGPASSWORD=$POSTGRES_SUPERUSER_PASSWORD" \
    "$service" psql -XAt -U postgres -d postgres \
    -c 'SELECT pg_is_in_recovery();' 2>/dev/null || true)
  receiver=$(compose exec -T --env "PGPASSWORD=$POSTGRES_SUPERUSER_PASSWORD" \
    "$service" psql -XAt -U postgres -d postgres \
    -c "SELECT count(*) FROM pg_stat_wal_receiver WHERE status = 'streaming';" \
    2>/dev/null || true)
  [[ "$recovery" == t && "$receiver" == 1 ]]
}

diagnostics() {
  local service port
  printf '\n=== Compose state ===\n' >&2
  compose ps --all >&2 || true

  printf '\n=== Initializer state ===\n' >&2
  compose ps --all database-init hasura-init >&2 || true

  printf '\n=== Recent logs ===\n' >&2
  compose logs --tail=80 >&2 || true

  printf '\n=== Patroni APIs ===\n' >&2
  for service in postgres1 postgres2 postgres3; do
    port=$(patroni_port "$service")
    printf '%s: ' "$service" >&2
    curl --connect-timeout 1 --max-time 3 --silent \
      "http://127.0.0.1:${port}/patroni" >&2 || true
    printf '\n' >&2
  done

  printf '\n=== etcd health ===\n' >&2
  compose exec -T etcd1 etcdctl \
    --endpoints=http://etcd1:2379,http://etcd2:2379,http://etcd3:2379 \
    endpoint health --cluster >&2 || true

  printf '\n=== HAProxy statistics ===\n' >&2
  haproxy_stats >&2 || true

  printf '\n=== Hasura strict health ===\n' >&2
  curl --connect-timeout 1 --max-time 5 --include --silent \
    --header "x-hasura-admin-secret: $HASURA_ADMIN_SECRET" \
    "http://127.0.0.1:${HASURA_HOST_PORT}/healthz?strict=true" >&2 || true
  printf '\n' >&2

  printf '\n=== Last GraphQL response ===\n' >&2
  if [[ -f "$graphql_response_file" ]]; then
    cat "$graphql_response_file" >&2
  else
    printf 'No GraphQL request has completed.\n' >&2
  fi
  printf '\n' >&2
}
