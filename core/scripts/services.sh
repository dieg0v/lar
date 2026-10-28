#!/bin/sh
# Arranque, parada, estado y logs. Se incluye desde lar.sh.

if [ "${0##*/}" = "services.sh" ]; then
  printf '%s\n' "Este archivo se carga desde ./lar.sh" >&2
  exit 1
fi

lar_bind_ip() {
  case "$1" in
    local)
      printf '%s\n' "127.0.0.1"
      ;;
    lan)
      printf '%s\n' "0.0.0.0"
      ;;
    *)
      lar_fail "Bind no válido: $1"
      ;;
  esac
}

lar_env_value() {
  file=$1
  key=$2
  [ -f "$file" ] || return 0
  awk -F= -v k="$key" '
    $1 == k {
      print substr($0, length(k) + 2)
      exit
    }
  ' "$file"
}

lar_known_service() {
  case "$1" in
    proxy|apache|nginx|php|mysql57|mysql8|mariadb1011|mariadb101|elasticsearch|minio|redis|mailpit)
      return 0
      ;;
    php56|php70|php74|php80|php81|php82|php85)
      printf '%s\n' "Las versiones de PHP van dentro del servicio php. Usa ./lar.sh up php." >&2
      exit 2
      ;;
    *)
      return 1
      ;;
  esac
}

lar_unknown_service() {
  printf '%s\n' "Servicio desconocido: $1" >&2
  printf '%s\n' "Servicios: proxy, apache, nginx, php, mysql57, mysql8, mariadb1011, mariadb101, elasticsearch, minio, redis, mailpit" >&2
  exit 2
}

lar_service_enabled() {
  case "$1" in
    proxy) [ "$LAR_SERVICE_PROXY" = true ] ;;
    apache) [ "$LAR_SERVICE_APACHE" = true ] ;;
    nginx) [ "$LAR_SERVICE_NGINX" = true ] ;;
    php) [ "$LAR_SERVICE_PHP" = true ] ;;
    mysql57) [ "$LAR_SERVICE_MYSQL57" = true ] ;;
    mysql8) [ "$LAR_SERVICE_MYSQL8" = true ] ;;
    mariadb1011) [ "$LAR_SERVICE_MARIADB1011" = true ] ;;
    mariadb101) [ "$LAR_SERVICE_MARIADB101" = true ] ;;
    elasticsearch) [ "$LAR_SERVICE_ELASTICSEARCH" = true ] ;;
    minio) [ "$LAR_SERVICE_MINIO" = true ] ;;
    redis) [ "$LAR_SERVICE_REDIS" = true ] ;;
    mailpit) [ "$LAR_SERVICE_MAILPIT" = true ] ;;
    *) return 1 ;;
  esac
}

lar_prepare_runtime() {
  if [ ! -f "$LAR_ROOT/data/config/settings.yaml" ]; then
    lar_fail "Falta data/config/settings.yaml. Ejecuta ./lar.sh init."
  fi
  if [ ! -s "$LAR_ROOT/data/.env" ]; then
    lar_fail "Falta data/.env. Ejecuta ./lar.sh init."
  fi
  lar_config_load "$LAR_ROOT/data/config/settings.yaml"
  lar_require_docker

  LAR_BIND_HTTP_IP=$(lar_bind_ip "$LAR_BIND_HTTP")
  LAR_BIND_MYSQL57_IP=$(lar_bind_ip "$LAR_BIND_MYSQL57")
  LAR_BIND_MYSQL8_IP=$(lar_bind_ip "$LAR_BIND_MYSQL8")
  LAR_BIND_MARIADB1011_IP=$(lar_bind_ip "$LAR_BIND_MARIADB1011")
  LAR_BIND_MARIADB101_IP=$(lar_bind_ip "$LAR_BIND_MARIADB101")
  LAR_BIND_ELASTICSEARCH_IP=$(lar_bind_ip "$LAR_BIND_ELASTICSEARCH")
  LAR_BIND_MINIO_IP=$(lar_bind_ip "$LAR_BIND_MINIO")
  LAR_BIND_REDIS_IP=$(lar_bind_ip "$LAR_BIND_REDIS")
  LAR_BIND_MAILPIT_IP=$(lar_bind_ip "$LAR_BIND_MAILPIT")
  export LAR_TIMEZONE
  export LAR_BIND_HTTP_IP LAR_PORT_HTTP
  export LAR_BIND_MYSQL57_IP LAR_PORT_MYSQL57
  export LAR_BIND_MYSQL8_IP LAR_PORT_MYSQL8
  export LAR_BIND_MARIADB1011_IP LAR_PORT_MARIADB1011
  export LAR_BIND_MARIADB101_IP LAR_PORT_MARIADB101
  export LAR_BIND_ELASTICSEARCH_IP LAR_PORT_ELASTICSEARCH LAR_PORT_ELASTICSEARCH_TRANSPORT
  export LAR_BIND_MINIO_IP LAR_PORT_MINIO LAR_PORT_MINIO_CONSOLE
  export LAR_BIND_REDIS_IP LAR_PORT_REDIS
  export LAR_BIND_MAILPIT_IP LAR_PORT_MAILPIT_SMTP LAR_PORT_MAILPIT_WEB

  LAR_COMPOSE_OVERRIDE=''
  redis_password=$(lar_env_value "$LAR_ROOT/data/.env" REDIS_PASSWORD)
  case "$redis_password" in
    *[!A-Za-z0-9]*)
      lar_fail "REDIS_PASSWORD en data/.env solo puede contener letras y números."
      ;;
  esac
  if [ "$LAR_BIND_REDIS" = "lan" ] && [ -z "$redis_password" ]; then
    lar_fail "Redis con bind lan necesita REDIS_PASSWORD en data/.env."
  fi
  lar_env_ensure MYSQL8_ROOT_PASSWORD toor
  lar_env_ensure MARIADB1011_ROOT_PASSWORD toor
  lar_env_ensure MARIADB101_ROOT_PASSWORD toor
  lar_env_ensure MINIO_ROOT_USER minioadmin
  lar_env_ensure MINIO_ROOT_PASSWORD minioadmin
  if [ "$LAR_SERVICE_MINIO" = true ]; then
    minio_user=$(lar_env_value "$LAR_ROOT/data/.env" MINIO_ROOT_USER)
    minio_password=$(lar_env_value "$LAR_ROOT/data/.env" MINIO_ROOT_PASSWORD)
    if [ -z "$minio_user" ] || [ "${#minio_password}" -lt 8 ]; then
      lar_fail "MinIO necesita MINIO_ROOT_USER y una MINIO_ROOT_PASSWORD de 8 caracteres o más en data/.env."
    fi
  fi
  lar_ensure_service_configs "$LAR_ROOT"
  lar_sites_prepare
  lar_write_runtime "$redis_password"
}

lar_write_runtime() {
  password=$1
  mounts=$LAR_ROOT/data/.site-mounts
  dest=$LAR_ROOT/data/.runtime.yml
  has_mounts=0
  if [ -s "$mounts" ]; then
    has_mounts=1
  fi
  if [ -z "$password" ] && [ "$has_mounts" -eq 0 ]; then
    rm -f "$dest"
    LAR_COMPOSE_OVERRIDE=''
    return 0
  fi
  old_umask=$(umask)
  umask 077
  {
    printf '%s\n' "services:"
    if [ "$has_mounts" -eq 1 ]; then
      services=$(cut -f 1 "$mounts" | sort -u)
      for service in $services; do
        printf '%s\n' "  ${service}:"
        printf '%s\n' "    volumes:"
        awk -F '\t' -v wanted="$service" '$1 == wanted { target = $3; if (target == "") target = $2; print $2 "\t" target }' "$mounts" | while IFS='	' read -r host target; do
          host_escaped=$(printf '%s' "$host" | sed 's/\\/\\\\/g; s/"/\\"/g')
          target_escaped=$(printf '%s' "$target" | sed 's/\\/\\\\/g; s/"/\\"/g')
          printf '      - "%s:%s"\n' "$host_escaped" "$target_escaped"
        done
      done
    fi
    if [ -n "$password" ]; then
      printf '%s\n' "  redis:"
      printf '%s\n' "    command: [\"redis-server\", \"/usr/local/etc/redis/redis.conf\", \"--requirepass\", \"${password}\"]"
    fi
  } > "$dest"
  umask "$old_umask"
  LAR_COMPOSE_OVERRIDE=$dest
}

lar_compose() {
  if [ -n "$LAR_COMPOSE_OVERRIDE" ]; then
    docker compose \
      --project-name lar \
      --project-directory "$LAR_ROOT/core" \
      -f "$LAR_ROOT/core/docker-compose.yml" \
      -f "$LAR_COMPOSE_OVERRIDE" \
      --env-file "$LAR_ROOT/data/.env" \
      "$@"
  else
    docker compose \
      --project-name lar \
      --project-directory "$LAR_ROOT/core" \
      -f "$LAR_ROOT/core/docker-compose.yml" \
      --env-file "$LAR_ROOT/data/.env" \
      "$@"
  fi
}

lar_default_services() {
  LAR_SERVICE_LIST=''
  if [ "$LAR_SERVICE_PROXY" = true ]; then
    LAR_SERVICE_LIST="$LAR_SERVICE_LIST proxy"
  fi
  if [ "$LAR_SERVICE_APACHE" = true ]; then
    LAR_SERVICE_LIST="$LAR_SERVICE_LIST apache"
  fi
  if [ "$LAR_SERVICE_NGINX" = true ]; then
    LAR_SERVICE_LIST="$LAR_SERVICE_LIST nginx"
  fi
  if [ "$LAR_SERVICE_PHP" = true ]; then
    LAR_SERVICE_LIST="$LAR_SERVICE_LIST php"
  fi
  if [ "$LAR_SERVICE_MYSQL57" = true ]; then
    LAR_SERVICE_LIST="$LAR_SERVICE_LIST mysql57"
  fi
  if [ "$LAR_SERVICE_MYSQL8" = true ]; then
    LAR_SERVICE_LIST="$LAR_SERVICE_LIST mysql8"
  fi
  if [ "$LAR_SERVICE_MARIADB1011" = true ]; then
    LAR_SERVICE_LIST="$LAR_SERVICE_LIST mariadb1011"
  fi
  if [ "$LAR_SERVICE_MARIADB101" = true ]; then
    LAR_SERVICE_LIST="$LAR_SERVICE_LIST mariadb101"
  fi
  if [ "$LAR_SERVICE_ELASTICSEARCH" = true ]; then
    LAR_SERVICE_LIST="$LAR_SERVICE_LIST elasticsearch"
  fi
  if [ "$LAR_SERVICE_MINIO" = true ]; then
    LAR_SERVICE_LIST="$LAR_SERVICE_LIST minio"
  fi
  if [ "$LAR_SERVICE_REDIS" = true ]; then
    LAR_SERVICE_LIST="$LAR_SERVICE_LIST redis"
  fi
  if [ "$LAR_SERVICE_MAILPIT" = true ]; then
    LAR_SERVICE_LIST="$LAR_SERVICE_LIST mailpit"
  fi
  LAR_SERVICE_LIST=$(printf '%s' "$LAR_SERVICE_LIST" | sed 's/^ *//')
  if [ -z "$LAR_SERVICE_LIST" ]; then
    lar_fail "No hay servicios habilitados en settings.yaml."
  fi
}

lar_warn_bind() {
  service=$1
  bind=$2
  if [ "$bind" = "lan" ]; then
    printf '%s\n' "Aviso: $service se publica en todas las interfaces." >&2
  fi
}

lar_check_one_service() {
  service=$1
  if ! lar_known_service "$service"; then
    lar_unknown_service "$service"
  fi
  if ! lar_service_enabled "$service"; then
    printf '%s\n' "Aviso: $service está desactivado en settings.yaml. Se gestiona solo esta vez." >&2
  fi
  case "$service" in
    proxy) lar_warn_bind proxy "$LAR_BIND_HTTP" ;;
    mysql57) lar_warn_bind mysql57 "$LAR_BIND_MYSQL57" ;;
    mysql8) lar_warn_bind mysql8 "$LAR_BIND_MYSQL8" ;;
    mariadb1011) lar_warn_bind mariadb1011 "$LAR_BIND_MARIADB1011" ;;
    mariadb101) lar_warn_bind mariadb101 "$LAR_BIND_MARIADB101" ;;
    elasticsearch) lar_warn_bind elasticsearch "$LAR_BIND_ELASTICSEARCH" ;;
    minio) lar_warn_bind minio "$LAR_BIND_MINIO" ;;
    redis) lar_warn_bind redis "$LAR_BIND_REDIS" ;;
    mailpit) lar_warn_bind mailpit "$LAR_BIND_MAILPIT" ;;
  esac
}

lar_command_needs_sites() {
  if [ "$#" -eq 0 ]; then
    case " $LAR_SERVICE_LIST " in
      *" proxy "*|*" apache "*|*" nginx "*|*" php "*)
        return 0
        ;;
    esac
    return 1
  fi
  case "$1" in
    proxy|apache|nginx|php)
      return 0
      ;;
  esac
  return 1
}

lar_reload_php() {
  running=$(lar_compose ps --status running -q php 2>/dev/null || true)
  if [ -z "$running" ]; then
    return 0
  fi
  lar_compose exec -T php lar-php-reload >/dev/null
}

lar_reload_apache() {
  running=$(lar_compose ps --status running -q apache 2>/dev/null || true)
  if [ -z "$running" ]; then
    return 0
  fi
  lar_compose exec -T apache apachectl graceful >/dev/null
}

lar_reload_nginx_service() {
  reload_service=$1
  running=$(lar_compose ps --status running -q "$reload_service" 2>/dev/null || true)
  if [ -z "$running" ]; then
    return 0
  fi
  lar_compose exec -T "$reload_service" nginx -s reload >/dev/null
}

lar_reload_front() {
  lar_reload_php
  lar_reload_apache
  lar_reload_nginx_service nginx
  lar_reload_nginx_service proxy
}

lar_truncate_logs() {
  for log_dir in apache nginx proxy php; do
    log_path=$LAR_ROOT/data/logs/$log_dir
    if [ ! -d "$log_path" ]; then
      continue
    fi
    for log_file in "$log_path"/*.log; do
      if [ ! -f "$log_file" ]; then
        continue
      fi
      : > "$log_file"
    done
  done
  printf '%s\n' "Logs vaciados."
}

lar_up() {
  if [ "$#" -gt 1 ]; then
    printf '%s\n' "up admite como máximo un servicio." >&2
    exit 2
  fi
  if [ "$#" -eq 1 ] && ! lar_known_service "$1"; then
    lar_unknown_service "$1"
  fi
  lar_prepare_runtime
  lar_truncate_logs
  if [ "$#" -eq 1 ]; then
    lar_check_one_service "$1"
    if lar_command_needs_sites "$1"; then
      lar_require_shared
    fi
    printf '%s\n' "Arrancando $1"
    lar_compose up -d --build --remove-orphans "$1"
    case "$1" in
      proxy|apache|nginx|php)
        lar_reload_front
        ;;
    esac
    lar_sites_hosts_hint
    return 0
  fi
  lar_default_services
  if lar_command_needs_sites; then
    lar_require_shared
  fi
  for service in $LAR_SERVICE_LIST; do
    case "$service" in
      proxy) lar_warn_bind proxy "$LAR_BIND_HTTP" ;;
      mysql57) lar_warn_bind mysql57 "$LAR_BIND_MYSQL57" ;;
      mysql8) lar_warn_bind mysql8 "$LAR_BIND_MYSQL8" ;;
      mariadb1011) lar_warn_bind mariadb1011 "$LAR_BIND_MARIADB1011" ;;
      mariadb101) lar_warn_bind mariadb101 "$LAR_BIND_MARIADB101" ;;
      elasticsearch) lar_warn_bind elasticsearch "$LAR_BIND_ELASTICSEARCH" ;;
      minio) lar_warn_bind minio "$LAR_BIND_MINIO" ;;
      redis) lar_warn_bind redis "$LAR_BIND_REDIS" ;;
      mailpit) lar_warn_bind mailpit "$LAR_BIND_MAILPIT" ;;
    esac
  done
  printf '%s\n' "Arrancando: $LAR_SERVICE_LIST"
  # Los nombres salen de una lista fija de servicios.
  # shellcheck disable=SC2086
  lar_compose up -d --build --remove-orphans $LAR_SERVICE_LIST
  lar_reload_front
  lar_sites_hosts_sync
}

lar_down() {
  if [ "$#" -gt 1 ]; then
    printf '%s\n' "down admite como máximo un servicio." >&2
    exit 2
  fi
  lar_prepare_runtime
  if [ "$#" -eq 1 ]; then
    lar_check_one_service "$1"
    lar_compose stop "$1"
  else
    lar_compose down --remove-orphans
  fi
  if [ "$#" -eq 0 ]; then
    lar_sites_hosts_clear
  fi
  printf '%s\n' "Los datos de data/ se conservan."
}

lar_restart() {
  if [ "$#" -gt 1 ]; then
    printf '%s\n' "restart admite como máximo un servicio." >&2
    exit 2
  fi
  lar_prepare_runtime
  if [ "$#" -eq 1 ]; then
    lar_check_one_service "$1"
    lar_compose restart "$1"
    lar_reload_front
    return 0
  fi
  lar_default_services
  # shellcheck disable=SC2086
  lar_compose restart $LAR_SERVICE_LIST
  lar_reload_front
}

lar_status() {
  if [ "$#" -ne 0 ]; then
    printf '%s\n' "status no admite argumentos." >&2
    exit 2
  fi
  lar_prepare_runtime
  lar_compose ps -a
}

lar_logs() {
  if [ "$#" -gt 1 ]; then
    printf '%s\n' "logs admite como máximo un servicio." >&2
    exit 2
  fi
  lar_prepare_runtime
  if [ "$#" -eq 1 ]; then
    lar_check_one_service "$1"
    lar_compose logs --tail 200 "$1"
    return 0
  fi
  lar_compose logs --tail 200
}
