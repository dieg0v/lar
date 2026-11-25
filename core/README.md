# LAR core

Versioned environment code. The `data/` folders are versioned too, empty. Personal config and data the environment creates are not.

`./lar.sh init` copies `templates/settings.yaml` and `templates/sites.yaml` only when the destination does not exist or is empty. The same applies to `data/.env`, generated from the variables documented in `.env.example`.

`docker-compose.yml` starts the proxy, Apache, nginx, the PHP machine (5.6 through 8.5), MySQL 5.7, MySQL 8, MariaDB 10.11 (`mariadb1011`), MariaDB 11.8 (`mariadb101`), Elasticsearch, MinIO, Redis, and Mailpit. The 11.8 service keeps the name `mariadb101`, so the data folder and the hostname inside Docker stay the same. The PHP machine also has a few extra binaries, an opinionated set for the shell.

`./lar.sh shell site1` enters that site as the `web` user. If the site defines `node`, that shell runs `nvm use`. Without `php` the site is static HTML. `public_path` is the folder Apache and nginx serve; `path` remains the project. `alias` adds other domains to the same site.
