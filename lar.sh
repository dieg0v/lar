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
Usage: ./lar.sh <command>

Commands:
  install              Starts Docker and prepares the configuration. Asks before replacing personal files
  init                 Creates the data directories, the initial configuration, and validates settings.yaml
  up [service]         Starts the enabled services, or only the one given
  down [service]       Stops the environment or one service, without deleting data
  restart [service]    Restarts the enabled services, or only the one given
  status               Shows the containers
  logs [service]       Shows the latest log lines
  shell [site]         Opens zsh in that site's folder, as the web user
  -s [site]            Same as shell
  list                 Shows the sites. Arrows to move, enter opens the chosen one
  update               Looks for PHP, Chrome, and tool patches, and asks before applying them
  help                 Shows this help

Services: proxy, apache, nginx, php, mysql57, mysql8, mariadb1011, mariadb101, elasticsearch, minio, redis, mailpit

./lar.sh up starts the nginx on port 80, Apache, nginx, the PHP machine, MySQL 5.7, MySQL 8, MariaDB 10.11, MariaDB 10.1, Elasticsearch, MinIO, Redis, and Mailpit.
./lar.sh shell site1 opens zsh at site1's path. lar -s site1 is the same. lar list picks the site with the arrows and enter. If the site has php, that version is set. If it has node, it runs nvm use. With no name it opens web's home. sudo su switches to root.
On the Mac, up writes the domains into /etc/hosts and down removes that block. If it changes, macOS asks for the password.
init does not replace settings.yaml, sites.yaml, or data/.env when they already have content.
install asks before replacing them. If you answer no, it keeps them.
On macOS, install checks vmnetd. Without that helper, port 80 cannot be opened.
update asks about PHP, about Chrome, and about the other tools. LibreOffice, Node, and gulp stay on their pinned version.

Planned and not implemented yet:
  backup, restore
EOF
}

not_implemented() {
  printf '%s\n' "Command '$1' is not implemented yet." >&2
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
      printf '%s\n' "install does not accept arguments." >&2
      usage >&2
      exit 2
    fi
    lar_install
    ;;
  init)
    if [ "$#" -ne 0 ]; then
      printf '%s\n' "init does not accept arguments." >&2
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
    printf '%s\n' "Unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
