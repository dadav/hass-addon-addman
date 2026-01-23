# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AddMan is a Home Assistant add-on that enables declarative, git-based management of other Home Assistant add-ons. It continuously syncs add-on installations and configurations from YAML files, allowing version-controlled infrastructure-as-code for Home Assistant instances.

**Core Technology**: Bash scripting, Home Assistant Supervisor API, Docker containers

## Key Commands

### Testing & Validation

```bash
# Lint YAML files and add-on structure
# Note: Linting runs automatically via GitHub Actions on push/PR

# Manual YAML validation (if yamllint is installed locally)
yamllint -c .yamllint .

# Test build locally (requires Docker)
docker build -t addman-test ./addman
```

### Building

```bash
# Builds are handled exclusively by GitHub Actions (.github/workflows/builder.yaml)
# Triggered on: push to main, pull requests
# Builds for: aarch64, amd64
# Output: ghcr.io/dadav/addman:VERSION

# The builder only rebuilds when these files change:
# - build.yaml
# - config.yaml
# - Dockerfile
# - rootfs/
```

### Development Workflow

There are no local development commands. This add-on is developed and tested by:

1. Making code changes to `addman/rootfs/usr/bin/addman.sh`
2. Updating version in `addman/config.yaml`
3. Pushing to GitHub (triggers build)
4. Installing/updating in Home Assistant Supervisor
5. Testing with live configuration files

## Architecture

### High-Level Structure

```
Main Script: addman/rootfs/usr/bin/addman.sh
    ↓
Continuous Loop (sleep N seconds between iterations)
    ↓
Read Configuration: /config/addman.yaml
    ↓
For each configured repository:
    → Add repository via Supervisor API (if missing)
    ↓
For each configured add-on:
    → Install add-on via Supervisor API (if missing)
    → Validate options via Supervisor API
    → Configure: boot, watchdog, auto_update, ingress_panel, options
    → Start/restart based on auto_start/auto_restart flags
```

### Key Implementation Details

**Main Loop Pattern**:
- Runs indefinitely in a loop
- Sleeps for `check_interval` seconds between iterations
- Optionally re-reads config file each iteration (if `watch_config_changes: true`)
- Periodically triggers "check for updates" every N iterations

**Core Functions** (in addman.sh):
- `addman::addons.fetch_repositories()` - Caches list of installed repositories
- `addman::addons.add_repository()` - Adds missing repositories
- `addman::yaml_to_json()` - Converts YAML to JSON with secrets file merging
- `addman::var.is_yaml_bool()` - Detects YAML booleans to preserve type in JSON
- `addman::addon.validate_options()` - Validates options against add-on schema before applying

**Configuration Management**:
1. User creates `/config/addman.yaml` with desired add-on state
2. Optional `/config/addman.yaml.secrets` contains YAML anchors for sensitive data
3. AddMan merges secrets, converts YAML to JSON, validates via API
4. Applies configuration only if validation succeeds
5. Restarts add-ons only if `auto_restart: true` (default) and config changed

**API Communication**:
All operations use the Home Assistant Supervisor REST API via `curl`. The base URL is typically `http://supervisor/` and requires the `SUPERVISOR_TOKEN` environment variable (automatically provided by Home Assistant).

### Critical Design Constraints

1. **No State Persistence**: Each iteration treats the configuration as the source of truth. No database or state files.

2. **Idempotent Operations**: Safe to run repeatedly. Only applies changes when current state differs from desired state.

3. **Validation Before Application**: Always validates add-on options via Supervisor API before applying to prevent breaking add-ons.

4. **Boolean Type Preservation**: YAML booleans (true/false) must remain booleans in JSON, not strings. The script uses regex detection to handle this.

5. **Secrets Management**: Secrets use standard YAML anchors/aliases. The secrets file is merged at runtime before processing.

## Configuration Schema

### Add-on Configuration (`config.yaml`)

This file defines the AddMan add-on itself:
- `version` - Semantic version (manually updated on each release)
- `slug` - Must be `addman`
- `arch` - Supported architectures (currently: aarch64, amd64)
- `startup` - Startup type (currently: `services`)
- `boot` - When to start (currently: `auto`)

When changing the add-on's own behavior or requirements, update this file.

### User Configuration (`addman.yaml`)

Structure:
```yaml
repositories:
  - https://github.com/owner/repo

addons:
  addon_slug:
    auto_start: true          # Start after installation
    auto_restart: true        # Restart when options change (default: true)
    boot: auto                # "auto" or "manual"
    watchdog: true            # Enable watchdog monitoring
    auto_update: true         # Enable automatic updates
    ingress_panel: false      # Show in Home Assistant sidebar
    options:                  # Add-on-specific options
      key: value
```

**Important**: The `addon_slug` must match the add-on's official slug in the Supervisor API, not the display name.

## Home Assistant Integration Points

### Supervisor API Endpoints Used

- `GET /addons` - List installed add-ons
- `GET /store` - List available add-ons in store
- `POST /store/repositories` - Add new repository
- `POST /addons/{slug}/install` - Install add-on
- `POST /addons/{slug}/start` - Start add-on
- `POST /addons/{slug}/restart` - Restart add-on
- `POST /addons/{slug}/options/validate` - Validate options before applying
- `POST /addons/{slug}/options` - Apply add-on options
- `POST /addons/{slug}/boot` - Set boot behavior
- `POST /addons/{slug}/watchdog` - Enable/disable watchdog
- `POST /addons/{slug}/auto_update` - Enable/disable auto-updates
- `POST /supervisor/options` - Trigger supervisor update check

### Security Model

**AppArmor Profile** (`apparmor.txt`):
- Read-only access to `/config/` (for user configuration)
- Read-write access to `/data/`, `/tmp/`
- Restricted network access (can only communicate with Supervisor)
- Limited binary execution (only specific tools like `yq`, `jq`, `curl`)

The add-on runs with `hassio_api: true` privilege to communicate with the Supervisor API.

## Testing Strategy

There are no automated unit tests. Testing happens via:

1. **Linting**: GitHub Actions runs `frenck/action-addon-linter` on all changes
2. **Manual Testing**: Install the add-on in a live Home Assistant instance
3. **Validation**: The script validates all options via Supervisor API before applying

To test changes:
1. Update code in `addman/rootfs/usr/bin/addman.sh`
2. Bump version in `addman/config.yaml`
3. Commit and push (triggers build)
4. Install/update from the repository in Home Assistant
5. Configure test add-ons in `/config/addman.yaml`
6. Monitor logs via Home Assistant UI or `docker logs addon_XXX_addman`

## Versioning & Release Process

**Versioning**: Follows Semantic Versioning (MAJOR.MINOR.PATCH)
- Increment MAJOR for breaking changes to configuration format
- Increment MINOR for new features (e.g., new options, new API endpoints)
- Increment PATCH for bug fixes

**Release Steps**:
1. Update `addman/config.yaml` version field
2. Update `addman/CHANGELOG.md` with changes
3. Commit with message like "chore: version++"
4. Push to main branch
5. GitHub Actions automatically builds and publishes to ghcr.io
6. Users can update via Home Assistant UI

**Note**: The `version` field in `config.yaml` must be manually updated. Renovate only handles dependency updates (base images, actions).

## Common Pitfalls

1. **Boolean Quoting**: When adding options, ensure YAML booleans remain unquoted. The script detects and preserves them, but manual JSON construction can break this.

2. **Add-on Slugs**: Use the exact slug from the Supervisor API, not the display name. Find slugs via `GET /addons` or in the add-on's `config.yaml`.

3. **Option Validation**: Always test option changes with small iterations. The script validates before applying, but invalid options will log errors and skip that add-on.

4. **Auto-restart**: By default, changing any option restarts the add-on. Set `auto_restart: false` to prevent this for sensitive add-ons.

5. **Repository URLs**: Must be full GitHub URLs (https://github.com/owner/repo). The Supervisor API rejects other formats.

## Debugging

**Enable Debug Logging**:
Set `log_level: debug` in the AddMan add-on configuration (via Home Assistant UI).

**View Logs**:
- Via Home Assistant UI: Supervisor → AddMan → Log tab
- Via CLI: `docker logs addon_<hash>_addman`

**Common Issues**:

- **"Options validation failed"**: The options you specified don't match the add-on's schema. Check the add-on's documentation for required fields and types.

- **"Repository already exists"**: Harmless warning. The script checks before adding but may log this if the repository was added manually.

- **Add-on not installing**: Check the slug is correct and the repository is added first. Verify via `GET /store` API endpoint.

- **Configuration not applying**: If `watch_config_changes: false`, you must restart AddMan after editing `addman.yaml`. If `true`, changes apply within `check_interval` seconds.

## Dependencies

**Runtime Dependencies** (in Dockerfile):
- `bashio` - Home Assistant Bash library (provides logging, API helpers)
- `yq` - YAML processor for parsing configuration files
- `coreutils` - Standard Unix utilities
- `curl` - HTTP client for Supervisor API calls
- `jq` - JSON processor for API response handling

**Build Dependencies**:
- Base image: `ghcr.io/hassio-addons/base:19.0.0`
- Home Assistant builder action: `home-assistant/builder@2025.11.0`

**When updating dependencies**:
- Base image: Update in `addman/build.yaml` (Renovate handles this automatically)
- Bashio: Automatically included in base image
- Other tools: Add to Dockerfile `RUN apk add --no-cache PACKAGE`
