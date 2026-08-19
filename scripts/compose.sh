#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib.sh
source "$script_dir/lib.sh"

require_commands docker

exec docker compose \
  --project-directory "$root_dir" \
  --project-name "$COMPOSE_PROJECT_NAME" \
  "$@"
