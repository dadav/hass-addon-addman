#!/command/with-contenv bashio
# ==============================================================================
# Home Assistant Community Add-on: AddMan
#
# An add-on to configure them all.
# This add-on can install and configure other add-ons.
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

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    if bashio::fs.file_exists "${path}.secrets"; then
        bashio::log.trace "Reading the secrets file (${path}.secrets)."
        # For-loop is need to add a newline after the secret file
        yq -M -N -oj --yaml-fix-merge-anchor-to-spec "explode(.) | select(document_index == 1)" <(for f in "${path}.secrets" "${path}"; do cat "$f"; echo; done)
    else
        yq -M -N -oj --yaml-fix-merge-anchor-to-spec "." "${path}"
    fi
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

    if bashio::var.false "$(bashio::jq "${response}" ".valid")"; then
        bashio::log.trace "response: ${response}"
        bashio::log.info "[${slug}] Invalid options: $(bashio::jq "${response}" ".message // \"unknown error\"")"
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
# Uninstall an add-on (used for declarative removal via `state: absent`).
#
# Mirrors the direct Supervisor API pattern used by add_repository because
# bashio does not ship an uninstall helper.
#
# Arguments:
#   $1 Add-on slug
# ------------------------------------------------------------------------------
function addman::addon.uninstall() {
    local slug=${1}

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    bashio::api.supervisor POST "/addons/${slug}/uninstall"
    bashio::cache.flush_all

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
    local dry_run
    local watch_config_changes
    local iterations=0

    bashio::log.trace "${FUNCNAME[0]}"

    watch_config_changes=$(bashio::config 'watch_config_changes')
    config_file=$(bashio::config 'config_file')
    dry_run=$(bashio::config 'dry_run' 'false')
    check_updates_x_iterations=$(bashio::config 'check_updates_x_iterations')

    if bashio::var.true "$dry_run"; then
        bashio::log.warning "[dry-run] AddMan will only log planned changes."
    fi

    bashio::log.trace "Checking if $config_file exists..."
    if ! bashio::fs.file_exists "$config_file"; then
        if ! bashio::var.equals "$config_file" /config/addman.yaml; then
            return "${__BASHIO_EXIT_NOK}"
        fi
        if bashio::var.true "$dry_run"; then
            bashio::log.info '[dry-run] Would copy default config to /config/addman.yaml'
            config_file=/etc/addman/defaults.yaml
        else
            bashio::log.info '[addman] Copy default config to /config/addman.yaml'
            cp /etc/addman/defaults.yaml /config/addman.yaml
        fi
    fi

    bashio::log.trace "Reading config from $config_file ..."
    config_content=$(addman::yaml_to_json "$config_file")
    bashio::log.trace "Loaded config from $config_file."

    sleep=$(bashio::config 'check_interval')
    bashio::log.info "Seconds between checks is set to: ${sleep}"

    while true; do
        iterations=$(( iterations+1 ))

        if bashio::var.true "$watch_config_changes"; then
            bashio::log.trace "Reading config from $config_file ..."
            config_content=$(addman::yaml_to_json "$config_file")
            bashio::log.trace "Loaded config from $config_file."
        fi
        bashio::log.trace "Start repositories iteration"

        local current_repositories
        local repository_changed="false"

        current_repositories=$(addman::addons.fetch_repositories)

        for repo in $(bashio::jq "$config_content" ".repositories // [] | .[]"); do
            bashio::log.trace "Check if $repo exists"
            if bashio::jq.has_value "${current_repositories}" ".[] | select(.url == \"${repo}\")"; then
                bashio::log.trace "$repo already exists"
                continue
            fi
            if bashio::var.true "$dry_run"; then
                bashio::log.info "[dry-run] Would add addon repository: $repo"
            else
                bashio::log.info "Adding addon repository: $repo"
                addman::addons.add_repository "$repo"
            fi
            repository_changed="true"
        done

        if bashio::var.true "$repository_changed"; then
            if bashio::var.true "$dry_run"; then
                bashio::log.info "[dry-run] Would refresh add-ons after repository changes."
            else
                bashio::log.info "Repositories have changed. Refreshing add-ons."
                bashio::addons.reload
            fi
        elif [[ $check_updates_x_iterations -gt 0 && $(( iterations % check_updates_x_iterations)) -eq 0 ]]; then
            if bashio::var.true "$dry_run"; then
                bashio::log.info "[dry-run] Would check for add-on updates on iteration ${iterations}."
            else
                bashio::log.info "This is the ${iterations}. iteration, time to check for updates."
                bashio::addons.reload
            fi
        fi

        bashio::log.trace "Start addon iteration"
        for slug in $(bashio::jq "$config_content" ".addons // {} | keys | .[]"); do
            local addon_settings
            local addon_options
            local addon_changed="false"
            local addon_installed

            addon_settings=$(bashio::jq "$config_content" ".addons.\"${slug}\"")
            addon_installed=$(bashio::addons.installed "$slug")

            # Declarative removal: `state: absent` uninstalls a managed add-on.
            # Anything else (or no `state` key) is treated as `present`.
            if bashio::var.equals "$(bashio::jq "$addon_settings" ".state // \"present\"")" "absent"; then
                if bashio::var.equals "$slug" "self"; then
                    bashio::log.warning "[${slug}] Refusing to uninstall AddMan itself; ignoring 'state: absent'."
                    continue
                fi
                if bashio::var.true "$addon_installed"; then
                    if bashio::var.true "$dry_run"; then
                        bashio::log.info "[dry-run] [${slug}] state is 'absent'. Would uninstall add-on."
                    else
                        bashio::log.info "[${slug}] state is 'absent'. Uninstalling add-on..."
                        addman::addon.uninstall "$slug"
                    fi
                fi
                continue
            fi

            bashio::log.trace "[${slug}] Check if already installed"
            if bashio::var.false "$addon_installed"; then
                if bashio::var.true "$dry_run"; then
                    bashio::log.info "[dry-run] [${slug}] Would install add-on."
                else
                    bashio::log.info "[${slug}] Installing add-on..."
                    bashio::addon.install "$slug"
                    addon_installed="true"
                fi
            fi

            if bashio::jq.exists "$addon_settings" ".boot"; then
                if bashio::var.true "$dry_run"; then
                    bashio::log.info "[dry-run] [${slug}] Would set boot to $(bashio::jq "$addon_settings" ".boot")."
                else
                    bashio::addon.boot "$slug" "$(bashio::jq "$addon_settings" ".boot")"
                fi
            fi

            if bashio::jq.exists "$addon_settings" ".auto_update"; then
                if bashio::var.true "$dry_run"; then
                    bashio::log.info "[dry-run] [${slug}] Would set auto_update to $(bashio::jq "$addon_settings" ".auto_update")."
                else
                    bashio::addon.auto_update "$slug" "$(bashio::jq "$addon_settings" ".auto_update")"
                fi
            fi

            if bashio::jq.exists "$addon_settings" ".watchdog"; then
                if bashio::var.true "$dry_run"; then
                    bashio::log.info "[dry-run] [${slug}] Would set watchdog to $(bashio::jq "$addon_settings" ".watchdog")."
                else
                    bashio::addon.watchdog "$slug" "$(bashio::jq "$addon_settings" ".watchdog")"
                fi
            fi

            if bashio::jq.exists "$addon_settings" ".ingress_panel"; then
                if bashio::var.true "$dry_run"; then
                    bashio::log.info "[dry-run] [${slug}] Would set ingress_panel to $(bashio::jq "$addon_settings" ".ingress_panel")."
                else
                    addman::addon.ingress_panel "$slug" "$(bashio::jq "$addon_settings" ".ingress_panel")"
                fi
            fi

            if bashio::jq.exists "$addon_settings" ".options"; then
                local current_options
                if bashio::var.true "$dry_run" && bashio::var.false "$addon_installed"; then
                    current_options="{}"
                else
                    current_options=$(bashio::addon.options "$slug")
                fi

                addon_options=$(bashio::jq "$addon_settings" ".options")
                bashio::log.trace "[${slug}] Found options block."

                if addman::addon.validate_options "$addon_options" "$slug"; then
                    for key in $(bashio::jq "$addon_options" "keys | .[]"); do
                        bashio::log.trace "[${slug}] Getting value of $key"
                        local value
                        value=$(bashio::jq "$addon_options" ".\"${key}\"")
                        if ! bashio::var.equals "$(bashio::jq "$current_options" ".\"${key}\"")" "$value"; then
                            addon_changed="true"
                            if bashio::var.true "$dry_run"; then
                                bashio::log.info "[dry-run] [${slug}] Would set option '${key}'."
                            else
                                bashio::log.info "[${slug}] Setting option '${key}'."
                                if addman::var.is_yaml_bool "$value" || [[ "${value[0]}" =~ [\[{] ]]; then
                                    bashio::addon.option "$key" "^$value" "$slug"
                                else
                                    bashio::addon.option "$key" "$value" "$slug"
                                fi
                            fi
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
                    if bashio::var.false "$addon_installed"; then
                        if bashio::var.true "$dry_run"; then
                            bashio::log.info "[dry-run] [${slug}] Would start add-on after install."
                        fi
                    elif ! bashio::var.equals "$(bashio::addon.state "$slug")" "started"; then
                        if bashio::var.true "$dry_run"; then
                            bashio::log.info "[dry-run] [${slug}] Would start add-on."
                        else
                            bashio::log.info "[${slug}] Starting add-on..."
                            bashio::addon.start "$slug"
                        fi
                    elif bashio::var.true "$addon_changed"; then
                        if ! bashio::jq.exists "$addon_settings" ".auto_restart" || \
                             bashio::var.true "$(bashio::jq "$addon_settings" ".auto_restart")"; then
                                if bashio::var.true "$dry_run"; then
                                    bashio::log.info "[dry-run] [${slug}] Options would change. Would restart add-on."
                                else
                                    bashio::log.info "[${slug}] Options changed. Restarting add-on..."
                                    bashio::addon.restart "$slug"
                                fi
                        fi
                    fi
                fi
            fi
        done

        sleep "${sleep}"
    done
}
main "$@"
