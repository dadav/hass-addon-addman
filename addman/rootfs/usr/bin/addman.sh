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

# ==============================================================================
# RUN LOGIC
# ------------------------------------------------------------------------------
main() {
    local sleep
    local config_file
    local config_content
    local watch_config_changes

    bashio::log.trace "${FUNCNAME[0]}"

    watch_config_changes=$(bashio::config 'watch_config_changes')
    config_file=$(bashio::config 'config_file')

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
        if bashio::var.true "$watch_config_changes"; then
            bashio::log.trace "Reading config from $config_file ..."
            config_content=$(addman::yaml_to_json "$config_file")
            bashio::log.trace "Got this config: $config_content"
        fi

        bashio::log.trace "Start addon iteration"
        for slug in $(bashio::jq "$config_content" ".addons | keys | .[]"); do
            bashio::log.trace "Check if $slug is installed"
            if bashio::var.false "$(bashio::addons.installed "$slug")"; then
                bashio::log.info "[${slug}] Installing add-on..."
                bashio::addon.install "$slug"
            fi
            # Configure the addon
            local addon_settings
            local addon_options
            local addon_changed

            addon_settings=$(bashio::jq "$config_content" ".addons.${slug}")
            addon_changed="false"

            if bashio::jq.exists "$addon_settings" ".boot"; then
                bashio::addon.boot "$slug" "$(bashio::jq "$addon_settings" ".boot")"
            fi

            if bashio::jq.exists "$addon_settings" ".auto_update"; then
                bashio::addon.auto_update "$slug" "$(bashio::jq "$addon_settings" ".auto_update")"
            fi

            if bashio::jq.exists "$addon_settings" ".watchdog"; then
                bashio::addon.watchdog "$slug" "$(bashio::jq "$addon_settings" ".watchdog")"
            fi

            # TODO: Add option to set Ingress-Panel

            if bashio::jq.exists "$addon_settings" ".options"; then
                local current_options
                current_options=$(bashio::addon.options "$slug")

                addon_options=$(bashio::jq "$addon_settings" ".options")
                bashio::log.trace "Found these options $addon_options"

                if addman::addon.validate_options "$addon_options" "$slug"; then
                    for key in $(bashio::jq "$addon_options" "keys | .[]"); do
                        bashio::log.trace "Getting value of $key"
                        for value in $(bashio::jq "$addon_options" ".${key}"); do
                            if ! bashio::var.equals "$(bashio::jq "$current_options" ".${key}")" "$value"; then
                                bashio::log.info "[${slug}] Setting $key to $value"
                                bashio::addon.option "$key" "^$value" "$slug"
                                addon_changed="true"
                            fi
                        done
                    done
                else
                    bashio::log.error "Invalid options detected (add-on: ${slug}). Skip."
                    continue
                fi
            fi

            if bashio::jq.exists "$addon_settings" ".start"; then
                if bashio::var.true "$(bashio::jq "$addon_settings" ".start")"; then
                    if ! bashio::var.equals "$(bashio::addon.state "$slug")" "started"; then
                        bashio::log.info "[${slug}] Starting add-on..."
                        bashio::addon.start "$slug"
                    elif bashio::var.true "$addon_changed"; then
                        bashio::log.info "[${slug}] Options changed. Restarting add-on..."
                        bashio::addon.restart "$slug"
                    fi
                fi
            fi
        done

        sleep "${sleep}"
    done
}
main "$@"
