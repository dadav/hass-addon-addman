# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2026-01-22

### Breaking Changes

- Dropped support for 32-bit architectures (armhf, armv7, i386)
- Now only supports 64-bit architectures: aarch64 and amd64
- Updated to Home Assistant base image v19.0.0
- Updated to builder action 2025.11.0

### Fixed

- Fixed `bashio::jq.exists` and `bashio::jq` function calls to use direct `jq` commands for compatibility with base image v19.0.0

### Changed

- Removed Alpine package version pins for better cross-architecture compatibility

## [1.5.7] - 2023-10-26

### Fixed

- Bump deps to latest version

## [1.5.6] - 2023-09-03

### Fixed

- Bump deps to latest version

## [1.5.5] - 2023-03-29

### Fixed

- Bump deps to latest version

## [1.5.4] - 2023-01-25

### Fixed

- Bump deps to latest version

## [1.5.3] - 2022-12-11

### Fixed

- Need a newline between the files

## [1.5.2] - 2022-12-11

### Fixed

- Need a newline between the files

## [1.5.1] - 2022-12-11

### Fixed

- Actually increase the version

## [1.5.0] - 2022-12-11

### Added

- Secrets support

### Fixed

- Quoting bug with some variables

## [1.4.2] - 2022-11-27

### Fixed

- Fixed splitting issue
-

## [1.4.1] - 2022-11-27

### Fixed

- Bug when slug/key started with number

## [1.4.0] - 2022-11-27

### Added

- Apparmor profile

### Fixed

- Assume default for auto_restart is true

## [1.3.4] - 2022-11-26

### Fixed

- Nothing changed, just trying to get codenotary to work

## [1.3.3] - 2022-11-26

### Fixed

- Nothing changed, just trying to get codenotary to work

## [1.3.2] - 2022-11-26

### Fixed

- Bug which caused some values to be not quoted correctly

## [1.3.1] - 2022-11-26

### Fixed

- Codenotary mail for base images

## [1.3.0] - 2022-11-26

### Added

- Added check_updates_x_iterations option
- Added codenotary mail

## [1.2.0] - 2022-11-25

### Added

- Add "auto_restart" option

### Changed

- Option "start" renamed to "auto_start"

## [1.1.0] - 2022-11-24

### Fixed

- Removed stage option because linter said so.
- Adjusted docs to latest features

### Added

- Added some example configurations.
- Added ingress_panel addon option
- Added repository config option
- Added check if options need to be quoted

## [1.0.3] - 2022-11-23

### Fixed

- Adjusted the defaults. The name of the own add-on must be self.

## [1.0.2] - 2022-11-23

### Fixed

- Fixed a typo which prevented the defaults config to be copied

## [1.0.0] - 2022-11-23

### Added

- Initial release
