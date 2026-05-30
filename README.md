<h1 align="center">🔥 AddMan</h1>

<p align="center">
  <img src="images/logo.jpg" width="400" />
</p>

<p align="center">
  <b>Add-ons as code for Home Assistant.</b><br />
  Declare which add-ons should be installed, how they are configured, and which
  ones should be removed - all in a single YAML file you can keep in git.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/aarch64-yes-green.svg" alt="aarch64" />
  <img src="https://img.shields.io/badge/amd64-yes-green.svg" alt="amd64" />
</p>

## The problem

Home Assistant add-ons are configured by hand in the UI. That works for one
add-on, but it doesn't scale:

- Rebuilding or migrating a Home Assistant instance means re-installing and
  re-configuring every add-on by hand, from memory.
- There is no version history of your add-on configuration - no diff, no
  rollback, no review.
- Keeping several Home Assistant instances consistent is a manual chore.

## What AddMan does

AddMan is a small add-on that continuously reconciles your add-ons against a
declarative `addman.yaml` file:

- **Installs** add-ons and the repositories they come from.
- **Configures** them: options, `boot`, `watchdog`, `auto_update`,
  `ingress_panel`, start/restart behaviour.
- **Removes** add-ons you mark with `state: absent`.
- **Validates** every option against the add-on's own schema _before_ applying,
  so a typo can't break an add-on.

Point AddMan's config directory at a git repo (e.g. with the
[git-pull](https://github.com/home-assistant/addons/tree/master/git_pull)
add-on) and your entire add-on setup becomes version-controlled,
reproducible infrastructure-as-code.

```
addman.yaml  ->  AddMan reconcile loop  ->   Home Assistant Supervisor API
(desired state)   (every check_interval)      (install / configure / remove)
```

## Quick start

1. Add this repository to Home Assistant:

   [![Add repository to your Home Assistant instance.][repo-badge]][repo]

2. Install the add-on:

   [![Open this add-on in your Home Assistant instance.][addon-badge]][addon]

3. Start AddMan. On first start it writes a default `/config/addman.yaml` you can
   edit. A minimal example:

   ```yaml
   repositories:
     - https://github.com/sabeechen/hassio-google-drive-backup

   addons:
     # The key is the add-on slug.
     core_samba:
       auto_start: true
     cebe7a76_hassio_google_drive_backup:
       auto_start: true
       options:
         days_between_backups: 3
     # No longer want an add-on? Declare it absent and AddMan uninstalls it.
     core_ssh:
       state: absent
   ```

See [the add-on documentation](./addman/DOCS.md) for every option, secrets
support, and troubleshooting.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](./CONTRIBUTING.md).

[addon-badge]: https://my.home-assistant.io/badges/supervisor_addon.svg
[addon]: https://my.home-assistant.io/redirect/supervisor_addon/?addon=1fa9e8ff_addman&repository_url=https%3A%2F%2Fgithub.com%2Fdadav%2Fhass-addon-addman
[repo-badge]: https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg
[repo]: https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fdadav%2Fhass-addon-addman
