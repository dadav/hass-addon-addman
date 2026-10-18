#!/command/with-contenv bashio
# ==============================================================================
# Home Assistant Community Add-on: AddMan
#
# An add-on to configure them all.
# This add-on can install and configure other add-ons.
#
# Error handling invariant: bashio enables errexit, so any unchecked failing
# Supervisor call would kill this script and halt the add-on. Every Supervisor
# call in the reconcile loop is therefore wrapped in `if !` and failures are
# recorded via addman::errors.record. At the end of each iteration
# addman::errors.notify_changes notifies the user about new errors and
# recovered ones (see /usr/bin/addman-notify).
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
# Records an error for the current iteration and logs it.
#
# Arguments:
#   $1 Name of the associative array holding this iteration's errors
#   $2 Error key (e.g. addon:tailscale). One entry per key per iteration.
#   $3 Human readable error message (sent as notification). Must be stable
#      across iterations so unchanged errors are not re-notified.
# ------------------------------------------------------------------------------
function addman::errors.record() {
    local -n errors_ref=${1}
    local key=${2}
    local message=${3}

    bashio::log.error "[${key}] ${message}"
    errors_ref["${key}"]=${message}
}

# ------------------------------------------------------------------------------
# Notifies about errors that are new or changed since the last iteration and
# about errors that disappeared (recovered). Then makes the current errors the
# active ones.
#
# Arguments:
#   $1 Name of the associative array with errors notified so far (updated)
#   $2 Name of the associative array with this iteration's errors
#   $3 dry_run flag
# ------------------------------------------------------------------------------
function addman::errors.notify_changes() {
    local -n active_ref=${1}
    local -n current_ref=${2}
    local dry_run=${3}
    local title_prefix="AddMan"
    local key

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    if bashio::var.true "$dry_run"; then
        title_prefix="[dry-run] AddMan"
    fi

    for key in "${!current_ref[@]}"; do
        if [[ "${active_ref[${key}]:-}" != "${current_ref[${key}]}" ]]; then
            addman-notify error "${key}" "${title_prefix}: error" \
                "${current_ref[${key}]}"$'\n\n'"Check the AddMan log for details." || true
        fi
    done

    for key in "${!active_ref[@]}"; do
        if [[ -z "${current_ref[${key}]+set}" ]]; then
            addman-notify resolve "${key}" "${title_prefix}: resolved" \
                "Resolved: ${active_ref[${key}]}" || true
        fi
    done

    active_ref=()
    for key in "${!current_ref[@]}"; do
        active_ref["${key}"]=${current_ref[${key}]}
    done
}

# ------------------------------------------------------------------------------
# Check if the given options are valid
#
# Arguments:
#   $1 Addon options as String
#   $2 Add-on slug
# Prints:
#   On failure, the reason (Supervisor validation message)
# ------------------------------------------------------------------------------
function addman::addon.validate_options() {
    local data=${1}
    local slug=${2:-self}
    local response
    local message

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    if ! response=$(bashio::api.supervisor POST "/addons/${slug}/options/validate" "$data"); then
        printf '%s' "the Supervisor API call to validate the options failed."
        return "${__BASHIO_EXIT_NOK}"
    fi

    if bashio::var.false "$(bashio::jq "${response}" ".valid")"; then
        message=$(bashio::jq "${response}" ".message // \"unknown error\"")
        bashio::log.trace "response: ${response}"
        bashio::log.info "[${slug}] Invalid options: ${message}"
        printf '%s' "${message}"
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

    if ! response=$(bashio::api.supervisor GET "/store/repositories" false); then
        return "${__BASHIO_EXIT_NOK}"
    fi
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

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    if bashio::var.has_value "${repo}"; then
        repo=$(bashio::var.json repository "${repo}")
        bashio::api.supervisor POST "/store/repositories" "${repo}" || return "${__BASHIO_EXIT_NOK}"
    else
        return "${__BASHIO_EXIT_NOK}"
    fi

    return "${__BASHIO_EXIT_OK}"
}

# ------------------------------------------------------------------------------
# Reload add-ons and store. Unlike bashio::addons.reload, this returns
# non-zero when the Supervisor call fails.
# ------------------------------------------------------------------------------
function addman::addons.reload() {
    bashio::log.trace "${FUNCNAME[0]}"

    bashio::api.supervisor POST /addons/reload || return "${__BASHIO_EXIT_NOK}"
    bashio::cache.flush_all

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

    bashio::api.supervisor POST "/addons/${slug}/uninstall" || return "${__BASHIO_EXIT_NOK}"
    bashio::cache.flush_all

    return "${__BASHIO_EXIT_OK}"
}

# ------------------------------------------------------------------------------
# Sets a top-level add-on setting (boot, watchdog, auto_update,
# ingress_panel) via POST /addons/{slug}/options. Unlike the bashio setters,
# this returns non-zero when the Supervisor call fails.
#
# Arguments:
#   $1 Add-on slug
#   $2 Setting key
#   $3 Setting value as JSON (e.g. "auto" or true)
# ------------------------------------------------------------------------------
function addman::addon.set_setting() {
    local slug=${1}
    local key=${2}
    local value=${3}
    local payload

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    if ! payload=$(jq -n -c --arg key "${key}" --argjson value "${value}" '{($key): $value}'); then
        return "${__BASHIO_EXIT_NOK}"
    fi

    bashio::api.supervisor POST "/addons/${slug}/options" "${payload}" || return "${__BASHIO_EXIT_NOK}"
    bashio::cache.flush_all

    return "${__BASHIO_EXIT_OK}"
}

# ------------------------------------------------------------------------------
# Sets a single add-on option, keeping all other current options.
# Same value semantics as bashio::addon.option (a "^" prefix marks a raw JSON
# value, anything else is a string), but returns non-zero on failure.
#
# Arguments:
#   $1 Option key
#   $2 Option value
#   $3 Add-on slug
# ------------------------------------------------------------------------------
function addman::addon.set_option() {
    local key=${1}
    local value=${2}
    local slug=${3}
    local options
    local payload

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    if ! options=$(bashio::addon.options "${slug}"); then
        return "${__BASHIO_EXIT_NOK}"
    fi
    if bashio::var.is_empty "${options}"; then
        options="{}"
    fi

    if [[ "${value:0:1}" == "^" ]]; then
        if ! options=$(jq -c --arg key "${key}" --argjson value "${value:1}" '.[$key] = $value' <<< "${options}"); then
            return "${__BASHIO_EXIT_NOK}"
        fi
    else
        if ! options=$(jq -c --arg key "${key}" --arg value "${value}" '.[$key] = $value' <<< "${options}"); then
            return "${__BASHIO_EXIT_NOK}"
        fi
    fi

    payload=$(jq -n -c --argjson options "${options}" '{options: $options}')
    bashio::api.supervisor POST "/addons/${slug}/options" "${payload}" || return "${__BASHIO_EXIT_NOK}"
    bashio::cache.flush_all

    return "${__BASHIO_EXIT_OK}"
}

# ==============================================================================
# RUN LOGIC
# ------------------------------------------------------------------------------
main() {
    local sleep
    local check_updates_x_iterations
    local config_file
    local config_content
    local new_config_content
    local dry_run
    local watch_config_changes
    local iterations=0
    # Errors already notified (key -> message). In-memory only.
    local -A active_errors=()
    # Errors found during the current iteration (key -> message).
    local -A iteration_errors=()

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
            bashio::log.fatal "Config file ${config_file} does not exist."
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
    if ! config_content=$(addman::yaml_to_json "$config_file"); then
        bashio::log.fatal "Failed to parse config file ${config_file}."
        return "${__BASHIO_EXIT_NOK}"
    fi
    bashio::log.trace "Loaded config from $config_file."

    sleep=$(bashio::config 'check_interval')
    bashio::log.info "Seconds between checks is set to: ${sleep}"

    while true; do
        iterations=$(( iterations+1 ))
        iteration_errors=()

        if bashio::var.true "$watch_config_changes"; then
            bashio::log.trace "Reading config from $config_file ..."
            if new_config_content=$(addman::yaml_to_json "$config_file"); then
                config_content=${new_config_content}
                bashio::log.trace "Loaded config from $config_file."
            else
                addman::errors.record iteration_errors "config" \
                    "Failed to parse config file '${config_file}'. Using the last valid config."
            fi
        fi
        bashio::log.trace "Start repositories iteration"

        local current_repositories
        local repository_changed="false"

        if current_repositories=$(addman::addons.fetch_repositories); then
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
                    if ! addman::addons.add_repository "$repo"; then
                        addman::errors.record iteration_errors "repository:${repo}" \
                            "Failed to add add-on repository '${repo}'."
                        continue
                    fi
                fi
                repository_changed="true"
            done
        else
            addman::errors.record iteration_errors "repositories" \
                "Failed to fetch add-on repositories from the Supervisor."
        fi

        if bashio::var.true "$repository_changed"; then
            if bashio::var.true "$dry_run"; then
                bashio::log.info "[dry-run] Would refresh add-ons after repository changes."
            else
                bashio::log.info "Repositories have changed. Refreshing add-ons."
                if ! addman::addons.reload; then
                    addman::errors.record iteration_errors "reload" \
                        "Failed to refresh add-ons from the Supervisor."
                fi
            fi
        elif [[ $check_updates_x_iterations -gt 0 && $(( iterations % check_updates_x_iterations)) -eq 0 ]]; then
            if bashio::var.true "$dry_run"; then
                bashio::log.info "[dry-run] Would check for add-on updates on iteration ${iterations}."
            else
                bashio::log.info "This is the ${iterations}. iteration, time to check for updates."
                if ! addman::addons.reload; then
                    addman::errors.record iteration_errors "reload" \
                        "Failed to refresh add-ons from the Supervisor."
                fi
            fi
        fi

        bashio::log.trace "Start addon iteration"
        for slug in $(bashio::jq "$config_content" ".addons // {} | keys | .[]"); do
            local addon_settings
            local addon_options
            local addon_changed="false"
            local addon_installed
            local addon_state
            local error_key="addon:${slug}"

            addon_settings=$(bashio::jq "$config_content" ".addons.\"${slug}\"")
            if ! addon_installed=$(bashio::addons.installed "$slug"); then
                addman::errors.record iteration_errors "${error_key}" \
                    "Failed to query add-on '${slug}' from the Supervisor. Check the slug and that its repository is added."
                continue
            fi

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
                        if ! addman::addon.uninstall "$slug"; then
                            addman::errors.record iteration_errors "${error_key}" \
                                "Failed to uninstall add-on '${slug}'."
                        fi
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
                    if ! bashio::addon.install "$slug"; then
                        addman::errors.record iteration_errors "${error_key}" \
                            "Failed to install add-on '${slug}'."
                        continue
                    fi
                    bashio::cache.flush_all
                    addon_installed="true"
                fi
            fi

            for setting in boot auto_update watchdog ingress_panel; do
                if ! bashio::jq.exists "$addon_settings" ".${setting}"; then
                    continue
                fi
                if bashio::var.true "$dry_run"; then
                    bashio::log.info "[dry-run] [${slug}] Would set ${setting} to $(bashio::jq "$addon_settings" ".${setting}")."
                elif ! addman::addon.set_setting "$slug" "$setting" "$(bashio::jq "$addon_settings" ".${setting} | tojson")"; then
                    addman::errors.record iteration_errors "${error_key}" \
                        "Failed to set ${setting} for add-on '${slug}'."
                    continue 2
                fi
            done

            if bashio::jq.exists "$addon_settings" ".options"; then
                local current_options
                local validation_message
                if bashio::var.true "$dry_run" && bashio::var.false "$addon_installed"; then
                    current_options="{}"
                elif ! current_options=$(bashio::addon.options "$slug"); then
                    addman::errors.record iteration_errors "${error_key}" \
                        "Failed to read current options of add-on '${slug}'."
                    continue
                fi

                addon_options=$(bashio::jq "$addon_settings" ".options")
                bashio::log.trace "[${slug}] Found options block."

                if ! validation_message=$(addman::addon.validate_options "$addon_options" "$slug"); then
                    bashio::log.error "[${slug}] Invalid options detected. Skip."
                    addman::errors.record iteration_errors "${error_key}" \
                        "Invalid options for add-on '${slug}': ${validation_message}"
                    continue
                fi

                for key in $(bashio::jq "$addon_options" "keys | .[]"); do
                    bashio::log.trace "[${slug}] Getting value of $key"
                    local value
                    value=$(bashio::jq "$addon_options" ".\"${key}\"")
                    if bashio::var.equals "$(bashio::jq "$current_options" ".\"${key}\"")" "$value"; then
                        continue
                    fi
                    addon_changed="true"
                    if bashio::var.true "$dry_run"; then
                        bashio::log.info "[dry-run] [${slug}] Would set option '${key}'."
                        continue
                    fi
                    bashio::log.info "[${slug}] Setting option '${key}'."
                    # Lists/objects are detected by their real JSON type, so
                    # strings containing [ or { (passwords, regexes) stay
                    # strings. is_yaml_bool keeps the legacy bool/number
                    # coercion.
                    local value_type
                    value_type=$(bashio::jq "$addon_options" ".\"${key}\" | type")
                    if addman::var.is_yaml_bool "$value" \
                        || bashio::var.equals "$value_type" "array" \
                        || bashio::var.equals "$value_type" "object"; then
                        value="^${value}"
                    fi
                    if ! addman::addon.set_option "$key" "$value" "$slug"; then
                        addman::errors.record iteration_errors "${error_key}" \
                            "Failed to set option '${key}' for add-on '${slug}'."
                        continue 2
                    fi
                done
            fi

            if bashio::jq.exists "$addon_settings" ".start"; then
                bashio::log.warning "[${slug}] start is now called auto_start and will be removed in the future."
                addon_settings=$(bashio::jq "$addon_settings" ".auto_start = .start")
            fi

            if ! bashio::jq.exists "$addon_settings" ".auto_start" \
                || ! bashio::var.true "$(bashio::jq "$addon_settings" ".auto_start")"; then
                continue
            fi

            if bashio::var.false "$addon_installed"; then
                if bashio::var.true "$dry_run"; then
                    bashio::log.info "[dry-run] [${slug}] Would start add-on after install."
                fi
                continue
            fi

            if ! addon_state=$(bashio::addon.state "$slug"); then
                addman::errors.record iteration_errors "${error_key}" \
                    "Failed to read the state of add-on '${slug}'."
                continue
            fi

            if ! bashio::var.equals "$addon_state" "started"; then
                if bashio::var.true "$dry_run"; then
                    bashio::log.info "[dry-run] [${slug}] Would start add-on."
                else
                    bashio::log.info "[${slug}] Starting add-on..."
                    if ! bashio::addon.start "$slug"; then
                        addman::errors.record iteration_errors "${error_key}" \
                            "Failed to start add-on '${slug}'."
                        continue
                    fi
                fi
            elif bashio::var.true "$addon_changed"; then
                if ! bashio::jq.exists "$addon_settings" ".auto_restart" || \
                     bashio::var.true "$(bashio::jq "$addon_settings" ".auto_restart")"; then
                    if bashio::var.true "$dry_run"; then
                        bashio::log.info "[dry-run] [${slug}] Options would change. Would restart add-on."
                    else
                        bashio::log.info "[${slug}] Options changed. Restarting add-on..."
                        if ! bashio::addon.restart "$slug"; then
                            addman::errors.record iteration_errors "${error_key}" \
                                "Failed to restart add-on '${slug}'."
                            continue
                        fi
                    fi
                fi
            fi
        done

        addman::errors.notify_changes active_errors iteration_errors "$dry_run"

        sleep "${sleep}"
    done
}
main "$@"
