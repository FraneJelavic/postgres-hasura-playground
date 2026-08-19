# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
when publishing releases.

## [Unreleased]

### Added

- Three-member PostgreSQL 16 cluster managed by Patroni and a three-voter etcd
  distributed configuration store.
- HAProxy routing to the sole writable primary.
- Hasura GraphQL Engine with tracked migrations, metadata, and idempotent seed.
- Local startup, status, controlled switchover, abrupt-failover, reset, and
  acceptance-verification workflows.
- Reproducible C4 architecture diagrams, compatibility policy, provenance,
  third-party notices, and Apache-2.0 project governance.

[Unreleased]: https://github.com/FraneJelavic/postgres-hasura-playground/commits/main
