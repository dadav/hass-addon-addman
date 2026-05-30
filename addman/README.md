# Home Assistant Add-on: AddMan

![Supports aarch64 Architecture][aarch64-shield]
![Supports amd64 Architecture][amd64-shield]
![Supports armhf Architecture][armhf-shield]
![Supports armv7 Architecture][armv7-shield]
![Supports i386 Architecture][i386-shield]

[aarch64-shield]: https://img.shields.io/badge/aarch64-yes-green.svg
[amd64-shield]: https://img.shields.io/badge/amd64-yes-green.svg
[armhf-shield]: https://img.shields.io/badge/armhf-yes-green.svg
[armv7-shield]: https://img.shields.io/badge/armv7-yes-green.svg
[i386-shield]: https://img.shields.io/badge/i386-yes-green.svg

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
