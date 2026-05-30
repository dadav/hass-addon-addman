# Home Assistant Add-on: AddMan

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg

**Add-ons as code for Home Assistant.**

AddMan continuously reconciles your add-ons against a declarative YAML file:
it installs add-ons and their repositories, configures them (options, `boot`,
`watchdog`, `auto_update`, `ingress_panel`, start/restart), and uninstalls the
ones you mark `state: absent`. Every option is validated against the add-on's
own schema before it is applied.

Keep that YAML file in git (for example via the `git-pull` add-on) and your
whole add-on setup becomes version-controlled, reproducible infrastructure.

See the **Documentation** tab for configuration, secrets, examples and
troubleshooting.
