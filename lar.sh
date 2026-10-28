#!/bin/sh
set -eu

lar_invoke_path() {
  case "$0" in
    */*)
      printf '%s\n' "$0"
      ;;
    *)
      command -v "$0"
      ;;
  esac
}

lar_real_dir() {
  current=$1
  while [ -L "$current" ]; do
    target=$(readlink "$current")
    case "$target" in
      /*) current=$target ;;
      *) current=$(dirname "$current")/$target ;;
    esac
  done
  CDPATH= cd -- "$(dirname "$current")" && pwd
}

ROOT=$(lar_real_dir "$(lar_invoke_path)")
LAR_ROOT=$ROOT
# shellcheck source=core/scripts/config.sh
. "$ROOT/core/scripts/config.sh"
# shellcheck source=core/scripts/bootstrap.sh
. "$ROOT/core/scripts/bootstrap.sh"
# shellcheck source=core/scripts/sites.sh
. "$ROOT/core/scripts/sites.sh"
# shellcheck source=core/scripts/services.sh
. "$ROOT/core/scripts/services.sh"
# shellcheck source=core/scripts/install.sh
. "$ROOT/core/scripts/install.sh"
# shellcheck source=core/scripts/update.sh
. "$ROOT/core/scripts/update.sh"

usage() {
  cat <<'EOF'
Uso: ./lar.sh <comando>

Comandos:
  install              Arranca Docker y prepara la configuración. Pregunta antes de sustituir los archivos personales
  init                 Crea los directorios de datos, la configuración inicial y valida settings.yaml
  up [servicio]        Arranca los servicios habilitados, o solo el indicado
  down [servicio]      Detiene el entorno o un servicio, sin borrar datos
  restart [servicio]   Reinicia los servicios habilitados, o solo el indicado
  status               Muestra los contenedores
  logs [servicio]      Muestra las últimas líneas de log
  shell [sitio]        Abre zsh en la carpeta de ese sitio, con el usuario web
  -s [sitio]           Igual que shell
  list                 Muestra los sitios. Flechas para moverse, enter abre el elegido
  update               Busca parches de PHP, Chrome y las herramientas, y pregunta antes de subirlos
  help                 Muestra esta ayuda

Servicios: proxy, apache, nginx, php, mysql57, mysql8, mariadb1011, mariadb101, elasticsearch, minio, redis, mailpit

./lar.sh up arranca el nginx del puerto 80, Apache, nginx, la máquina PHP, MySQL 5.7, MySQL 8, MariaDB 10.11, MariaDB 10.1, Elasticsearch, MinIO, Redis y Mailpit.
./lar.sh shell site1 abre zsh en el path de site1. lar -s site1 es lo mismo. lar list elige el sitio con las flechas y enter. Si el sitio tiene php, deja esa versión. Si tiene node, hace nvm use. Sin nombre abre el home de web. sudo su pasa a root.
En el Mac, up escribe los dominios en /etc/hosts y down quita ese bloque. Si cambia, macOS pide la contraseña.
init no sustituye settings.yaml, sites.yaml ni data/.env si ya tienen contenido.
install pregunta antes de sustituirlos. Si respondes que no, los conserva.
En macOS, install comprueba vmnetd. Sin ese ayudante no se puede abrir el puerto 80.
update pregunta por PHP, por Chrome y por el resto de herramientas. LibreOffice, Node y gulp se quedan en su versión fijada.

Previstos y todavía no implementados:
  backup, restore
EOF
}

not_implemented() {
  printf '%s\n' "El comando '$1' todavía no está implementado." >&2
  exit 1
}

if [ "${1:-}" = "-s" ]; then
  shift
  lar_shell "$@"
fi

cmd=${1:-help}
if [ "$#" -gt 0 ]; then
  shift
fi

case "$cmd" in
  help|-h|--help)
    usage
    ;;
  install)
    if [ "$#" -ne 0 ]; then
      printf '%s\n' "install no admite argumentos." >&2
      usage >&2
      exit 2
    fi
    lar_install
    ;;
  init)
    if [ "$#" -ne 0 ]; then
      printf '%s\n' "init no admite argumentos." >&2
      usage >&2
      exit 2
    fi
    lar_init "$ROOT"
    ;;
  up)
    lar_up "$@"
    ;;
  down)
    lar_down "$@"
    ;;
  restart)
    lar_restart "$@"
    ;;
  status)
    lar_status "$@"
    ;;
  logs)
    lar_logs "$@"
    ;;
  shell)
    lar_shell "$@"
    ;;
  list)
    lar_list "$@"
    ;;
  update)
    lar_update "$@"
    ;;
  backup|restore)
    not_implemented "$cmd"
    ;;
  *)
    printf '%s\n' "Comando desconocido: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
