#!/bin/sh
# Arranque de Docker y uso compartido de data/. Se incluye desde lar.sh.

if [ "${0##*/}" = "install.sh" ]; then
  printf '%s\n' "Este archivo se carga desde ./lar.sh" >&2
  exit 1
fi

lar_ask_yes() {
  prompt=$1
  if [ ! -r /dev/tty ]; then
    return 1
  fi
  printf '%s [s/N] ' "$prompt" >/dev/tty
  read -r answer </dev/tty || return 1
  case "$answer" in
    s|S|si|SI|sí|Sí|y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

lar_docker_ready() {
  docker info >/dev/null 2>&1 &
  pid=$!
  elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    elapsed=$((elapsed + 1))
    if [ "$elapsed" -ge 4 ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 1
  done
  wait "$pid" || return 1
  return 0
}

lar_wait_docker() {
  tries=0
  printf '%s' "  Esperando a Docker"
  while [ "$tries" -lt 40 ]; do
    if lar_docker_ready; then
      printf '\n'
      return 0
    fi
    printf '.'
    tries=$((tries + 1))
  done
  printf '\n'
  return 1
}

lar_start_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    lar_fail "No se encuentra docker. Instala Docker Engine o Docker Desktop."
  fi
  if ! docker compose version >/dev/null 2>&1; then
    lar_fail "No se encuentra Docker Compose v2. Hace falta el comando: docker compose"
  fi
  if docker info >/dev/null 2>&1; then
    printf '%s\n' "  Docker ya está en marcha"
    return 0
  fi
  case "$(uname -s)" in
    Darwin)
      printf '%s\n' "  Abriendo Docker Desktop"
      open -a Docker
      ;;
    *)
      lar_fail "Docker no está en marcha. Arranca el servicio y vuelve a ejecutar ./lar.sh install."
      ;;
  esac
  if ! lar_wait_docker; then
    lar_fail "Docker no respondió. Ábrelo a mano y vuelve a ejecutar ./lar.sh install."
  fi
  printf '%s\n' "  Docker y Compose v2: disponibles"
}

lar_docker_settings() {
  printf '%s\n' "$HOME/Library/Group Containers/group.com.docker/settings.json"
}

lar_share_data_status() {
  settings=$1
  path=$2
  python3 - "$settings" "$path" <<'PY'
import json, os, sys
settings, path = sys.argv[1], sys.argv[2]
with open(settings, encoding="utf-8") as handle:
    data = json.load(handle)
dirs = data.get("filesharingDirectories") or []
target = os.path.realpath(path).rstrip("/")
for entry in dirs:
    shared = os.path.realpath(entry).rstrip("/")
    if target == shared or target.startswith(shared + os.sep):
        print("already")
        raise SystemExit(0)
print("missing")
PY
}

lar_share_data_add() {
  settings=$1
  path=$2
  python3 - "$settings" "$path" <<'PY'
import json, os, sys
settings, path = sys.argv[1], sys.argv[2]
with open(settings, encoding="utf-8") as handle:
    data = json.load(handle)
dirs = list(data.get("filesharingDirectories") or [])
target = os.path.realpath(path).rstrip("/")
for entry in dirs:
    shared = os.path.realpath(entry).rstrip("/")
    if target == shared or target.startswith(shared + os.sep):
        print("already")
        raise SystemExit(0)
dirs.append(target)
data["filesharingDirectories"] = dirs
temporary = settings + ".lar-tmp"
with open(temporary, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
os.replace(temporary, settings)
PY
}

lar_share_realpath() {
  rel=$1
  mkdir -p "$LAR_ROOT/$rel"
  (CDPATH= cd -- "$LAR_ROOT/$rel" && pwd -P)
}

lar_share_targets() {
  lar_share_realpath data
  lar_sites_configured_paths | while IFS= read -r path; do
    if [ -z "$path" ]; then
      continue
    fi
    if [ -d "$path" ]; then
      (CDPATH= cd -- "$path" && pwd -P)
    else
      printf '%s\n' "$path"
    fi
  done
}

lar_require_shared() {
  case "$(uname -s)" in
    Darwin)
      ;;
    *)
      return 0
      ;;
  esac
  settings=$(lar_docker_settings)
  if [ ! -f "$settings" ] || ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  missing=0
  path=$(lar_share_realpath data)
  status=$(lar_share_data_status "$settings" "$path" </dev/null)
  if [ "$status" != "already" ]; then
    printf '%s\n' "Docker todavía no puede usar esta carpeta:" >&2
    printf '%s\n' "  $path" >&2
    missing=1
  fi
  if [ -f "$LAR_ROOT/data/.site-mounts" ]; then
    seen_paths='|'
    while IFS='	' read -r service path target; do
      if [ -z "$target" ] || [ "$path" != "$target" ]; then
        continue
      fi
      case "$seen_paths" in
        *"|$path|"*)
          continue
          ;;
      esac
      seen_paths="${seen_paths}${path}|"
      status=$(lar_share_data_status "$settings" "$path" </dev/null)
      if [ "$status" != "already" ]; then
        printf '%s\n' "Docker todavía no puede usar esta carpeta:" >&2
        printf '%s\n' "  $path" >&2
        missing=1
      fi
    done < "$LAR_ROOT/data/.site-mounts"
  fi
  if [ "$missing" -eq 1 ]; then
    printf '%s\n' "Ciérralo desde el icono de la ballena, ejecuta ./lar.sh install y, cuando añada la ruta, ábrelo y vuelve a ejecutar ./lar.sh up." >&2
    exit 1
  fi
}

lar_share_data() {
  case "$(uname -s)" in
    Darwin)
      ;;
    *)
      printf '%s\n' "  En este sistema Docker monta las carpetas directamente"
      return 0
      ;;
  esac

  settings=$(lar_docker_settings)
  targets=$(mktemp)
  lar_share_targets | awk '!seen[$0]++' > "$targets"
  if [ ! -f "$settings" ]; then
    printf '%s\n' "  No encuentro la configuración de Docker Desktop."
    printf '%s\n' "  Añade estas rutas en Docker Desktop → Resources → File sharing:"
    while IFS= read -r path; do
      printf '%s\n' "  $path"
    done < "$targets"
    rm -f "$targets"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "  Hace falta python3 para editar la configuración de Docker Desktop."
    printf '%s\n' "  Añade estas rutas a mano:"
    while IFS= read -r path; do
      printf '%s\n' "  $path"
    done < "$targets"
    rm -f "$targets"
    return 0
  fi

  missing=$(mktemp)
  while IFS= read -r path; do
    if [ -z "$path" ]; then
      continue
    fi
    status=$(lar_share_data_status "$settings" "$path" </dev/null)
    if [ "$status" = "already" ]; then
      printf '%s\n' "  Docker ya puede usar $path"
      continue
    fi
    printf '%s\n' "$path" >> "$missing"
  done < "$targets"
  rm -f "$targets"
  if [ ! -s "$missing" ]; then
    rm -f "$missing"
    return 0
  fi

  if [ ! -r /dev/tty ]; then
    printf '%s\n' "  Sin terminal interactiva no se cambia la configuración de Docker Desktop."
    printf '%s\n' "  Sin esas rutas, ./lar.sh up no puede usar los sitios ni guardar datos."
    rm -f "$missing"
    return 0
  fi

  printf '%s\n' "Docker todavía no puede usar estas carpetas:"
  while IFS= read -r path; do
    printf '%s\n' "  $path"
  done < "$missing"
  printf '%s\n' "Hay que añadirlas a Docker Desktop. Antes se guarda una copia en data/backups/docker-settings.json."
  if ! lar_ask_yes "¿Añadir esas carpetas?"; then
    printf '%s\n' "  No se modifica la configuración de Docker Desktop."
    printf '%s\n' "  Sin esas rutas, ./lar.sh up no puede usar los sitios ni guardar datos."
    rm -f "$missing"
    return 0
  fi

  if lar_docker_ready; then
    printf '%s\n' "  Docker Desktop está abierto. La ruta se guarda solo con la aplicación cerrada."
    printf '%s\n' "  Ciérralo desde el icono de la ballena → Quit."
    printf '%s' "  Cuando esté cerrado, pulsa Intro para añadir la ruta: " >/dev/tty
    read -r _ </dev/tty || true
    if lar_docker_ready; then
      printf '%s\n' "  Docker Desktop sigue abierto. Ciérralo y ejecuta otra vez ./lar.sh install." >&2
      rm -f "$missing"
      exit 1
    fi
  fi

  mkdir -p "$LAR_ROOT/data/backups"
  cp "$settings" "$LAR_ROOT/data/backups/docker-settings.json"
  while IFS= read -r path; do
    if ! lar_share_data_add "$settings" "$path"; then
      rm -f "$missing"
      lar_fail "No se pudo guardar la ruta en la configuración de Docker Desktop."
    fi
    printf '%s\n' "  Ruta añadida: $path"
  done < "$missing"
  rm -f "$missing"
  printf '%s\n' "  Reinicia Docker Desktop a mano: ciérralo y ábrelo otra vez."
  printf '%s\n' "  Cuando esté en marcha, ejecuta otra vez ./lar.sh install."
  exit 0
}

lar_ask_replace_files() {
  root=$1
  found=0
  for file in data/config/settings.yaml data/config/sites.yaml data/.env; do
    if [ -s "$root/$file" ]; then
      found=1
    fi
  done
  if [ "$found" -eq 0 ]; then
    return 1
  fi
  if [ ! -r /dev/tty ]; then
    printf '%s\n' "  Sin terminal interactiva no se sustituyen settings.yaml, sites.yaml ni data/.env."
    return 1
  fi
  printf '%s\n' "PELIGRO: responder que sí sustituye estos archivos por las plantillas:"
  for file in data/config/settings.yaml data/config/sites.yaml data/.env; do
    if [ -s "$root/$file" ]; then
      printf '%s\n' "  $file"
    fi
  done
  printf '%s\n' "data/.env, si se sustituye, vuelve a dejar el usuario root con contraseña toor."
  lar_ask_yes "¿Sustituir esos archivos?"
}

lar_require_vmnetd() {
  case "$(uname -s)" in
    Darwin)
      ;;
    *)
      return 0
      ;;
  esac

  helper=/Library/PrivilegedHelperTools/com.docker.vmnetd
  socket=/var/run/com.docker.vmnetd.sock
  if [ -f "$helper" ] || [ -S "$socket" ]; then
    printf '%s\n' "  vmnetd: instalado"
    return 0
  fi

  printf '%s\n' "En macOS, Docker necesita vmnetd para abrir el puerto 80." >&2
  printf '%s\n' "Ese ayudante no está instalado." >&2
  printf '%s\n' "Cierra Docker Desktop desde el icono de la ballena y ejecuta:" >&2
  printf '%s\n' "  sudo /Applications/Docker.app/Contents/MacOS/install vmnetd" >&2
  printf '%s\n' "Después ábrelo y vuelve a ejecutar ./lar.sh install." >&2
  exit 1
}

lar_install() {
  printf '%s\n' "Instalando LAR"
  overwrite=0
  if ! command -v docker >/dev/null 2>&1; then
    lar_fail "No se encuentra docker. Instala Docker Engine o Docker Desktop."
  fi
  if ! docker compose version >/dev/null 2>&1; then
    lar_fail "No se encuentra Docker Compose v2. Hace falta el comando: docker compose"
  fi
  lar_require_vmnetd
  lar_share_data
  lar_start_docker
  if lar_ask_replace_files "$LAR_ROOT"; then
    overwrite=1
  fi
  lar_init "$LAR_ROOT" "$overwrite"
}
