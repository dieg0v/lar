#!/bin/sh
# Patches for the PHP image. Included from lar.sh.

if [ "${0##*/}" = "update.sh" ]; then
  printf '%s\n' "This file is loaded from ./lar.sh" >&2
  exit 1
fi

lar_update_cleanup() {
  if [ -n "${LAR_UPDATE_DIR:-}" ]; then
    rm -rf "$LAR_UPDATE_DIR"
    LAR_UPDATE_DIR=''
  fi
}

lar_update_group() {
  case "$1" in
    php[0-9].[0-9]*)
      printf '%s\n' php
      ;;
    google-chrome-stable)
      printf '%s\n' chrome
      ;;
    ca-certificates|curl|git|unzip|sudo|zsh|tzdata|systemd-standalone-tmpfiles|rclone|rsync|htop|zip|pdftk-java|mysql-client|tar|wget|imagemagick|ffmpeg|tree|python3|golang-go|jpegoptim|optipng|pngquant|gifsicle|webp|libavif-bin|tmux|nano|vim)
      printf '%s\n' tools
      ;;
    *)
      printf '%s\n' skip
      ;;
  esac
}

lar_update_print_php() {
  awk -F '\t' '
    NF {
      ver = $1
      sub(/^php/, "", ver)
      sub(/-.*/, "", ver)
      mod = $1
      sub(/^php[0-9.]+-/, "", mod)
      if (!(ver in seen)) {
        seen[ver] = 1
        order[++n] = ver
        same[ver] = 1
        old[ver] = $2
        newv[ver] = $3
      } else if (old[ver] != $2 || newv[ver] != $3) {
        same[ver] = 0
      }
      line[ver] = line[ver] sprintf("  %s  %s  ->  %s\n", mod, $2, $3)
    }
    END {
      for (i = 1; i <= n; i++) {
        ver = order[i]
        if (same[ver]) printf "  %s  %s  ->  %s\n", ver, old[ver], newv[ver]
        else printf "%s", line[ver]
      }
    }
  ' "$1"
}

lar_update_print_rows() {
  while IFS=$(printf '\t') read -r update_pkg update_old update_new; do
    printf '  %s  %s  ->  %s\n' "$update_pkg" "$update_old" "$update_new"
  done < "$1"
}

lar_update_saved_names() {
  awk 'NF && $1 !~ /^#/ { print $1 }' "$LAR_ROOT/core/php/upgrade.list"
}

lar_update_apply() {
  accepted=$1
  list=$LAR_ROOT/core/php/upgrade.list
  stamp=$LAR_ROOT/core/php/upgrade.stamp
  invalid=$(cat "$accepted" | awk 'NF && $1 !~ /^[a-z0-9][a-z0-9.+-]*$/ { print $1 }')
  if [ -n "$invalid" ]; then
    lar_update_cleanup
    lar_fail "Invalid package: $invalid"
  fi
  tmp=$(mktemp)
  {
    printf '%s\n' "# Packages lar update upgrades in the image. One package per line."
    printf '%s\n' "# LibreOffice, Node, and gulp are not included here."
    {
      lar_update_saved_names
      cat "$accepted"
    } | sort -u
  } > "$tmp"
  mv "$tmp" "$list"
  date +%s > "$stamp"
  printf '%s\n' "Updating the PHP image. Shells in that container will close."
  lar_prepare_runtime
  lar_require_shared
  lar_compose up -d --build --force-recreate --no-deps php
  lar_reload_front
  printf '%s\n' "PHP image updated."
}

lar_update() {
  if [ "$#" -ne 0 ]; then
    printf '%s\n' "update does not accept arguments." >&2
    exit 2
  fi
  lar_prepare_runtime
  running=$(lar_compose ps --status running -q php 2>/dev/null || true)
  if [ -z "$running" ]; then
    lar_fail "The lar-php container is not running. Run lar up."
  fi
  LAR_UPDATE_DIR=$(mktemp -d)
  : > "$LAR_UPDATE_DIR/php"
  : > "$LAR_UPDATE_DIR/chrome"
  : > "$LAR_UPDATE_DIR/tools"
  : > "$LAR_UPDATE_DIR/accepted"
  printf '%s\n' "Looking for updates in the PHP machine"
  if ! lar_compose exec -T -u root php sh -s > "$LAR_UPDATE_DIR/raw" <<'EOF'
set -eu
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt list --upgradable 2>/dev/null | awk '
  /upgradable from:/ {
    split($1, a, "/")
    name = a[1]
    newv = $2
    oldv = ""
    n = split($0, parts, "upgradable from: ")
    if (n >= 2) {
      oldv = parts[2]
      sub(/\].*$/, "", oldv)
    }
    printf "UP\t%s\t%s\t%s\n", name, oldv, newv
  }
'
lo=$(soffice --version 2>/dev/null | awk 'NR == 1 { printf "%s %s\n", $1, $2; exit }')
printf "PIN\tlibreoffice\t%s\n" "$lo"
gver=$(gulp --version 2>/dev/null | awk -F ": " "/^CLI version/ { print \$2; exit }")
printf "PIN\tgulp\t%s\n" "$gver"
EOF
  then
    lar_update_cleanup
    lar_fail "Could not look for updates."
  fi
  pin_lo=''
  pin_gulp=''
  while IFS=$(printf '\t') read -r update_kind update_pkg update_old update_new; do
    case "$update_kind" in
      UP)
        case "$(lar_update_group "$update_pkg")" in
          php|chrome|tools)
            printf '%s\t%s\t%s\n' "$update_pkg" "$update_old" "$update_new" >> "$LAR_UPDATE_DIR/$(lar_update_group "$update_pkg")"
            ;;
        esac
        ;;
      PIN)
        case "$update_pkg" in
          libreoffice) pin_lo=$update_old ;;
          gulp) pin_gulp=$update_old ;;
        esac
        ;;
    esac
  done < "$LAR_UPDATE_DIR/raw"
  printf '\n'
  if [ -s "$LAR_UPDATE_DIR/php" ]; then
    printf '%s\n' "PHP"
    lar_update_print_php "$LAR_UPDATE_DIR/php"
  else
    printf '%s\n' "PHP is up to date"
  fi
  if [ -s "$LAR_UPDATE_DIR/chrome" ]; then
    printf '%s\n' "Chrome"
    lar_update_print_rows "$LAR_UPDATE_DIR/chrome"
  else
    printf '%s\n' "Chrome is up to date"
  fi
  if [ -s "$LAR_UPDATE_DIR/tools" ]; then
    printf '%s\n' "Tools"
    lar_update_print_rows "$LAR_UPDATE_DIR/tools"
  else
    printf '%s\n' "Tools are up to date"
  fi
  nodes=$(awk 'NF && $1 !~ /^#/ { printf "%s%s", sep, $1; sep = ", " }' "$LAR_ROOT/core/php/node-versions")
  if [ -z "$pin_lo" ]; then
    pin_lo='LibreOffice 7.3.7.2'
  fi
  if [ -z "$pin_gulp" ]; then
    pin_gulp='2.3.0'
  fi
  printf '%s\n' "Pinned"
  printf '  %s\n' "$pin_lo"
  printf '  Node %s\n' "$nodes"
  printf '  gulp-cli %s\n' "$pin_gulp"
  if [ ! -s "$LAR_UPDATE_DIR/php" ] && [ ! -s "$LAR_UPDATE_DIR/chrome" ] && [ ! -s "$LAR_UPDATE_DIR/tools" ]; then
    printf '%s\n' "There are no updates."
    lar_update_cleanup
    return 0
  fi
  if [ -n "$(lar_update_saved_names)" ]; then
    printf '%s\n' "If you accept a group, the last layer is rebuilt. What was already accepted is upgraded too."
  fi
  if [ -s "$LAR_UPDATE_DIR/php" ] && lar_ask_yes "Update PHP?"; then
    cut -f 1 "$LAR_UPDATE_DIR/php" >> "$LAR_UPDATE_DIR/accepted"
  fi
  if [ -s "$LAR_UPDATE_DIR/chrome" ] && lar_ask_yes "Update Chrome?"; then
    cut -f 1 "$LAR_UPDATE_DIR/chrome" >> "$LAR_UPDATE_DIR/accepted"
  fi
  if [ -s "$LAR_UPDATE_DIR/tools" ] && lar_ask_yes "Update the tools?"; then
    cut -f 1 "$LAR_UPDATE_DIR/tools" >> "$LAR_UPDATE_DIR/accepted"
  fi
  if [ ! -s "$LAR_UPDATE_DIR/accepted" ]; then
    printf '%s\n' "Nothing is changed."
    lar_update_cleanup
    return 0
  fi
  lar_update_apply "$LAR_UPDATE_DIR/accepted"
  lar_update_cleanup
}
