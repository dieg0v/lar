#!/bin/sh
set -eu

if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
  ln -sfn "/usr/share/zoneinfo/$TZ" /etc/localtime
  printf '%s\n' "$TZ" > /etc/timezone
fi

/usr/local/bin/lar-php-reload

pids=''
while read -r version listen; do
  case "$version" in
    ''|\#*)
      continue
      ;;
  esac
  conf=/etc/php/$version/fpm/pool.d/www.conf
  sed -i "s|^listen = .*|listen = ${listen}|" "$conf"
  sed -i "s|^user = .*|user = web|" "$conf"
  sed -i "s|^group = .*|group = web|" "$conf"
  sed -i 's|^listen.allowed_clients|;listen.allowed_clients|' "$conf"
  if grep -q '^clear_env' "$conf"; then
    sed -i 's|^clear_env = .*|clear_env = no|' "$conf"
  else
    printf '\n%s\n' 'clear_env = no' >> "$conf"
  fi
  php-fpm"$version" --nodaemonize &
  pids="$pids $!"
done < /usr/local/lar/versions

trap 'kill $pids 2>/dev/null || true; wait' TERM INT
wait
