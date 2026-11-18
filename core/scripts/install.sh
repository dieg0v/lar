#!/bin/sh
# Starts Docker and shares data/. Included from lar.sh.

if [ "${0##*/}" = "install.sh" ]; then
  printf '%s\n' "This file is loaded from ./lar.sh" >&2
  exit 1
fi

lar_ask_yes() {
  prompt=$1
  if [ ! -r /dev/tty ]; then
    return 1
  fi
  printf '%s [y/N] ' "$prompt" >/dev/tty
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
  printf '%s' "  Waiting for Docker"
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
    lar_fail "docker was not found. Install Docker Engine or Docker Desktop."
  fi
  if ! docker compose version >/dev/null 2>&1; then
    lar_fail "Docker Compose v2 was not found. The command is required: docker compose"
  fi
  if docker info >/dev/null 2>&1; then
    printf '%s\n' "  Docker is already running"
    return 0
  fi
  case "$(uname -s)" in
    Darwin)
      printf '%s\n' "  Opening Docker Desktop"
      open -a Docker
      ;;
    *)
      lar_fail "Docker is not running. Start the service and run ./lar.sh install again."
      ;;
  esac
  if ! lar_wait_docker; then
    lar_fail "Docker did not respond. Open it by hand and run ./lar.sh install again."
  fi
  printf '%s\n' "  Docker and Compose v2: available"
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
    printf '%s\n' "Docker still cannot use this folder:" >&2
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
        printf '%s\n' "Docker still cannot use this folder:" >&2
        printf '%s\n' "  $path" >&2
        missing=1
      fi
    done < "$LAR_ROOT/data/.site-mounts"
  fi
  if [ "$missing" -eq 1 ]; then
    printf '%s\n' "Quit it from the whale icon, run ./lar.sh install and, when it adds the path, open it and run ./lar.sh up again." >&2
    exit 1
  fi
}

lar_share_data() {
  case "$(uname -s)" in
    Darwin)
      ;;
    *)
      printf '%s\n' "  On this system Docker mounts the folders directly"
      return 0
      ;;
  esac

  settings=$(lar_docker_settings)
  targets=$(mktemp)
  lar_share_targets | awk '!seen[$0]++' > "$targets"
  if [ ! -f "$settings" ]; then
    printf '%s\n' "  Docker Desktop configuration was not found."
    printf '%s\n' "  Add these paths in Docker Desktop → Resources → File sharing:"
    while IFS= read -r path; do
      printf '%s\n' "  $path"
    done < "$targets"
    rm -f "$targets"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "  python3 is required to edit the Docker Desktop configuration."
    printf '%s\n' "  Add these paths by hand:"
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
      printf '%s\n' "  Docker can already use $path"
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
    printf '%s\n' "  Without an interactive terminal the Docker Desktop configuration is not changed."
    printf '%s\n' "  Without those paths, ./lar.sh up cannot use the sites or store data."
    rm -f "$missing"
    return 0
  fi

  printf '%s\n' "Docker still cannot use these folders:"
  while IFS= read -r path; do
    printf '%s\n' "  $path"
  done < "$missing"
  printf '%s\n' "They have to be added to Docker Desktop. A copy is saved first in data/backups/docker-settings.json."
  if ! lar_ask_yes "Add those folders?"; then
    printf '%s\n' "  The Docker Desktop configuration is not changed."
    printf '%s\n' "  Without those paths, ./lar.sh up cannot use the sites or store data."
    rm -f "$missing"
    return 0
  fi

  if lar_docker_ready; then
    printf '%s\n' "  Docker Desktop is open. The path is saved only while the application is closed."
    printf '%s\n' "  Quit it from the whale icon → Quit."
    printf '%s' "  When it is closed, press Enter to add the path: " >/dev/tty
    read -r _ </dev/tty || true
    if lar_docker_ready; then
      printf '%s\n' "  Docker Desktop is still open. Quit it and run ./lar.sh install again." >&2
      rm -f "$missing"
      exit 1
    fi
  fi

  mkdir -p "$LAR_ROOT/data/backups"
  cp "$settings" "$LAR_ROOT/data/backups/docker-settings.json"
  while IFS= read -r path; do
    if ! lar_share_data_add "$settings" "$path"; then
      rm -f "$missing"
      lar_fail "Could not save the path in the Docker Desktop configuration."
    fi
    printf '%s\n' "  Path added: $path"
  done < "$missing"
  rm -f "$missing"
  printf '%s\n' "  Restart Docker Desktop by hand: quit it and open it again."
  printf '%s\n' "  When it is running, run ./lar.sh install again."
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
    printf '%s\n' "  Without an interactive terminal, settings.yaml, sites.yaml, and data/.env are not replaced."
    return 1
  fi
  printf '%s\n' "DANGER: answering yes replaces these files with the templates:"
  for file in data/config/settings.yaml data/config/sites.yaml data/.env; do
    if [ -s "$root/$file" ]; then
      printf '%s\n' "  $file"
    fi
  done
  printf '%s\n' "If data/.env is replaced, the root user password goes back to toor."
  lar_ask_yes "Replace those files?"
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
    printf '%s\n' "  vmnetd: installed"
    return 0
  fi

  printf '%s\n' "On macOS, Docker needs vmnetd to open port 80." >&2
  printf '%s\n' "That helper is not installed." >&2
  printf '%s\n' "Quit Docker Desktop from the whale icon and run:" >&2
  printf '%s\n' "  sudo /Applications/Docker.app/Contents/MacOS/install vmnetd" >&2
  printf '%s\n' "Then open it and run ./lar.sh install again." >&2
  exit 1
}

lar_install() {
  printf '%s\n' "Installing LAR"
  overwrite=0
  if ! command -v docker >/dev/null 2>&1; then
    lar_fail "docker was not found. Install Docker Engine or Docker Desktop."
  fi
  if ! docker compose version >/dev/null 2>&1; then
    lar_fail "Docker Compose v2 was not found. The command is required: docker compose"
  fi
  lar_require_vmnetd
  lar_share_data
  lar_start_docker
  if lar_ask_replace_files "$LAR_ROOT"; then
    overwrite=1
  fi
  lar_init "$LAR_ROOT" "$overwrite"
}
