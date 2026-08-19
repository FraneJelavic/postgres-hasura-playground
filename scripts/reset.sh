#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

require_commands docker

project_label="com.docker.compose.project=$COMPOSE_PROJECT_NAME"
project_volumes=()
while IFS= read -r volume_name; do
  [[ -z "$volume_name" ]] || project_volumes+=("$volume_name")
done < <(docker volume ls --filter "label=$project_label" --format '{{.Name}}')

printf 'Compose project: %s\n' "$COMPOSE_PROJECT_NAME"
if ((${#project_volumes[@]} == 0)); then
  printf 'Project volumes: none\n'
else
  printf 'Project volumes to remove:\n'
  printf '  %s\n' "${project_volumes[@]}"
fi

if [[ "${CONFIRM_RESET:-}" != YES ]]; then
  if [[ ! -t 0 ]]; then
    printf 'Refusing non-interactive reset. Set CONFIRM_RESET=YES to confirm.\n' >&2
    exit 1
  fi

  printf 'Type the exact project name (%s) to continue: ' "$COMPOSE_PROJECT_NAME"
  IFS= read -r confirmation
  if [[ "$confirmation" != "$COMPOSE_PROJECT_NAME" ]]; then
    printf 'Reset cancelled: confirmation did not match the project name.\n' >&2
    exit 1
  fi
fi

compose down --volumes --remove-orphans

if ((${#project_volumes[@]} > 0)); then
  remaining_volumes=()
  while IFS= read -r volume_name; do
    [[ -z "$volume_name" ]] || remaining_volumes+=("$volume_name")
  done < <(docker volume ls --filter "label=$project_label" --format '{{.Name}}')

  if ((${#remaining_volumes[@]} > 0)); then
    docker volume rm "${remaining_volumes[@]}"
  fi
fi

printf 'Removed resources and volumes for Compose project %s.\n' \
  "$COMPOSE_PROJECT_NAME"
