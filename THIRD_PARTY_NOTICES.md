# Third-Party Notices

This playground downloads, builds with, or runs unmodified upstream software. Each project remains governed by its own license.

| Dependency | Version | Registry/source | License |
|---|---:|---|---|
| PostgreSQL image | 16.14-bookworm | docker.io/library/postgres | PostgreSQL License |
| Patroni | 4.1.5 | pypi.org/project/patroni | MIT |
| etcd | 3.5.33 | quay.io/coreos/etcd | Apache-2.0 |
| HAProxy | 3.2.22-alpine | docker.io/library/haproxy | GPL-2.0-or-later with linking exception |
| Hasura GraphQL Engine | 2.42.0 | docker.io/hasura/graphql-engine | Apache-2.0 |
| Hasura CLI migrations image | 2.42.0.cli-migrations-v3 | docker.io/hasura/graphql-engine | Apache-2.0 |
| Structurizr CLI (rendering only) | 2025.11.09 | docker.io/structurizr/cli | Apache-2.0 |
| PlantUML (rendering only) | 1.2026.6 | docker.io/plantuml/plantuml | GPL-3.0-or-later |

The complete Patroni Python dependency lock, including package hashes, is in `images/postgres-patroni/requirements.txt`. Container image versions and architecture availability are documented in `docs/compatibility.md`.

The Hasura runtime and CLI initializer are separate image variants from the same upstream project and are listed separately because both are executed by the Compose environment.
