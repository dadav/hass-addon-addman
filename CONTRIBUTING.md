# Contributing to AddMan

Thanks for your interest in improving AddMan! Issues and pull requests are
welcome.

## Project layout

- `addman/rootfs/usr/bin/addman.sh` — the add-on logic (Bash, runs the reconcile
  loop against the Home Assistant Supervisor API).
- `addman/config.yaml` — the add-on manifest (name, version, arch, options).
- `addman/DOCS.md` — user-facing documentation (the add-on's Documentation tab).
- `tests/` — a smoke test that runs the real script against a mock Supervisor.

## Making a change

1. Edit `addman/rootfs/usr/bin/addman.sh` (or the relevant file).
2. If you change behaviour, update `addman/DOCS.md` and add a `addman/CHANGELOG.md`
   entry under `[Unreleased]`.
3. Bump `version` in `addman/config.yaml` following
   [Semantic Versioning](https://semver.org/): MAJOR for breaking config changes,
   MINOR for new features, PATCH for fixes.

## Running the tests locally

The smoke test builds the add-on image and runs the real `addman.sh` against a
stdlib-only mock Supervisor, asserting the reconcile calls (add repo, install,
validate + set options, start, uninstall):

```bash
docker build -t addman-test ./addman
bash tests/smoke_test.sh
```

You need Docker and Python 3. The mock listens on `127.0.0.1:8099`
(override with `MOCK_PORT`).

## Linting

YAML and the add-on structure are linted in CI. To check locally:

```bash
yamllint -c .yamllint .
```

## Pull requests

- Keep changes focused and follow the existing style in `addman.sh`.
- Make sure the smoke test passes.
- Describe what changed and why in the PR.
