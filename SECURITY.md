# Security Policy

## Supported versions

Security fixes are made on the default branch. Tagged releases, if any, are
supported only when explicitly identified in release notes. This playground is not
a production service and does not receive a production support or patching SLA.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use the hosting
platform's private vulnerability-reporting feature for this repository. Include:

- the affected revision and component;
- reproduction steps or a minimal proof of concept;
- expected and observed impact;
- whether the issue requires a non-default configuration; and
- any suggested mitigation.

Maintainers will acknowledge reports on a best-effort basis, validate the issue,
and coordinate disclosure when a fix is available. Do not include credentials,
personal data, or access to third-party systems in a report.

## Security model

The tracked passwords and Hasura admin secret are fixed development values. The
Hasura console is enabled, traffic is unencrypted, and local users can inspect
container configuration and volumes. Loopback-only port bindings reduce accidental
network exposure but do not make this environment suitable for untrusted users.

The project provides no secret management, authentication integration, TLS,
network policy, audit pipeline, backup encryption, or production hardening. Use it
only with disposable data on an isolated development machine.

For general defects and operational questions that do not have security impact,
follow [SUPPORT.md](SUPPORT.md).
