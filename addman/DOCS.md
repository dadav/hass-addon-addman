# Home Assistant Community Add-on: AddMan

AddMan is a simple add-on manager.

Add-ons will be installed, configured and (re)started.

The main goal is to provide a simple way to manage add-ons via files
managed by git.

## Installation

1. Add the repository to your home-assistant by clicking on this button:

[![Add this repository to your Home Assistant instance.][repo-badge]][repo]

1. Now open the add-on page by clicking on this button:

[![Open this add-on in your Home Assistant instance.][addon-badge]][addon]

1. Click the "Install" button to install the add-on.
1. Start the "AddMan" add-on.

## Configuration

There are two configuration locations you have to consider when using
this add-on.

1. The configuration of the add-on itself
(which you can also do with the second option). You usually change this
configuration by clicking on the documentation tab.
2. The configuration of the other add-ons, which reside (by default) in the
`/config/addman.yaml` file.

**Note**: _Remember to restart the add-on when the configuration is changed._

The AddMan add-on default configuration looks like this:

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
    # If you set `auto_start` to true, it will be started automatically.
    auto_start: true
    # If you set `auto_restart` to true, it will be restarted automatically.
    # when the configuration changed
    auto_restart: true
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

## Changelog

This repository keeps a change log using [the conventions of keepachangelog.com][changelog].

Releases are based on [Semantic Versioning][semver], and use the format
of `MAJOR.MINOR.PATCH`. In a nutshell, the version will be incremented
based on the following:

- `MAJOR`: Incompatible or major changes.
- `MINOR`: Backwards-compatible new features and enhancements.
- `PATCH`: Backwards-compatible bugfixes and package updates.

## Support

Got questions? Have an idea?

Feel free to [open an issue here][issue] GitHub.

## Authors & contributors

The structure of this project is based on an example add-on from [Franck Nijhof][frenck].

## License

MIT License

Copyright (c) 2019-2022 dadav

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

[addon-badge]: https://my.home-assistant.io/badges/supervisor_addon.svg
[addon]: https://my.home-assistant.io/redirect/supervisor_addon/?addon=1fa9e8ff_addman&repository_url=https%3A%2F%2Fgithub.com%2Fdadav%2Fhass-addon-addman
[changelog]: https://keepachangelog.com/en/1.0.0/
[issue]: https://github.com/dadav/hass-addon-addman/issues
[repo-badge]: https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg
[repo]: https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fdadav%2Fhass-addon-addman
[semver]: http://semver.org/spec/v2.0.0
