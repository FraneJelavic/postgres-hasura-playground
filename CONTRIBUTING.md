# Contributing

Contributions that keep the playground reproducible, local-only, and educational
are welcome. By submitting a contribution, you agree that it is licensed under the
Apache License 2.0 and that you have the right to provide it.

## Before opening a change

1. Search existing issues and pull requests.
2. For a substantial behavior or topology change, open an issue describing the
   use case, operational impact, compatibility impact, and alternatives.
3. Keep the scope focused. Avoid mixing dependency updates, formatting, and
   behavioral changes unless they must land together.

## Development environment

Use the prerequisites and Colima baseline from the [README](README.md). Fork and
clone the repository, then create a topic branch:

```sh
git switch -c feature/short-description
make check
make up
make status
```

Do not commit local state, generated logs, credentials, or container volumes.

## Change requirements

- Add or update executable verification before changing runtime behavior.
- Keep shell scripts compatible with the repository's Bash baseline and clean
  under ShellCheck.
- Keep all published ports explicitly bound to `127.0.0.1`.
- Use explicit upstream versions. Update `docs/compatibility.md`, `PROVENANCE.md`,
  and `THIRD_PARTY_NOTICES.md` when dependencies change.
- Preserve idempotent database initialization, Hasura migrations, metadata, and
  seeds.
- Document user-visible commands, environment variables, failure behavior, and
  limitations.
- Update the C4 source when architecture changes, run `make diagrams`, and commit
  the resulting images.
- Never add real secrets or private infrastructure references.

## Validation

Run the shortest relevant checks during development and the complete suite before
requesting review:

```sh
make check
make check-diagrams
make verify
```

`make verify` changes database leadership, kills a primary container, creates test
rows, and restarts the Compose environment while preserving named volumes. Run it
only against disposable playground state. Include the commands and results in the
pull request description.

## Pull requests

A reviewable pull request:

- explains the problem and the chosen behavior;
- links the issue when one exists;
- calls out destructive steps, compatibility changes, and known limitations;
- includes documentation and generated C4 images when relevant;
- has focused commits with clear messages; and
- passes required automated checks.

Maintainers may request a smaller scope or additional verification. Review and
merge are best-effort and do not imply a release schedule.
