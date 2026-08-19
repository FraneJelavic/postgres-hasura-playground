#!/usr/bin/env bash
set -Eeuo pipefail

required=(
  PATRONI_NAME
  PATRONI_POSTGRESQL_CONNECT_ADDRESS
  PATRONI_RESTAPI_CONNECT_ADDRESS
  PATRONI_SUPERUSER_PASSWORD
  PATRONI_REPLICATION_PASSWORD
  PATRONI_REWIND_PASSWORD
)

for variable_name in "${required[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    printf 'Required environment variable %s is not set.\n' "$variable_name" >&2
    exit 1
  fi
done

umask 077
exec "$@"
