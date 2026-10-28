#!/bin/sh
set -eu

while read -r version listen; do
  case "$version" in
    ''|\#*)
      continue
      ;;
  esac
  pool_dir=/etc/php/$version/fpm/pool.d
  src_dir=/usr/local/lar/php-config/$version/fpm
  if [ -d "$src_dir" ]; then
    for conf in "$src_dir"/*.conf; do
      if [ ! -f "$conf" ]; then
        continue
      fi
      ln -sfn "$conf" "$pool_dir/zz-$(basename "$conf")"
    done
  fi
  for link in "$pool_dir"/zz-*.conf; do
    if [ -L "$link" ] && [ ! -e "$link" ]; then
      rm -f "$link"
    fi
  done
  ini=/usr/local/lar/php-config/$version/php.ini
  if [ -s "$ini" ]; then
    ln -sfn "$ini" "/etc/php/$version/fpm/conf.d/zz-lar.ini"
    ln -sfn "$ini" "/etc/php/$version/cli/conf.d/zz-lar.ini"
  fi
  pid=/run/php/php$version-fpm.pid
  if [ -f "$pid" ]; then
    kill -USR2 "$(cat "$pid")" || true
  fi
done < /usr/local/lar/versions
