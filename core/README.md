# LAR core

Versioned environment code. The `data/` folders are versioned too, empty. Personal config and data the environment creates are not.

`./lar.sh init` copies `templates/settings.yaml` and `templates/sites.yaml` only when the destination does not exist or is empty. The same applies to `data/.env`, generated from the variables documented in `.env.example`.

`docker-compose.yml` starts the proxy, Apache, nginx, the PHP machine, MySQL 5.7, Redis, and Mailpit. `./lar.sh shell site1` enters that site as the `web` user. If the site defines `node`, that shell runs `nvm use`. Without `php` the site is static HTML. `public_path` is the folder Apache and nginx serve; `path` remains the project. `alias` adds other domains to the same site.
