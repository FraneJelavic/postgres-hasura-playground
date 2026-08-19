# Hasura Project

The repository tracks the complete Hasura schema, metadata, and seed under
`hasura/`. Startup deploys this project non-interactively after the writable
PostgreSQL route exists.

## Database separation

Hasura state and application data use separate databases and owners:

| Purpose | Database | Login role | Connection source |
|---|---|---|---|
| Hasura metadata catalog | `hasura_metadata` | `hasura_metadata` | `HASURA_GRAPHQL_METADATA_DATABASE_URL` |
| Tracked application source | `app` | `hasura_app` | `PG_DATABASE_URL` in metadata |

Both URLs use `haproxy:5432` inside the Compose network, so metadata and application
writes follow the same current PostgreSQL primary. The database initializer creates
or updates both login roles, creates missing databases, and restores the expected
owners. The SQL is safe to run again against preserved volumes.

Hasura's generic `HASURA_GRAPHQL_DATABASE_URL` is intentionally not used. Keeping
metadata storage separate from the named `app` source makes ownership and tracked
configuration explicit.

## Tracked layout

```text
hasura/
├── config.yaml
├── migrations/
│   └── app/
│       └── 202608170001_create_todos/
│           ├── up.sql
│           └── down.sql
├── metadata/
│   ├── version.yaml
│   └── databases/
│       ├── databases.yaml
│       └── app/tables/
│           ├── tables.yaml
│           └── public_todos.yaml
└── seeds/
    └── app/
        └── 202608170001_todos.sql
```

- `config.yaml` selects Hasura project format version 3 and the tracked
  directories.
- `migrations/app` owns application DDL. The initial migration creates
  `public.todos` with `id`, `title`, and `completed` columns.
- `metadata/databases` declares the `app` source from `PG_DATABASE_URL` and tracks
  `public.todos`.
- `seeds/app` inserts `Seeded playground todo` only when that title is absent.

## Deployment order

Two one-shot Compose services keep bootstrap responsibilities separate:

1. `database-init` waits for writable SQL through HAProxy, then creates the roles
   and databases.
2. Hasura starts and reaches ordinary health without requiring project metadata to
   be present yet.
3. `hasura-init` runs the pinned Hasura CLI image with `deploy --with-seeds` against
   the Hasura API.
4. Startup requires `hasura-init` to exit with code zero and strict health to return
   `OK`.

Ordinary `/healthz` is therefore only a bootstrap milestone. Operator readiness is
`/healthz?strict=true`, which detects inconsistent metadata or an unavailable
source.

## Making project changes

Represent schema changes as a new timestamped migration under `migrations/app`,
update tracked metadata for exposed objects, and add a seed only when its behavior
is idempotent. Do not edit a migration that may already have been applied to a
preserved volume unless the change is explicitly a history correction.

Validate a change with disposable data:

```sh
make check
make reset
make up
make status
make verify
```

`make reset` deletes the project volumes and requires confirmation. The full
verification also proves that re-running both initializers against preserved
volumes leaves exactly one seeded row.

The local console is useful for exploration, but exported schema and metadata
changes must be represented in the tracked project before review.
