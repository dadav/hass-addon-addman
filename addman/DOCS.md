# Home Assistant Community Add-on: AddMan

AddMan is a simple add-on manager.

AddMan installs, configures and (re)starts add-ons.

## Installation

1. Add the repository to your home-assistant by clicking on this button:

[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fdadav%2Fhass-addon-addman)

2. Navigate to the add-on section.
3. Click on the `AddMan` add-on.
4. Click on install.

## Configuration

There are two configuration locations you have to consider when using
this add-on.

1. The configuration of the add-on itself
(which you can also do with the second option).
2. The configuration of the other add-ons.

**Note**: _Remember to restart the add-on when the configuration is changed._

AddMan add-on configuration:

```yaml
check_interval: 600
config_file: /config/addman.yaml
log_level: info
watch_config_changes: false
```

### Option: `check_interval`

AddMan runs in a loop. During every iteration in this loop, AddMan will
compare the current configuration with the target configuration and make
it right if there is some difference.

This option specifies the time (in seconds) how long AddMan should sleep
between each iteration.

### Option: `config_file`

AddMan needs an additional configuration file. This configuration file
contains the configuration of all the other add-ons you want to manage
with AddMan.

If you don't change this value, a default configuration will be copied 
to your configuration directory (`/config/addman.yaml`).

An example add-on configuration looks like this:

```yaml
---
# AddMan is part of another repository, so we need to add it first
repositories:
  - https://github.com/dadav/hass-addon-addman

addons:
  # The key must be the slug of the add-on you want to manage.
  # It will be installed automatically.
  # In this case we will install addman itself. Therefore "self"...
  self:
    # If you set `start` to true, it will be started automatically.
    start: true
    # Enables the watchdog setting in home assistant.
    watchdog: true
    # Enables the auto-update setting in home assistant.
    auto_update: true
    # Enables the boot setting in home assistant.
    boot: auto
    # Enables the ingress panel on the side bar
    ingress_panel: false
    # This must contain the valid add-on configuration.
    # The content will be validated before it will be applied.
    options:
      check_interval: 600
      config_file: /config/addman.yaml
      log_level: info
      watch_config_changes: true
```

### Option: `log_level`

The `log_level` option controls the level of log output by the add-on and can
be changed to be more or less verbose, which might be useful when you are
dealing with an unknown issue. Possible values are:

- `trace`: Show every detail, like all called internal functions.
- `debug`: Shows detailed debug information.
- `info`: Normal (usually) interesting events.
- `warning`: Exceptional occurrences that are not errors.
- `error`: Runtime errors that do not require immediate action.
- `fatal`: Something went terribly wrong. Add-on becomes unusable.

Please note that each level automatically includes log messages from a
more severe level, e.g., `debug` also shows `info` messages. By default,
the `log_level` is set to `info`, which is the recommended setting unless
you are troubleshooting.

### Option: `watch_config_changes`

If this option is set to true, the configuration file (`config_file`) will
be read before every iteration. This has the benefit, that you can change
the add-ons configuration on-the-fly.
