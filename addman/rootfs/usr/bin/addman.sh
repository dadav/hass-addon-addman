#!/command/with-contenv bashio
# ==============================================================================
# Home Assistant Community Add-on: AddMan
#
# An add-on to configure them all.
# This add-on can install and configure other add-ons.
# ==============================================================================

# update config


# ------------------------------------------------------------------------------
# Send a post request to the given url.
#
# Arguments:
#   - URL
#   - Data (optional)
# Returns:
#   Json result
# ------------------------------------------------------------------------------
http_post() {
    bashio::log.trace "${FUNCNAME[0]}"

    curl -sSL \ -X POST \
         -d "${2}" \
         -H "Content-Type: application/json" \
         -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
         "$1"
}

# ------------------------------------------------------------------------------
# Make a get request to the give url.
#
# Arguments:
#   URL
# Returns:
#   Json result
# ------------------------------------------------------------------------------
http_get() {
    bashio::log.trace "${FUNCNAME[0]}"

    curl -sSL \
         -H "Content-Type: application/json" \
         -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
         "$1"
}

# ------------------------------------------------------------------------------
# Configure the given add-on
#
# Arguments:
#   Add-on slug
#   Config data
# Returns:
#   Json result
# ------------------------------------------------------------------------------
addon_set_config() {
    bashio::log.trace "${FUNCNAME[0]}"

    http_post http://supervisor/addons/"$1"/options "$2"
}

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
# Execute a YAML query.
#
# Arguments:
#   $1 YAML string or path to a YAML file
#   $2 yq filter (optional)
# ------------------------------------------------------------------------------
function addman::yq() {
    local data=${1}
    local filter=${2:-}

    bashio::log.trace "${FUNCNAME[0]}:" "$@"

    if [[ -f "${data}" ]]; then
        yq -M -N "$filter" "${data}"
    else
        yq -M -N "$filter" <<< "${data}"
    fi
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
        return "${__BASHIO_EXIT_NOK}"
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
            if ! bashio::addons.installed "$slug"; then
                bashio::log.trace "It's not, install!"
                bashio::addon.install "$slug"
            fi
            # Configure the addon
            local addon_settings
            local addon_options

            addon_settings=$(bashio::jq "$config_content" ".addons | to_entries[] | select(.key == \"${slug}\").value")

            if bashio::jq.exists "$addon_settings" ".boot"; then
                bashio::addon.boot "$slug" "$(bashio::jq "$addon_settings" ".boot")"
            fi

            if bashio::jq.exists "$addon_settings" ".auto_update"; then
                bashio::addon.auto_update "$slug" "$(bashio::jq "$addon_settings" ".auto_update")"
            fi

            if bashio::jq.exists "$addon_settings" ".watchdog"; then
                bashio::addon.watchdog "$slug" "$(bashio::jq "$addon_settings" ".watchdog")"
            fi


            if bashio::jq.exists "$addon_settings" ".options"; then
                local current_options
                current_options=$(bashio::addon.options "$slug")

                addon_options=$(bashio::jq "$addon_settings" ".options")
                bashio::log.trace "Found these options $addon_options"

                for key in $(bashio::jq "$addon_options" "keys | .[]"); do
                    bashio::log.trace "Getting value of $key"
                    for value in $(bashio::jq "$addon_options" "to_entries[] | select(.key == \"${key}\").value"); do
                        if ! bashio::var.equals "$(bashio::jq "$current_options" "$key")" "$value"; then
                            bashio::log.trace "Setting $key to $value"
                            bashio::addon.option "$key" "$value" "$slug"
                        fi
                    done
                done
            fi

            if bashio::jq.exists "$addon_settings" ".start"; then
                if bashio::var.true "$(bashio::jq "$addon_settings" ".start")"; then
                    if ! bashio::var.equals "$(bashio::addon.state "$slug")" "started"; then
                        bashio::addon.start "$slug"
                    fi
                fi
            fi
        done

        sleep "${sleep}"
    done
}
main "$@"
