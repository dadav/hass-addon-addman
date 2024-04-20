<h1 align="center">🔥AddMan</h1>

<p align="center">
  <img src="images/logo.jpg" width="400" />
  <br />
  This repository contains a single add-on for home-assistant: <a href="./addman">AddMan</a>
  <br />
  <a href="./addman">AddMan</a> can be used to configure <a href="https://www.home-assistant.io">Home-Assistant</a>
  via a git repository.
</p>

## ⚡Installation

To add this repository to your home-assistant, just click on this button:

[![Add this repository to your Home Assistant instance.][repo-badge]][repo]

And then install the add-on by pressing on this button:

[![Open this add-on in your Home Assistant instance.][addon-badge]][addon]

and simply click on `install`.

## 🐝About AddMan

With this add-on you can do two things:

1. Install add-ons and repositories.
2. Change the configuration of add-ons.

**And the best thing:**

You can store the config in your configs directory and therefore
use the git-pull add-on to store all the add-on configuration
in a git repository!1!!

### 🎨Configuration

The addons are managed in a file called `addman.yaml` (by default). It contains the config
of all the other configurations. Addman will also look for a file called `addman.yaml.secrets`
which you can use to inject secrets.

Checkout [the examples](./addman/examples/) to get an idea how to configure addman.

[addon-badge]: https://my.home-assistant.io/badges/supervisor_addon.svg
[addon]: https://my.home-assistant.io/redirect/supervisor_addon/?addon=1fa9e8ff_addman&repository_url=https%3A%2F%2Fgithub.com%2Fdadav%2Fhass-addon-addman
[repo-badge]: https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg
[repo]: https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fdadav%2Fhass-addon-addman
