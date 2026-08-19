# Provenance

This repository is an independently maintained, clean-history implementation
assembled from public upstream software and documentation.

The PostgreSQL high-availability topology was adapted from the public
[`postgres-debezium-playground`](https://github.com/FraneJelavic/postgres-debezium-playground)
sibling repository under Apache-2.0. Only generic topology, configuration, and
workflow patterns were carried forward. Repository history, generated assets,
credentials, application schemas, and release artifacts were not imported. All
Hasura integration, database initialization, operational workflows, documentation,
and C4 source in this repository are maintained independently.

## Public sources

| Component | Public source | License | Selection and integrity policy |
|---|---|---|---|
| Prior playground patterns | https://github.com/FraneJelavic/postgres-debezium-playground | Apache-2.0 | Public topology and workflow patterns were reviewed and adapted into this clean history. |
| PostgreSQL | https://www.postgresql.org/docs/16/ and https://hub.docker.com/_/postgres | PostgreSQL License | PostgreSQL 16 Bookworm patch release selected by explicit image tag. |
| Patroni | https://patroni.readthedocs.io/ and https://github.com/patroni/patroni | MIT | Exact Python package version with transitive dependencies pinned and hashed. |
| etcd | https://etcd.io/docs/ and https://github.com/etcd-io/etcd | Apache-2.0 | 3.5 patch release selected by explicit image tag. |
| HAProxy | https://docs.haproxy.org/ and https://github.com/haproxy/haproxy | GPL-2.0-or-later with linking exception | Stable patch release selected by explicit image tag. |
| Hasura GraphQL Engine and CLI | https://hasura.io/docs/2.0/ and https://github.com/hasura/graphql-engine | Apache-2.0 | Runtime and CLI initializer use matching explicit 2.42.0 image tags. |
| Docker Compose | https://docs.docker.com/compose/ and https://github.com/docker/compose | Apache-2.0 | Compose v2 plugin with the minimum supported version documented in the compatibility matrix. |
| Structurizr CLI | https://docs.structurizr.com/cli and https://github.com/structurizr/cli | Apache-2.0 | Used only to export repository-authored diagram source; rendering image is pinned. |
| PlantUML | https://plantuml.com/ and https://github.com/plantuml/plantuml | GPL-3.0-or-later | Used only to render generated diagram definitions; rendering image is pinned. |

## Repository-owned material

Compose configuration, Patroni and HAProxy configuration, shell workflows, SQL
initialization, the Hasura project, documentation, and Structurizr DSL are
maintained in this repository under Apache-2.0.

Generated C4 PNG files must be reproducible from the tracked Structurizr source
with `make diagrams`. `make check-diagrams` verifies that committed images match
their source.

## Integrity policy

- Container images use explicit version tags.
- Patroni and all transitive Python dependencies are pinned with hashes in `images/postgres-patroni/requirements.txt`.
- Runtime dependency versions are recorded in `docs/compatibility.md`.
- Rendering-only dependency versions are recorded in `THIRD_PARTY_NOTICES.md`.
- Dependency updates must pass `make check` and `make verify`.
