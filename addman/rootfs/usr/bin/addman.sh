#!/command/with-contenv bashio
# ==============================================================================
# Home Assistant Community Add-on: AddMan
#
# An add-on to configure them all.
# This add-on can install and configure other add-ons.
# ==============================================================================
#
# IMPORTANT: Base image 19.0.0 uses jq 1.8.1 which has breaking changes:
# - tonumber/0 now rejects numbers with leading/trailing whitespace
# - Stricter JSON parsing
# Some bashio library functions (especially cache operations) use jq internally
# and may produce "Invalid numeric literal" errors. We suppress these errors
# where they don't affect functionality.
# ==============================================================================

# ------------------------------------------------------------------------------
# Converts a given YAML file to a json string.
# Also looks for a $path.secrets file so you can use secrets
# in your $path file.
#
# Arguments:
#   $1 path to a YAML file
# Returns:
#   JSON string
# ------------------------------------------------------------------------------
function addman::yaml_to_json() {
    local path=${1}
    local result

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    if bashio::fs.file_exists "${path}.secrets"; then
        # Check secrets file permissions
        local perms
        perms=$(stat -c "%a" "${path}.secrets" 2>/dev/null || echo "000")
        if [[ "$perms" != "600" ]] && [[ "$perms" != "400" ]]; then
            bashio::log.warning "Secrets file has permissive permissions ($perms). Recommend chmod 600 ${path}.secrets"
        fi
        bashio::log.trace "Reading the secrets file (${path}.secrets)."
        # Concatenate secrets and main config into single YAML stream, then merge documents
        # This allows anchors from secrets to be referenced in main config
        if ! result=$(cat "${path}.secrets" <(echo) "${path}" <(echo) | yq -M -N -oj eval-all '. as $item ireduce ({}; . * $item) | explode(.)' 2>&1); then
            bashio::log.error "Failed to parse YAML with secrets: $result"
            return "${__BASHIO_EXIT_NOK}"
        fi
    else
        if ! result=$(yq -M -N -oj "explode(.)" "${path}" 2>&1); then
            bashio::log.error "Failed to parse YAML: $result"
            return "${__BASHIO_EXIT_NOK}"
        fi
    fi

    echo "$result"
    return "${__BASHIO_EXIT_OK}"
}

# ------------------------------------------------------------------------------
# Checks if a given value needs to be quoted (for jq)
#
# Arguments:
#   $1 value
# ------------------------------------------------------------------------------
function addman::var.is_yaml_bool() {
    local value=${1:-null}

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    if [[ "${value}" =~ ^(y|Y|yes|Yes|YES|n|N|no|No|NO|true|True|TRUE|false|False|FALSE|on|On|ON|off|Off|OFF|[0-9]+)$ ]]; then
        return "${__BASHIO_EXIT_OK}"
    fi

    return "${__BASHIO_EXIT_NOK}"
}

# ------------------------------------------------------------------------------
# Check if the given options are valid
#
# Arguments:
#   $1 Addon options as String
# ------------------------------------------------------------------------------
function addman::addon.validate_options() {
    local data=${1}
    local slug=${2:-self}
    local response

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    response=$(bashio::api.supervisor POST "/addons/${slug}/options/validate" "$data")

    if bashio::var.false "$(echo "${response}" | jq -r '.valid')"; then
        bashio::log.trace "response: ${response}"
        return "${__BASHIO_EXIT_NOK}"
    fi

    return "${__BASHIO_EXIT_OK}"
}


# ------------------------------------------------------------------------------
# Fetch the currently installed repositories
#
# Returns
# List of repo objects
# ------------------------------------------------------------------------------
function addman::addons.fetch_repositories() {
    local response
    local cache_file="/tmp/addman_repositories.cache"

    bashio::log.trace "${FUNCNAME[0]}"

    # Use simple file-based cache instead of bashio::cache (which has jq 1.8.1 issues)
    if [[ -f "$cache_file" ]]; then
        response=$(cat "$cache_file" 2>/dev/null || echo "")
        if [[ -n "$response" ]]; then
            printf "%s" "${response}"
            return "${__BASHIO_EXIT_OK}"
        fi
    fi

    # Fetch from API (jq errors are filtered globally)
    if response=$(bashio::api.supervisor GET "/store/repositories" false); then
        # Cache to simple file (avoid bashio::cache which has jq compatibility issues)
        echo "$response" > "$cache_file" 2>/dev/null || true
        printf "%s" "${response}"
        return "${__BASHIO_EXIT_OK}"
    else
        bashio::log.error "Failed to fetch repositories from supervisor API"
        return "${__BASHIO_EXIT_NOK}"
    fi
}

# ------------------------------------------------------------------------------
# Install a new addon repository
#
# Arguments:
#   $1 URL of the repository to add
#
# ------------------------------------------------------------------------------
function addman::addons.add_repository() {
    local repo=${1}
    local response

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    if bashio::var.has_value "${repo}"; then
        repo=$(bashio::var.json repository "${repo}")
        bashio::api.supervisor POST "/store/repositories" "${repo}"
    else
        return "${__BASHIO_EXIT_NOK}"
    fi

    return "${__BASHIO_EXIT_OK}"
}

# ------------------------------------------------------------------------------
# Returns the current ingress_panel setting of this add-on.
#
# Arguments:
#   $1 Add-on slug (optional, default: self)
#   $2 Sets ingress_panel setting (optional).
# ------------------------------------------------------------------------------
function addman::addon.ingress_panel() {
    local slug=${1:-'self'}
    local ingress=${2:-}

    bashio::log.trace "${FUNCNAME[0]}" "$@"

    if bashio::var.has_value "${ingress}"; then
        ingress=$(bashio::var.json ingress_panel "${ingress}")
        bashio::api.supervisor POST "/addons/${slug}/options" "${ingress}"
        # Only flush repository cache, not all caches
        bashio::cache.flush ".store.repositories"
    else
        bashio::addons "${slug}" "addons.${slug}.ingress_panel" '.ingress_panel'
    fi
}

# ------------------------------------------------------------------------------
# Safely check if an addon is installed with error handling for jq issues
#
# Arguments:
#   $1 Addon slug
#
# Returns:
#   0 if addon is installed, 1 otherwise
# ------------------------------------------------------------------------------
addman::addon.is_installed() {
    local slug=${1}
    local result
    local retries=3
    local attempt=1

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    while [[ $attempt -le $retries ]]; do
        # Call bashio function (jq errors are filtered globally)
        if result=$(bashio::addons.installed "$slug" 2>&1); then
            # Check if result is a valid boolean string
            if [[ "$result" == "true" ]] || [[ "$result" == "false" ]]; then
                echo "$result"
                return "${__BASHIO_EXIT_OK}"
            fi
        fi

        # If we got an error or invalid result, retry after a delay
        bashio::log.trace "[${slug}] Addon status check failed (attempt $attempt/$retries), retrying..."
        sleep 2
        attempt=$((attempt + 1))
    done

    # If all retries failed, assume addon is not installed
    bashio::log.warning "[${slug}] Could not determine addon status after $retries attempts, assuming not installed"
    echo "false"
    return "${__BASHIO_EXIT_NOK}"
}

# ------------------------------------------------------------------------------
# Verify that an addon is running after start/restart
#
# Arguments:
#   $1 Addon slug
#   $2 Timeout in seconds (optional, default from config)
#
# Returns:
#   0 if addon is running, 1 otherwise
# ------------------------------------------------------------------------------
addman::addon.verify_running() {
    local slug=${1}
    local timeout=${2:-10}
    local max_attempts=$((timeout / 2))
    local attempt=1

    bashio::log.trace "${FUNCNAME[0]}:" "$@"
    bashio::log.debug "[${slug}] Verifying addon is running (timeout: ${timeout}s)..."

    while [[ $attempt -le $max_attempts ]]; do
        local state
        # Get addon state (jq errors are filtered globally)
        state=$(bashio::addon.state "$slug")

        if [[ "$state" == "started" ]]; then
            bashio::log.debug "[${slug}] Addon is running"
            return "${__BASHIO_EXIT_OK}"
        fi

        bashio::log.trace "[${slug}] State: $state, attempt $attempt/$max_attempts"
        sleep 2
        attempt=$((attempt + 1))
    done

    bashio::log.error "[${slug}] Addon failed health check (final state: $state)"
    return "${__BASHIO_EXIT_NOK}"
}

# ------------------------------------------------------------------------------
# Save currently managed addon slugs to state file
#
# Arguments:
#   $1 JSON array of addon slugs
# ------------------------------------------------------------------------------
addman::state.save_managed_addons() {
    local addons=${1}
    local state_file="/data/addman_state.json"

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    echo "$addons" > "$state_file"
}

# ------------------------------------------------------------------------------
# Get previously managed addon slugs from state file
#
# Returns:
#   JSON array of addon slugs (or empty array if no state file)
# ------------------------------------------------------------------------------
addman::state.get_managed_addons() {
    local state_file="/data/addman_state.json"

    bashio::log.trace "${FUNCNAME[0]}"

    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo "[]"
    fi
}

# ==============================================================================
# RUN LOGIC
# ------------------------------------------------------------------------------
main() {
    local sleep
    local check_updates_x_iterations
    local config_file
    local config_content
    local watch_config_changes
    local dry_run
    local auto_uninstall
    local health_check_timeout
    local iterations=0

    bashio::log.trace "${FUNCNAME[0]}"

    # Globally suppress jq errors from bashio library (jq 1.8.1 compatibility issue in base image 19.0.0)
    # Save original stderr, then redirect stderr through a filter that removes jq parse errors
    exec 3>&2
    exec 2> >(grep -v "jq: parse error: Invalid numeric literal" >&3)

    # Ensure stderr filter process is cleaned up on exit
    trap 'exec 2>&3; exec 3>&-' EXIT

    watch_config_changes=$(bashio::config 'watch_config_changes')
    config_file=$(bashio::config 'config_file')
    check_updates_x_iterations=$(bashio::config 'check_updates_x_iterations')
    dry_run=$(bashio::config 'dry_run')
    auto_uninstall=$(bashio::config 'auto_uninstall')
    health_check_timeout=$(bashio::config 'health_check_timeout')

    # Validate config file path to prevent traversal attacks
    if [[ "$config_file" == *".."* ]]; then
        bashio::log.fatal "Config file path contains '..' which is not allowed for security reasons"
        bashio::exit.nok
    fi

    if [[ ! "$config_file" =~ ^/(config|share|ssl|addons|backup)/ ]]; then
        bashio::log.warning "Config file not in standard Home Assistant directory: $config_file"
    fi

    bashio::log.trace "Checking if $config_file exists..."
    if ! bashio::fs.file_exists "$config_file"; then
        if ! bashio::var.equals "$config_file" /config/addman.yaml; then
            return "${__BASHIO_EXIT_NOK}"
        fi
        bashio::log.info '[addman] Copy default config to /config/addman.yaml'
        cp /etc/addman/defaults.yaml /config/addman.yaml
    fi

    bashio::log.trace "Reading config from $config_file ..."
    if ! config_content=$(addman::yaml_to_json "$config_file"); then
        bashio::log.fatal "Failed to parse configuration file: $config_file"
        bashio::exit.nok
    fi
    # Hash config to avoid exposing secrets in logs
    local config_hash
    config_hash=$(echo "$config_content" | sha256sum | cut -d' ' -f1)
    bashio::log.trace "Config loaded successfully (hash: ${config_hash:0:8})"

    # Debug: Show addon keys found in config
    if echo "$config_content" | jq -e '.addons' >/dev/null 2>&1; then
        local addon_count
        addon_count=$(echo "$config_content" | jq -r '.addons | length')
        bashio::log.info "Found ${addon_count} addon(s) to manage"

        # Debug: List addon slugs
        local addon_slugs
        addon_slugs=$(echo "$config_content" | jq -r '.addons | keys[]? // empty' | tr '\n' ' ')
        if [[ -n "$addon_slugs" ]]; then
            bashio::log.debug "Addon slugs: ${addon_slugs}"
        else
            bashio::log.warning "No addon slugs found in configuration!"
            bashio::log.debug "Config structure: $(echo "$config_content" | jq -c 'keys')"
        fi
    else
        bashio::log.warning "Configuration has no addons section defined"
    fi

    if ! echo "$config_content" | jq -e '.repositories' >/dev/null 2>&1 && ! echo "$config_content" | jq -e '.addons' >/dev/null 2>&1; then
        bashio::log.warning "Configuration has no repositories or addons defined - nothing to manage"
    fi

    if echo "$config_content" | jq -e '.repositories' >/dev/null 2>&1; then
        local repo_count
        repo_count=$(echo "$config_content" | jq -r '.repositories | length')
        bashio::log.info "Found ${repo_count} repository(ies) to add"
    fi

    sleep=$(bashio::config 'check_interval')
    bashio::log.info "Seconds between checks is set to: ${sleep}"

    if bashio::var.true "$dry_run"; then
        bashio::log.warning "DRY-RUN MODE ENABLED - No changes will be made to the system"
    fi

    # Setup graceful shutdown handler
    cleanup() {
        bashio::log.info "Received shutdown signal, exiting gracefully..."
        exit 0
    }
    trap cleanup SIGTERM SIGINT

    while true; do
        iterations=$(( iterations+1 ))

        if bashio::var.true "$watch_config_changes"; then
            bashio::log.trace "Reading config from $config_file ..."
            if ! config_content=$(addman::yaml_to_json "$config_file"); then
                bashio::log.error "Failed to reload configuration file: $config_file - using previous config"
                # Continue with previous config_content instead of exiting
            else
                # Hash config to avoid exposing secrets in logs
                local config_hash
                config_hash=$(echo "$config_content" | sha256sum | cut -d' ' -f1)
                bashio::log.trace "Config reloaded successfully (hash: ${config_hash:0:8})"
            fi
        fi
        bashio::log.trace "Start repositories iteration"

        local current_repositories
        local repository_changed="false"

        current_repositories=$(addman::addons.fetch_repositories)

        while IFS= read -r repo; do
            [[ -z "$repo" ]] && continue  # Skip empty lines
            bashio::log.trace "Check if $repo exists"
            # Use jq --arg for safe variable interpolation
            if echo "${current_repositories}" | jq -e --arg url "$repo" '.[] | select(.url == $url)' > /dev/null; then
                bashio::log.trace "$repo already exists"
                continue
            fi
            if bashio::var.true "$dry_run"; then
                bashio::log.info "[DRY-RUN] Would add repository: $repo"
            else
                bashio::log.info "Adding addon repository: $repo"
                addman::addons.add_repository "$repo"
            fi
            repository_changed="true"
        done < <(echo "$config_content" | jq -r '.repositories[]? // empty')

        if bashio::var.true "$repository_changed"; then
            # Invalidate repository cache when repositories change (use simple file-based cache)
            rm -f /tmp/addman_repositories.cache 2>/dev/null || true
            bashio::log.info "Repositories have changed. Refreshing add-ons."
            # Call reload (jq errors from bashio cache are filtered globally)
            bashio::addons.reload || bashio::log.warning "Failed to reload addons"
        elif [[ $check_updates_x_iterations -gt 0 && $(( iterations % check_updates_x_iterations)) -eq 0 ]]; then
            bashio::log.info "This is the ${iterations}. iteration, time to check for updates."
            # Call reload (jq errors from bashio cache are filtered globally)
            bashio::addons.reload || bashio::log.warning "Failed to reload addons"
        fi

        bashio::log.trace "Start addon iteration"
        while IFS= read -r slug; do
            [[ -z "$slug" ]] && continue  # Skip empty lines
            bashio::log.trace "[${slug}] Check if already installed"
            if bashio::var.false "$(addman::addon.is_installed "$slug")"; then
                if bashio::var.true "$dry_run"; then
                    bashio::log.info "[DRY-RUN] Would install addon: ${slug}"
                else
                    bashio::log.info "[${slug}] Installing add-on..."
                    if ! bashio::addon.install "$slug"; then
                        bashio::log.error "[${slug}] Failed to install addon - skipping configuration"
                        continue
                    fi
                    bashio::log.info "[${slug}] Successfully installed"
                fi
            fi

            # Configure the addon
            local addon_settings
            local addon_options
            local addon_changed="false"

            addon_settings=$(echo "$config_content" | jq ".addons.\"${slug}\"")

            if echo "$addon_settings" | jq -e '.boot' >/dev/null 2>&1; then
                bashio::addon.boot "$slug" "$(echo "$addon_settings" | jq -r '.boot')"
            fi

            if echo "$addon_settings" | jq -e '.auto_update' >/dev/null 2>&1; then
                bashio::addon.auto_update "$slug" "$(echo "$addon_settings" | jq -r '.auto_update')"
            fi

            if echo "$addon_settings" | jq -e '.watchdog' >/dev/null 2>&1; then
                bashio::addon.watchdog "$slug" "$(echo "$addon_settings" | jq -r '.watchdog')"
            fi

            if echo "$addon_settings" | jq -e '.ingress_panel' >/dev/null 2>&1; then
                addman::addon.ingress_panel "$slug" "$(echo "$addon_settings" | jq -r '.ingress_panel')"
            fi

            if echo "$addon_settings" | jq -e '.options' >/dev/null 2>&1; then
                local current_options
                # Get current options (jq errors are filtered globally)
                current_options=$(bashio::addon.options "$slug" || echo "{}")

                addon_options=$(echo "$addon_settings" | jq '.options')
                bashio::log.trace "[${slug}] Found these options $addon_options"

                if addman::addon.validate_options "$addon_options" "$slug"; then
                    while IFS= read -r key; do
                        [[ -z "$key" ]] && continue  # Skip empty lines
                        bashio::log.trace "[${slug}] Getting value of $key"
                        local value
                        value=$(echo "$addon_options" | jq ".\"${key}\"")
                        if ! bashio::var.equals "$(echo "$current_options" | jq ".\"${key}\"")" "$value"; then
                            if bashio::var.true "$dry_run"; then
                                bashio::log.info "[DRY-RUN] Would set ${slug}.${key} to $value"
                            else
                                bashio::log.info "[${slug}] Setting $key to $value"
                                if addman::var.is_yaml_bool "$value" || [[ "${value:0:1}" =~ [\[{] ]]; then
                                    bashio::addon.option "$key" "^$value" "$slug"
                                else
                                    bashio::addon.option "$key" "$value" "$slug"
                                fi
                            fi
                            addon_changed="true"
                        fi
                    done < <(echo "$addon_options" | jq -r 'keys[]? // empty')
                else
                    bashio::log.error "[${slug}] Invalid options detected. Skip."
                    continue
                fi
            fi

            if echo "$addon_settings" | jq -e '.start' >/dev/null 2>&1; then
                bashio::log.warning "[${slug}] start is now called auto_start and will be removed in the future."
                addon_settings=$(echo "$addon_settings" | jq '.auto_start = .start')
            fi

            if echo "$addon_settings" | jq -e '.auto_start' >/dev/null 2>&1; then
                if bashio::var.true "$(echo "$addon_settings" | jq -r '.auto_start')"; then
                    if ! bashio::var.equals "$(bashio::addon.state "$slug")" "started"; then
                        if bashio::var.true "$dry_run"; then
                            bashio::log.info "[DRY-RUN] Would start addon: ${slug}"
                        else
                            bashio::log.info "[${slug}] Starting add-on..."
                            if bashio::addon.start "$slug"; then
                                # Verify addon started successfully
                                if ! addman::addon.verify_running "$slug" "$health_check_timeout"; then
                                    bashio::log.warning "[${slug}] Addon started but failed health check"
                                fi
                            else
                                bashio::log.error "[${slug}] Failed to start addon"
                            fi
                        fi
                    elif bashio::var.true "$addon_changed"; then
                        if ! echo "$addon_settings" | jq -e '.auto_restart' >/dev/null 2>&1 || \
                             bashio::var.true "$(echo "$addon_settings" | jq -r '.auto_restart')"; then
                                if bashio::var.true "$dry_run"; then
                                    bashio::log.info "[DRY-RUN] Would restart addon: ${slug}"
                                else
                                    bashio::log.info "[${slug}] Options changed. Restarting add-on..."
                                    if bashio::addon.restart "$slug"; then
                                        # Verify addon restarted successfully
                                        if ! addman::addon.verify_running "$slug" "$health_check_timeout"; then
                                            bashio::log.warning "[${slug}] Addon restarted but failed health check"
                                        fi
                                    else
                                        bashio::log.error "[${slug}] Failed to restart addon"
                                    fi
                                fi
                        fi
                    fi
                fi
            fi
        done < <(echo "$config_content" | jq -r '.addons | keys[]? // empty')

        # Handle addon uninstall if auto_uninstall is enabled
        if bashio::var.true "$auto_uninstall"; then
            local previous_addons
            local current_addon_slugs

            previous_addons=$(addman::state.get_managed_addons)
            current_addon_slugs=$(echo "$config_content" | jq -r -c '.addons | keys? // []')

            # Find addons that were managed but are no longer in config
            while IFS= read -r slug; do
                [[ -z "$slug" ]] && continue
                # Check if this slug is still in the current config
                if ! echo "$config_content" | jq -e --arg s "$slug" '.addons | has($s)' > /dev/null 2>&1; then
                    bashio::log.info "[${slug}] Addon removed from config"
                    if bashio::var.true "$dry_run"; then
                        bashio::log.info "[DRY-RUN] Would uninstall: ${slug}"
                    else
                        if bashio::addon.uninstall "$slug"; then
                            bashio::log.info "[${slug}] Successfully uninstalled"
                        else
                            bashio::log.error "[${slug}] Failed to uninstall"
                        fi
                    fi
                fi
            done < <(echo "$previous_addons" | jq -r '.[]? // empty')

            # Save current state for next iteration
            if ! bashio::var.true "$dry_run"; then
                addman::state.save_managed_addons "$current_addon_slugs"
            fi
        fi

        sleep "${sleep}"
    done
}
main "$@"
