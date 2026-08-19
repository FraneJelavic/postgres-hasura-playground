#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root_dir=$(cd "${script_dir}/.." && pwd)
compose_file="${root_dir}/compose.yaml"
rendered_compose=''

cleanup() {
  [[ -z "${rendered_compose}" ]] || rm -f "${rendered_compose}"
}
trap cleanup EXIT

fail() {
  printf 'Static check failed: %s\n' "$*" >&2
  exit 1
}

require_commands() {
  local command_name
  for command_name in "$@"; do
    command -v "${command_name}" >/dev/null 2>&1 || \
      fail "required command '${command_name}' is not installed"
  done
}

# Search files that would be published, including untracked work. Additional
# arguments are repository-relative files that are explicitly allowed to match.
# The checker itself is always excluded because it contains the enforced patterns.
scan_repository() {
  local pattern=$1 excluded file status matched=1
  shift
  while IFS= read -r -d '' file; do
    [[ "${file}" == 'scripts/check.sh' ]] && continue
    for excluded in "$@"; do
      [[ "${file}" == "${excluded}" ]] && continue 2
    done
    if grep -nHIE "${pattern}" "${root_dir}/${file}"; then
      matched=0
    else
      status=$?
      (( status == 1 )) || return "${status}"
    fi
  done < <(git -C "${root_dir}" ls-files --cached --others --exclude-standard -z)
  return "${matched}"
}

require_commands bash find git grep shellcheck

assert_hasura_project_invariants() {
  local hasura_dir="$root_dir/hasura"
  local config_file="$hasura_dir/config.yaml"
  local metadata_version_file="$hasura_dir/metadata/version.yaml"
  local databases_file="$hasura_dir/metadata/databases/databases.yaml"
  local tables_file="$hasura_dir/metadata/databases/app/tables/tables.yaml"
  local todos_file="$hasura_dir/metadata/databases/app/tables/public_todos.yaml"
  local source_count from_env_count table_count table_file

  [[ -f "$config_file" && -f "$metadata_version_file" && -f "$databases_file" \
    && -f "$tables_file" && -f "$todos_file" ]] || \
    fail 'Hasura project is missing a required config, metadata, or table file'

  grep -qx 'version: 3' "$config_file" || \
    fail 'Hasura config.yaml must use project format version 3'
  if ! grep -qx 'metadata_directory: metadata' "$config_file" \
    || ! grep -qx 'migrations_directory: migrations' "$config_file" \
    || ! grep -qx 'seeds_directory: seeds' "$config_file"; then
    fail 'Hasura config.yaml must use tracked metadata, migration, and seed paths'
  fi
  grep -qx 'version: 3' "$metadata_version_file" || \
    fail 'Hasura metadata must use version 3'

  source_count=$(grep -Ec '^[[:space:]]*-[[:space:]]+name:[[:space:]]*[^[:space:]]+[[:space:]]*$' \
    "$databases_file" || true)
  from_env_count=$(grep -Ec '^[[:space:]]*from_env:[[:space:]]*[^[:space:]]+[[:space:]]*$' \
    "$databases_file" || true)
  [[ "$source_count" == 1 ]] || \
    fail 'Hasura metadata must declare exactly one database source'
  grep -Eq '^[[:space:]]*-[[:space:]]+name:[[:space:]]*app[[:space:]]*$' \
    "$databases_file" || fail 'Hasura metadata source must be named app'
  if [[ "$from_env_count" != 1 ]] \
    || ! grep -Eq '^[[:space:]]*from_env:[[:space:]]*PG_DATABASE_URL[[:space:]]*$' \
      "$databases_file"; then
    fail 'Hasura app source must resolve only from PG_DATABASE_URL'
  fi

  grep -Eq '^[[:space:]]*-[[:space:]]*"!include[[:space:]]+public_todos\.yaml"[[:space:]]*$' \
    "$tables_file" || fail 'Hasura app source must include public_todos metadata'
  [[ $(grep -Ec '^[[:space:]]*![[:space:]]*include|^[[:space:]]*-[[:space:]]*"!include' \
    "$tables_file" || true) == 1 ]] || \
    fail 'Hasura app source must track exactly one table metadata file'

  table_count=0
  while IFS= read -r -d '' table_file; do
    table_count=$((table_count + $(grep -Ec '^[[:space:]]*table:[[:space:]]*$' "$table_file" || true)))
  done < <(find "$hasura_dir/metadata" -type f -name '*.yaml' -print0)
  [[ "$table_count" == 1 ]] || \
    fail 'Hasura metadata must track exactly one table'
  if ! grep -Eq '^[[:space:]]*name:[[:space:]]*todos[[:space:]]*$' "$todos_file" \
    || ! grep -Eq '^[[:space:]]*schema:[[:space:]]*public[[:space:]]*$' "$todos_file"; then
    fail 'Hasura metadata must track only public.todos'
  fi
}

shell_scripts=()
while IFS= read -r -d '' script_path; do
  shell_scripts+=("${script_path}")
done < <(find "${root_dir}/scripts" -type f -name '*.sh' -print0)
if [[ -f "${root_dir}/images/postgres-patroni/entrypoint.sh" ]]; then
  shell_scripts+=("${root_dir}/images/postgres-patroni/entrypoint.sh")
fi

for script in "${shell_scripts[@]}"; do
  bash -n "${script}"
done
shellcheck "${shell_scripts[@]}"

repository_yaml=()
while IFS= read -r -d '' yaml_path; do
  repository_yaml+=("${root_dir}/${yaml_path}")
done < <(
  git -C "${root_dir}" ls-files --cached --others --exclude-standard -z \
    '*.yaml' '*.yml'
)
if (( ${#repository_yaml[@]} > 0 )); then
  require_commands yamllint
  yamllint \
    --config-data '{extends: relaxed, rules: {line-length: disable}}' \
    "${repository_yaml[@]}" || \
    fail 'repository configuration contains invalid YAML'
fi

if [[ -d "${root_dir}/hasura" ]]; then
  assert_hasura_project_invariants
fi

if scan_repository \
  'BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{36,}|github_pat_[A-Za-z0-9_]{50,}'; then
  fail 'potential secret material found'
fi

if scan_repository \
  'docker\.ib-ci\.com|git\.ib-ci\.com|confluence\.infobip\.com|jira\.infobip\.com|serena\.infobip\.com|infobip'; then
  fail 'a prohibited private marker was found'
fi

if scan_repository \
  'postgres-debezium-playground' \
  'PROVENANCE.md' 'THIRD_PARTY_NOTICES.md'; then
  fail 'postgres-debezium-playground attribution is allowed only in provenance and third-party notices'
fi

if scan_repository \
  '(^|[^[:alnum:]_])(kafka|debezium)([^[:alnum:]_]|$)' \
  'PROVENANCE.md' 'THIRD_PARTY_NOTICES.md'; then
  fail 'a prohibited Kafka or Debezium remnant was found'
fi

if [[ -f "${compose_file}" ]]; then
  require_commands docker jq
  docker compose version >/dev/null 2>&1 || fail 'Docker Compose v2 is not available'

  (
    cd "${root_dir}"
    docker compose config --quiet
  )

  rendered_compose=$(mktemp "${TMPDIR:-/tmp}/postgres-hasura-compose.XXXXXX")
  (
    cd "${root_dir}"
    docker compose config --format json
  ) >"${rendered_compose}"

  jq -e '
    [
      .services[]?.ports[]?
      | select(.host_ip != "127.0.0.1")
    ]
    | length == 0
  ' "${rendered_compose}" >/dev/null || \
    fail 'every published port must bind explicitly to 127.0.0.1'

  jq -e '
    [
      .services
      | to_entries[]
      | select(.key | test("^etcd[0-9]+$"))
      | .value.ports[]?
      | select(.target == 2379 or .target == 2380)
    ]
    | length == 0
  ' "${rendered_compose}" >/dev/null || \
    fail 'etcd voters must not publish client or peer ports 2379/2380'

  jq -e '
    [
      .services
      | to_entries[]
      | select(.key | test("^postgres[0-9]+$"))
      | .value.ports[]?
      | select(.target == 5432)
    ]
    | length == 0
  ' "${rendered_compose}" >/dev/null || \
    fail 'PostgreSQL members must not publish their database port directly'

  jq -e '
    [
      .services
      | to_entries[]
      | select(
          (.key | test("(^|[-_])(kafka|connect|debezium)([-_]|$)"; "i"))
          or ((.value.image // "") | test("kafka|debezium|connect"; "i"))
        )
    ]
    | length == 0
  ' "${rendered_compose}" >/dev/null || \
    fail 'Compose must not define Kafka, Connect, or Debezium services'

  jq -e '
    [
      .services[]?.environment // {}
      | to_entries[]
      | select(.key | test("(PASSWORD|SECRET)$"))
      | select(.value != "test")
    ]
    | length == 0
  ' "${rendered_compose}" >/dev/null || \
    fail 'all development password and secret environment values must be fixed to test'

  jq -e '
    [
      .services[]?.environment // {}
      | to_entries[]
      | select((.value | type) == "string")
      | select(.value | test("^postgres(ql)?://"))
      | select((.value | test("^[^:]+://[^:/]+:test@")) | not)
    ]
    | length == 0
  ' "${rendered_compose}" >/dev/null || \
    fail 'PostgreSQL connection URLs must use the fixed development password test'

  hasura_service_count=$(jq '
    [
      .services
      | to_entries[]
      | select(
          (.key == "hasura" or .key == "hasura-init")
          or ((.value.image // "") | startswith("hasura/graphql-engine:"))
        )
    ]
    | length
  ' "${rendered_compose}")

  if (( hasura_service_count > 0 )); then
    jq -e '
      (.services.hasura.image == "hasura/graphql-engine:v2.42.0")
      and (.services["hasura-init"].image == "hasura/graphql-engine:v2.42.0.cli-migrations-v3")
      and (.services.hasura.environment.HASURA_GRAPHQL_ADMIN_SECRET == "test")
      and (.services.hasura.environment.HASURA_GRAPHQL_METADATA_DATABASE_URL == "postgres://hasura_metadata:test@haproxy:5432/hasura_metadata")
      and (.services.hasura.environment.PG_DATABASE_URL == "postgres://hasura_app:test@haproxy:5432/app")
      and ((.services.hasura.environment | has("HASURA_GRAPHQL_DATABASE_URL")) | not)
      and (.services["hasura-init"].environment.HASURA_GRAPHQL_ADMIN_SECRET == "test")
    ' "${rendered_compose}" >/dev/null || \
      fail 'Hasura services must use the pinned 2.42.0 images, HAProxy URLs, and fixed test credential'
  fi
fi

printf 'Static checks passed.\n'
