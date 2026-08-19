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
