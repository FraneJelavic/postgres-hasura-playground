# Compatibility Matrix

Validated selections as of 2026-08-18:

| Component | Version | amd64 | arm64 |
|---|---|:---:|:---:|
| PostgreSQL base/client | `postgres:16.14-bookworm` | yes | yes |
| Patroni | `4.1.5` | yes | yes |
| etcd | `quay.io/coreos/etcd:v3.5.33` | yes | yes |
| HAProxy | `haproxy:3.2.22-alpine` | yes | yes |
| Hasura GraphQL Engine | `hasura/graphql-engine:v2.42.0` | yes | yes |
| Hasura CLI initializer | `hasura/graphql-engine:v2.42.0.cli-migrations-v3` | yes | yes |

Container manifest inspection confirmed `linux/amd64` and `linux/arm64` availability for the declared upstream images. Patroni is installed from its exact Python dependency lock into the custom PostgreSQL image. The complete runtime regression is certified on Ubuntu/amd64; macOS with Colima is the supported local workflow.

Runtime and build inputs use explicit version tags so dependency automation can maintain them. Upstream publishers can repoint tags; dependency updates must be reviewed together with static checks and runtime verification.

This is a single-host development and learning environment: every redundant container still shares one Docker Engine or Colima host. It is not a production PostgreSQL or Hasura deployment.

## Host prerequisites

- Docker Engine 27 or newer.
- Docker Compose plugin 2.30 or newer (`docker compose`, not legacy `docker-compose`).
- Colima 0.8 or newer when running on macOS.
- `bash`, `curl`, `jq`, and `make` on the host.
- Starting Colima allocation: 4 CPUs, 8 GiB RAM, and 30 GiB disk.

Static repository validation additionally requires ShellCheck and `yamllint`. Diagram generation uses the pinned rendering containers recorded in `THIRD_PARTY_NOTICES.md`.
