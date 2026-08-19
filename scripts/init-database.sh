#!/usr/bin/env bash
set -Eeuo pipefail

readonly initialization_sql=/init/sql/001-databases.sql
readonly maximum_attempts=60

for ((attempt = 1; attempt <= maximum_attempts; attempt++)); do
  writable=$(psql -X -Atqc 'SELECT NOT pg_is_in_recovery();' 2>/dev/null || true)
  if [[ "${writable}" == t ]]; then
    psql -X -v ON_ERROR_STOP=1 --file "${initialization_sql}"
    exit 0
  fi

  printf 'Waiting for writable PostgreSQL through HAProxy (%d/%d).\n' \
    "${attempt}" "${maximum_attempts}"
  sleep 2
done

printf 'Timed out waiting for writable PostgreSQL through HAProxy.\n' >&2
exit 1
