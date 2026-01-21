# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AddMan is a Home Assistant add-on written in Bash that enables declarative management of Home Assistant add-ons and repositories via YAML configuration files stored in git. It operates as a long-running reconciliation loop that continuously ensures the actual state matches the desired state defined in configuration files.

**Key characteristics:**
- Single bash script (`addman/rootfs/usr/bin/addman.sh`) contains all core logic
- Uses Home Assistant Supervisor API for all add-on operations
- Requires `hassio_role: manager` permission
- Runs as a daemon with configurable check intervals (default: 600 seconds)
- Supports YAML anchors for secret management via separate `.secrets` files

## Architecture

### Core Components

**Main execution script:** `addman/rootfs/usr/bin/addman.sh` (~295 lines)
- Entry point: `#!/command/with-contenv bashio`
- Uses `bashio` library for logging and Home Assistant API interactions
- All functions prefixed with `addman::` namespace
- Main loop: Read config → Install repos → Install/configure add-ons → Sleep → Repeat

**Key functions:**
- `addman::yaml_to_json()`: Parse YAML with secret injection using `yq`
- `addman::addon.validate_options()`: Validate configuration via supervisor API before applying
- `addman::addons.fetch_repositories()`: Get installed repos with caching
- `addman::addon.ingress_panel()`: Configure ingress sidebar panel

**Configuration flow:**
1. Read `/config/addman.yaml` (or user-specified path)
2. Merge with `/config/addman.yaml.secrets` if present (YAML anchors)
3. Convert to JSON via `yq`
4. Validate against supervisor API schemas
5. Apply changes only if configuration differs from current state

### Directory Structure

```
addman/
├── rootfs/usr/bin/addman.sh      # Main script - all logic lives here
├── rootfs/etc/addman/defaults.yaml  # Default configuration template
├── config.yaml                    # Add-on manifest (schema, options, permissions)
├── build.yaml                     # Multi-arch Docker build config
├── Dockerfile                     # Container image definition
├── examples/                      # Configuration examples (basic, advanced, wireguard)
├── translations/                  # Localization files (en.yaml, de.yaml)
├── DOCS.md                        # User documentation
└── CHANGELOG.md                   # Release history (keepachangelog.com format)
```

## Common Development Commands

### Linting

```bash
# Lint all YAML files
yamllint .

# Lint markdown files
mdl --style .mdlrc .

# Lint using Home Assistant add-on linter (GitHub Actions workflow)
# See .github/workflows/lint.yaml
```

### Building

The add-on uses Home Assistant's builder for multi-architecture Docker images:

```bash
# Local build (single architecture)
docker build -t addman-local -f addman/Dockerfile addman/

# Production builds are handled by GitHub Actions
# See .github/workflows/builder.yaml
# Triggered on changes to: build.yaml, config.yaml, Dockerfile, rootfs/
```

**Supported architectures:** aarch64, amd64, armhf, armv7, i386

### Testing

There are no unit tests. Validation occurs through:
- YAML schema validation (`.yamllint` + Home Assistant supervisor)
- Configuration validation via supervisor API before applying changes
- CI/CD pipeline linting and build tests

To test manually:
1. Install add-on in Home Assistant
2. Configure `/config/addman.yaml` with test add-ons
3. Check logs via Home Assistant UI (set `log_level: debug` for verbosity)

### Development Workflow

1. Modify `addman/rootfs/usr/bin/addman.sh` for logic changes
2. Update `addman/config.yaml` if changing configuration schema or options
3. Update translations in `addman/translations/*.yaml` for UI changes
4. Test in Home Assistant environment (requires supervisor)
5. Update `addman/CHANGELOG.md` following keepachangelog.com conventions
6. Bump version in `addman/config.yaml` (Semantic Versioning: MAJOR.MINOR.PATCH)

## Configuration Files

### `addman/config.yaml` - Add-on Manifest

Defines:
- Add-on metadata (name, version, slug, description)
- Required Home Assistant permissions (`hassio_role: manager`)
- Host resource mappings (addons, configs, homeassistant_config)
- User-configurable options with schema validation
- Supported architectures
- Docker image registry path

**Critical fields:**
- `hassio_api: true` - Required for API access
- `hassio_role: manager` - Required for add-on management operations
- `map` - Grants filesystem access to add-on directories and configs

### `/config/addman.yaml` - Target State Configuration

User-defined file specifying desired state:

```yaml
repositories:
  - https://github.com/example/repo

addons:
  addon_slug:
    auto_start: true          # Start on boot
    auto_restart: true        # Restart when config changes
    auto_update: true         # Enable auto-updates
    boot: auto                # Boot behavior (auto/manual)
    watchdog: true            # Enable watchdog
    ingress_panel: false      # Show in sidebar
    options:                  # Add-on-specific configuration
      key: value              # Validated against add-on's schema
```

Secret management via YAML anchors:

```yaml
# /config/addman.yaml.secrets
my_secret: &secret_ref "secret_value"

# /config/addman.yaml
addons:
  addon_slug:
    options:
      password: *secret_ref
```

### `.yamllint` - YAML Validation Rules

Enforces:
- 2-space indentation
- Document start marker (`---`) required
- Max line length: 120 chars (warning)
- Unix line endings (LF)
- No trailing whitespaces

## CI/CD Pipeline

### Builder Workflow (`.github/workflows/builder.yaml`)

**Triggers:**
- Push to `main` branch
- Pull requests to `main`
- Only when monitored files change: `build.yaml`, `config.yaml`, `Dockerfile`, `rootfs/`

**Process:**
1. Detect changed add-ons
2. Build for all 5 architectures in parallel
3. Run with `--test` flag on PRs
4. Push to `ghcr.io/dadav/{arch}-addon-addman` on main branch
5. Sign with Codenotary (`CAS_API_KEY` secret required)

### Lint Workflow (`.github/workflows/lint.yaml`)

**Triggers:**
- Push/PR events
- Daily schedule

**Validation:**
- Home Assistant add-on structure
- YAML formatting
- Markdown formatting

### Dependency Management (`renovate.json`)

Renovate bot automatically:
- Updates Docker base images (`ghcr.io/hassio-addons/base`)
- Updates Alpine packages via repology datasource (`yq-go`, `coreutils`)
- Auto-merges patch and minor updates
- Groups related updates together

## Logging and Debugging

**Log levels:** `trace`, `debug`, `info`, `notice`, `warning`, `error`, `fatal`

Set in add-on configuration or `/config/addman.yaml`:
```yaml
options:
  log_level: debug  # For troubleshooting
```

**Common debugging steps:**
1. Enable `log_level: trace` to see all function calls
2. Enable `watch_config_changes: true` for hot-reload during testing
3. Check supervisor logs via Home Assistant UI
4. Verify configuration syntax with `yq` locally:
   ```bash
   yq eval /config/addman.yaml
   ```

## Important Implementation Notes

### State Reconciliation Pattern

AddMan implements a reconciliation loop (GitOps pattern):
- Reads desired state from YAML
- Compares with actual state via supervisor API
- Takes minimal actions to converge to desired state
- Only restarts add-ons if configuration actually changed (prevents unnecessary downtime)

### API Integration

All operations use Home Assistant Supervisor API via `bashio` library:
- `bashio::api.supervisor`: Make supervisor API calls
- Always validate options before applying: `addman::addon.validate_options()`
- Cache repository list to minimize API calls

### Configuration Validation

**Critical:** Always validate add-on options against supervisor schema before applying:
```bash
bashio::api.supervisor POST "/addons/${addon_slug}/options/validate" "${options_json}"
```

This prevents breaking add-ons with invalid configurations.

### Secret Handling

Secrets use standard YAML anchors/aliases:
- Define anchors in `${config_file}.secrets`
- Reference with aliases in main config
- Merged at runtime via `yq` with document merging
- Secrets file never committed to git (user responsibility)

### Multi-Architecture Considerations

When modifying shell scripts or dependencies:
- Test impact across all 5 architectures
- Bash features must work on Alpine Linux (busybox)
- Use POSIX-compatible commands where possible
- Dependencies installed via Alpine APK packages

### Versioning and Releases

**Semantic Versioning (MAJOR.MINOR.PATCH):**
- MAJOR: Breaking changes to configuration schema or behavior
- MINOR: New features, backwards-compatible enhancements
- PATCH: Bug fixes, dependency updates

**Release process:**
1. Update `addman/CHANGELOG.md` with changes
2. Bump version in `addman/config.yaml`
3. Commit and push to `main`
4. GitHub Actions builds and publishes images
5. Users see update in Home Assistant add-on store

## Common Patterns

### Adding New Configuration Options

1. Update schema in `addman/config.yaml`:
   ```yaml
   schema:
     new_option: str  # or int, bool, list(...)
   ```
2. Add default value in `options:` section
3. Parse in `addman.sh` main loop
4. Update `addman/DOCS.md` with option documentation
5. Update translations if adding UI elements

### Modifying Add-on Installation Logic

1. Locate relevant function in `addman.sh` (e.g., `addman::addon.install()`)
2. Modify logic following existing patterns
3. Ensure idempotency (safe to run repeatedly)
4. Add logging with appropriate level
5. Test with `log_level: trace` to verify function calls

### Adding Translations

1. Update `addman/translations/en.yaml` (English required)
2. Add corresponding translations in `addman/translations/de.yaml` (German)
3. Follow existing key structure
4. Use clear, concise descriptions for configuration options

## Dependencies

**Runtime dependencies (installed via Alpine APK):**
- `coreutils`: GNU core utilities
- `yq-go`: YAML processor (used for config parsing and merging)
- `bashio`: Home Assistant bash library (from base image)

**Base image:** `ghcr.io/hassio-addons/base:17.2.5`
- Provides Home Assistant integration
- Includes S6 overlay for process supervision
- Includes `bashio` library

## Recent Improvements (Latest Version)

### Bug Fixes
- **Fixed critical bash syntax error** (line 256): Corrected string indexing from `${value[0]}` to `${value:0:1}`
- **Added comprehensive error handling**: YAML parsing, addon operations (install/start/restart) now properly handle failures
- **Fixed word splitting vulnerability**: Converted all `for x in $(...)` loops to safe `while IFS= read -r` loops
- **Improved variable interpolation**: Repository URL comparison now uses `jq --arg` for safe variable passing

### Security Enhancements
- **Secret exposure prevention**: Configuration content is now hashed before logging (only shows hash, not full config)
- **Secrets file permission validation**: Warns if secrets file has overly permissive permissions (not 600/400)
- **Path traversal protection**: Validates `config_file` path doesn't contain `..` sequences
- **Improved error messages**: More descriptive errors for common failure scenarios

### New Features

#### 1. Dry-Run Mode (`dry_run: true`)
- Preview all changes without applying them
- Logs what would happen: repository additions, addon installations, configuration changes, start/restart operations
- Useful for testing configurations and debugging
- Default: `false`

#### 2. Auto-Uninstall Support (`auto_uninstall: true`)
- Automatically removes addons deleted from configuration
- Tracks managed addons in `/data/addman_state.json`
- Respects dry-run mode
- Safety feature: can be disabled to prevent accidental deletions
- Default: `true`

#### 3. Health Checks (`health_check_timeout: 10`)
- Verifies addons reach "started" state after start/restart operations
- Configurable timeout (1-60 seconds, default: 10)
- Checks every 2 seconds until timeout
- Logs warnings if health check fails but continues with other addons
- Default: `10` seconds

### Architecture Improvements
- **Graceful shutdown**: Properly handles SIGTERM/SIGINT signals
- **Configuration validation**: Validates config structure on startup, logs addon/repository counts
- **Targeted cache invalidation**: Only flushes repository cache when needed (not all caches)
- **Better error recovery**: Configuration reload failures use previous config instead of crashing

## Configuration Options

All options in `config.yaml`:

```yaml
options:
  check_interval: 600                  # Seconds between iterations
  check_updates_x_iterations: 6        # Check for updates every N iterations
  config_file: /config/addman.yaml     # Path to addon configuration
  log_level: info                      # trace|debug|info|notice|warning|error|fatal
  watch_config_changes: false          # Reload config on every iteration
  dry_run: false                       # NEW: Preview changes without applying
  auto_uninstall: true                 # NEW: Auto-remove deleted addons
  health_check_timeout: 10             # NEW: Addon startup verification timeout (1-60s)
```

## Known Limitations

1. No unit tests - validation relies on integration testing in Home Assistant
2. Requires running Home Assistant supervisor (cannot test standalone)
3. Configuration changes require add-on restart unless `watch_config_changes: true`
4. Secret files must be managed manually (not auto-generated)
5. Bash-only implementation limits testing capabilities
6. Bash strict mode (`set -euo pipefail`) not enabled - planned for future enhancement
7. Main function extraction deferred - current monolithic structure works but could be improved for maintainability
