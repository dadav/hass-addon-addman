<!-- Thanks for contributing to AddMan! -->

## What does this change?

<!-- A short description of the change and the problem it solves. -->

## Type of change

- [ ] Bug fix (PATCH)
- [ ] New feature (MINOR)
- [ ] Breaking change to the config format (MAJOR)
- [ ] Documentation / CI only

## Checklist

- [ ] I updated `addman/DOCS.md` if user-facing behaviour changed
- [ ] I added a `addman/CHANGELOG.md` entry under `[Unreleased]`
- [ ] I bumped `version` in `addman/config.yaml` (for code changes)
- [ ] The smoke test passes (`docker build -t addman-test ./addman && bash tests/smoke_test.sh`)
