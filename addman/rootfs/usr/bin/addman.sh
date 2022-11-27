#!/command/with-contenv bashio
# ==============================================================================
# Home Assistant Community Add-on: AddMan
#
# An add-on to configure them all.
# This add-on can install and configure other add-ons.
# ==============================================================================

# ------------------------------------------------------------------------------
# Converts a given YAML file or YAML string to YAML.
#
# Arguments:
#   $1 YAML string or path to a YAML file
# Returns:
#   JSON string
# ------------------------------------------------------------------------------
function addman::yaml_to_json() {
    local data=${1}

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    if [[ -f "${data}" ]]; then
        yq -M -N -oj "." "${data}"
    else
        yq -M -N -oj "." <<< "${data}"
    fi
}

# ------------------------------------------------------------------------------
# Checks if a given value needs to be quoted (for jq)
#
# Arguments:
#   $1 value
# ------------------------------------------------------------------------------
function addman::var.needs_quotes() {
    local value=${1:-null}

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    if [[ "${value}" =~ ^(y|Y|yes|Yes|YES|n|N|no|No|NO|true|True|TRUE|false|False|FALSE|on|On|ON|off|Off|OFF|[0-9]+)$ ]]; then
        return "${__BASHIO_EXIT_NOK}"
    fi

    return "${__BASHIO_EXIT_OK}"
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

    if bashio::var.false "$(bashio::jq "${response}" ".valid")"; then
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

    bashio::log.trace "${FUNCNAME[0]}"

    if bashio::cache.exists ".store.repositories"; then
        bashio::cache.get ".store.repositories"
        return "${__BASHIO_EXIT_OK}"
    fi

    response=$(bashio::api.supervisor GET "/store/repositories" false)
    bashio::cache.set ".store.repositories" "${response}"

    printf "%s" "${response}"

    return "${__BASHIO_EXIT_OK}"
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
        bashio::cache.flush_all
    else
        bashio::addons "${slug}" "addons.${slug}.ingress_panel" '.ingress_panel'
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
    local iterations=0

    bashio::log.trace "${FUNCNAME[0]}"

    watch_config_changes=$(bashio::config 'watch_config_changes')
    config_file=$(bashio::config 'config_file')
    check_updates_x_iterations=$(bashio::config 'check_updates_x_iterations')

    bashio::log.trace "Checking if $config_file exists..."
    if ! bashio::fs.file_exists "$config_file"; then
        if ! bashio::var.equals "$config_file" /config/addman.yaml; then
            return "${__BASHIO_EXIT_NOK}"
        fi
        bashio::log.info '[addman] Copy default config to /config/addman.yaml'
        cp /etc/addman/defaults.yaml /config/addman.yaml
    fi

    bashio::log.trace "Reading config from $config_file ..."
    config_content=$(addman::yaml_to_json "$config_file")
    bashio::log.trace "Got this config: $config_content"

    sleep=$(bashio::config 'check_interval')
    bashio::log.info "Seconds between checks is set to: ${sleep}"

    while true; do
        iterations=$(( iterations+1 ))

        if bashio::var.true "$watch_config_changes"; then
            bashio::log.trace "Reading config from $config_file ..."
            config_content=$(addman::yaml_to_json "$config_file")
            bashio::log.trace "Got this config: $config_content"
        fi
        bashio::log.trace "Start repositories iteration"

        local current_repositories
        local repository_changed="false"

        current_repositories=$(addman::addons.fetch_repositories)

        for repo in $(bashio::jq "$config_content" ".repositories[]"); do
            bashio::log.trace "Check if $repo exists"
            if bashio::jq.has_value "${current_repositories}" ".[] | select(.url == \"${repo}\")"; then
                bashio::log.trace "$repo already exists"
                continue
            fi
            bashio::log.info "Adding addon repository: $repo"
            addman::addons.add_repository "$repo"
            repository_changed="true"
        done

        if bashio::var.true "$repository_changed"; then
            bashio::log.info "Repositories have changed. Refreshing add-ons."
            bashio::addons.reload
        elif [[ $check_updates_x_iterations -gt 0 && $(( iterations % check_updates_x_iterations)) -eq 0 ]]; then
            bashio::log.info "This is the ${iterations}. iteration, time to check for updates."
            bashio::addons.reload
        fi

        bashio::log.trace "Start addon iteration"
        for slug in $(bashio::jq "$config_content" ".addons | keys | .[]"); do
            bashio::log.trace "[${slug}] Check if already installed"
            if bashio::var.false "$(bashio::addons.installed "$slug")"; then
                bashio::log.info "[${slug}] Installing add-on..."
                bashio::addon.install "$slug"
            fi

            # Configure the addon
            local addon_settings
            local addon_options
            local addon_changed="false"

            addon_settings=$(bashio::jq "$config_content" ".addons.\"${slug}\"")

            if bashio::jq.exists "$addon_settings" ".boot"; then
                bashio::addon.boot "$slug" "$(bashio::jq "$addon_settings" ".boot")"
            fi

            if bashio::jq.exists "$addon_settings" ".auto_update"; then
                bashio::addon.auto_update "$slug" "$(bashio::jq "$addon_settings" ".auto_update")"
            fi

            if bashio::jq.exists "$addon_settings" ".watchdog"; then
                bashio::addon.watchdog "$slug" "$(bashio::jq "$addon_settings" ".watchdog")"
            fi

            if bashio::jq.exists "$addon_settings" ".ingress_panel"; then
                addman::addon.ingress_panel "$slug" "$(bashio::jq "$addon_settings" ".ingress_panel")"
            fi

            if bashio::jq.exists "$addon_settings" ".options"; then
                local current_options
                current_options=$(bashio::addon.options "$slug")

                addon_options=$(bashio::jq "$addon_settings" ".options")
                bashio::log.trace "[${slug}] Found these options $addon_options"

                if addman::addon.validate_options "$addon_options" "$slug"; then
                    for key in $(bashio::jq "$addon_options" "keys | .[]"); do
                        bashio::log.trace "[${slug}] Getting value of $key"
                        local value
                        value=$(bashio::jq "$addon_options" ".\"${key}\"")
                        if ! bashio::var.equals "$(bashio::jq "$current_options" ".\"${key}\"")" "$value"; then
                            bashio::log.info "[${slug}] Setting $key to $value"
                            if addman::var.needs_quotes "$value"; then
                                bashio::addon.option "$key" "$value" "$slug"
                            else
                                bashio::addon.option "$key" "^$value" "$slug"
                            fi
                            addon_changed="true"
                        fi
                    done
                else
                    bashio::log.error "[${slug}] Invalid options detected. Skip."
                    continue
                fi
            fi

            if bashio::jq.exists "$addon_settings" ".start"; then
                bashio::log.warning "[${slug}] start is now called auto_start and will be removed in the future."
                addon_settings=$(bashio::jq "$addon_settings" ".auto_start = .start")
            fi

            if bashio::jq.exists "$addon_settings" ".auto_start"; then
                if bashio::var.true "$(bashio::jq "$addon_settings" ".auto_start")"; then
                    if ! bashio::var.equals "$(bashio::addon.state "$slug")" "started"; then
                        bashio::log.info "[${slug}] Starting add-on..."
                        bashio::addon.start "$slug"
                    elif bashio::var.true "$addon_changed"; then
                        if ! bashio::jq.exists "$addon_settings" ".auto_restart" || \
                             bashio::var.true "$(bashio::jq "$addon_settings" ".auto_restart")"; then
                                bashio::log.info "[${slug}] Options changed. Restarting add-on..."
                                bashio::addon.restart "$slug"
                        fi
                    fi
                fi
            fi
        done

        sleep "${sleep}"
    done
}
main "$@"
