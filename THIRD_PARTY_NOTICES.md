# Third-Party Notices

This playground downloads, builds with, or runs unmodified upstream software. Each project remains governed by its own license.

| Dependency | Version | Registry/source | License |
|---|---:|---|---|
| Adapted playground patterns | Public repository, accessed 2026-08-18 | https://github.com/FraneJelavic/postgres-debezium-playground | Apache-2.0 |
| PostgreSQL image | 16.14-bookworm | docker.io/library/postgres | PostgreSQL License |
| Patroni | 4.1.5 | pypi.org/project/patroni | MIT |
| etcd | 3.5.33 | quay.io/coreos/etcd | Apache-2.0 |
| HAProxy | 3.2.22-alpine | docker.io/library/haproxy | GPL-2.0-or-later with linking exception |
| Hasura GraphQL Engine | 2.42.0 | docker.io/hasura/graphql-engine | Apache-2.0 |
| Hasura CLI migrations image | 2.42.0.cli-migrations-v3 | docker.io/hasura/graphql-engine | Apache-2.0 |
| Structurizr CLI (rendering only) | 2025.11.09 | docker.io/structurizr/cli | Apache-2.0 |
| PlantUML (rendering only) | 1.2026.6 | docker.io/plantuml/plantuml | GPL-3.0-or-later |
| Contributor Covenant | 2.1 | https://www.contributor-covenant.org/version/2/1/code_of_conduct.html | CC BY 4.0 |

The complete Patroni Python dependency lock, including package hashes, is in `images/postgres-patroni/requirements.txt`. Container image versions and architecture availability are documented in `docs/compatibility.md`.

The Hasura runtime and CLI initializer are separate image variants from the same upstream project and are listed separately because both are executed by the Compose environment.

The adapted sibling repository's copyright notice is:

> Copyright 2026 The postgres-debezium-playground authors

Only generic topology and workflow patterns were adapted. No upstream repository
history or generated artifact is distributed as part of this repository.
