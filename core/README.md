# Núcleo de LAR

Código versionado del entorno. Las carpetas de `data/` también se versionan, vacías. La configuración personal y los datos que genere el entorno no.

`./lar.sh init` copia `templates/settings.yaml` y `templates/sites.yaml` solo cuando el destino no existe o está vacío. Lo mismo ocurre con `data/.env`, generado a partir de las variables documentadas en `.env.example`.

`docker-compose.yml` arranca el proxy, Apache, nginx, la máquina PHP, MySQL 5.7, Redis y Mailpit. `./lar.sh shell site1` entra en ese sitio con el usuario `web`. Si el sitio define `node`, esa shell hace `nvm use`. Sin `php` el sitio es HTML estático. `public_path` es la carpeta que sirven Apache y nginx; `path` sigue siendo el proyecto. `alias` añade otros dominios al mismo sitio.
