#!/bin/sh
set -eu

lar_fpm_signal_conf() {
  signal_conf=$1
  signal_pid=$2
  if [ -n "$signal_pid" ] && [ -f "$signal_pid" ]; then
    kill -USR2 "$(cat "$signal_pid")" || true
    return 0
  fi
  for fpm_pid in $(ps -eo pid,args | awk -v conf="$signal_conf" '$2 == "php-fpm:" && index($0, conf) { print $1 }'); do
    kill -USR2 "$fpm_pid" || true
  done
}

lar_fpm_pid_alive() {
  alive_pid=$1
  [ -n "$alive_pid" ] && [ -f "$alive_pid" ] || return 1
  kill -0 "$(cat "$alive_pid")" 2>/dev/null
}

while read -r version listen; do
  case "$version" in
    ''|\#*)
      continue
      ;;
  esac
  pool_dir=/etc/php/$version/fpm/pool.d
  src_dir=/usr/local/lar/php-config/$version/fpm
  extra_root=/run/lar-fpm/$version
  mkdir -p "$pool_dir" "$extra_root"
  for link in "$pool_dir"/zz-*.conf; do
    if [ -L "$link" ]; then
      rm -f "$link"
    fi
  done
  if [ -d "$extra_root" ]; then
    for extra_pool in "$extra_root"/*/pool.d; do
      if [ -d "$extra_pool" ]; then
        rm -f "$extra_pool"/*.conf
      fi
    done
  fi
  modes_seen=' '
  if [ -d "$src_dir" ]; then
    for conf in "$src_dir"/*.conf; do
      if [ ! -f "$conf" ]; then
        continue
      fi
      mode=$(awk -F= '/^env\[XDEBUG_MODE\]/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }' "$conf")
      base=$(basename "$conf")
      case "$mode" in
        ''|off)
          ln -sfn "$conf" "$pool_dir/zz-$base"
          ;;
        *)
          slug=$(printf '%s' "$mode" | tr ',' '_')
          dest_dir=$extra_root/$slug/pool.d
          mkdir -p "$dest_dir"
          ln -sfn "$conf" "$dest_dir/$base"
          printf '%s\n' "$mode" > "$extra_root/$slug/mode"
          case "$modes_seen" in
            *" $slug "*) ;;
            *) modes_seen="$modes_seen$slug " ;;
          esac
          ;;
      esac
    done
  fi
  ini=/usr/local/lar/php-config/$version/php.ini
  if [ -s "$ini" ]; then
    ln -sfn "$ini" "/etc/php/$version/fpm/conf.d/zz-lar.ini"
    ln -sfn "$ini" "/etc/php/$version/cli/conf.d/zz-lar.ini"
  fi
  lar_fpm_signal_conf "/etc/php/$version/fpm/php-fpm.conf" "/run/php/php$version-fpm.pid"
  for slug_dir in "$extra_root"/*; do
    if [ ! -d "$slug_dir" ]; then
      continue
    fi
    slug=$(basename "$slug_dir")
    case "$modes_seen" in
      *" $slug "*)
        mode=$(sed -n '1p' "$slug_dir/mode")
        fpm_conf=$slug_dir/php-fpm.conf
        pidfile=$slug_dir/php-fpm.pid
        cat > "$fpm_conf" <<EOF
[global]
pid = $pidfile
error_log = /var/log/php${version}-fpm.log
include = $slug_dir/pool.d/*.conf
EOF
        if lar_fpm_pid_alive "$pidfile"; then
          lar_fpm_signal_conf "$fpm_conf" "$pidfile"
        else
          sleep 1
          XDEBUG_MODE=$mode php-fpm"$version" --daemonize --fpm-config "$fpm_conf" --pid "$pidfile"
        fi
        ;;
      *)
        if lar_fpm_pid_alive "$slug_dir/php-fpm.pid"; then
          kill "$(cat "$slug_dir/php-fpm.pid")" || true
        fi
        rm -rf "$slug_dir"
        ;;
    esac
  done
done < /usr/local/lar/versions
