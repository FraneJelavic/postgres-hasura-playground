# Security Model

This playground assumes one trusted developer on an isolated local machine. It is
designed for inspection and failure exercises, not for untrusted or production
traffic.

## Network boundary

Every published port binds explicitly to `127.0.0.1`. The Hasura API and console,
HAProxy SQL and statistics endpoints, and Patroni inspection APIs are therefore
reachable only through the host's loopback interface by default.

etcd client and peer ports are not published. Individual PostgreSQL member database
ports are also not published; host clients use HAProxy's sole writable route.
Containers on the Compose network can still reach one another, and any process or
user with Docker access can inspect or control the entire environment.

Loopback binding is a guard against accidental LAN exposure, not a hardened
sandbox.

## Identity and transport

The repository deliberately tracks fixed development values:

- PostgreSQL passwords: `test`
- Hasura admin secret: `test`

The console and development mode are enabled. HTTP and PostgreSQL traffic is not
protected with TLS. There is no external identity provider, authorization model
beyond the Hasura admin secret, secret manager, certificate lifecycle, or network
policy. Never substitute real data or expose these ports through forwarding,
proxies, or a public container host.

## Data and host trust

Application data, metadata, cluster state, and write-ahead logs persist in
project-scoped Docker volumes. They are readable to an operator with Docker or host
filesystem privileges and are not encrypted by this project. `make down` preserves
them; `make reset` deletes them after confirmation.

Container images and Python packages come from the public sources and pinned
versions recorded in [Provenance](../PROVENANCE.md),
[Third-Party Notices](../THIRD_PARTY_NOTICES.md), and the
[compatibility matrix](compatibility.md). Explicit tags can still be repointed by
publishers, and Debian security updates are consumed when the custom image is
rebuilt.

## Operational assumptions

- The Docker daemon or Colima VM and host user are trusted.
- The checkout and tracked configuration have not been tampered with.
- The machine is not shared with untrusted local users.
- Only disposable development data is stored.
- A failed or compromised container can affect the shared Compose network and
  volumes.

The environment has no security monitoring, audit export, vulnerability response
automation, backup encryption, or production patch SLA.

Report vulnerabilities privately according to [SECURITY.md](../SECURITY.md). For
the broader non-production boundary, see [Limitations](limitations.md).
