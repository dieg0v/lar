#!/bin/sh
# Inicialización de directorios y configuración local.
# Este archivo se incluye desde lar.sh.

if [ "${0##*/}" = "bootstrap.sh" ]; then
  printf '%s\n' "Este archivo se carga desde ./lar.sh" >&2
  exit 1
fi

lar_require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    lar_fail "No se encuentra docker. Instala Docker Engine o Docker Desktop."
  fi
  if ! docker compose version >/dev/null 2>&1; then
    lar_fail "No se encuentra Docker Compose v2. Hace falta el comando: docker compose"
  fi
  if ! docker info >/dev/null 2>&1; then
    lar_fail "Docker está instalado, pero el daemon no responde. Arranca Docker y vuelve a ejecutar ./lar.sh init."
  fi
  printf '%s\n' "  Docker y Compose v2: disponibles"
}

lar_init_dirs() {
  root=$1
  for dir in \
    config \
    config/services \
    config/sites \
    config/nginx \
    config/proxy \
    config/php \
    mysql57 \
    mysql8 \
    mariadb1011 \
    mariadb101 \
    elasticsearch \
    minio \
    redis \
    mailpit \
    certs \
    logs/apache \
    logs/nginx \
    logs/proxy \
    logs/php \
    backups
  do
    mkdir -p "$root/data/$dir"
    if [ ! -e "$root/data/$dir/.gitkeep" ]; then
      : > "$root/data/$dir/.gitkeep"
    fi
  done
  printf '%s\n' "  directorios de datos: listos"
}

lar_init_copy() {
  dest=$1
  src=$2
  label=$3
  overwrite=$4
  if [ ! -f "$src" ]; then
    lar_fail "Falta la plantilla: $src"
  fi
  if [ -e "$dest" ] && [ ! -f "$dest" ]; then
    lar_fail "$label existe y no es un archivo."
  fi
  replaced=0
  if [ -s "$dest" ]; then
    if [ "$overwrite" != 1 ]; then
      printf '%s\n' "  se conserva $label"
      return 0
    fi
    replaced=1
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  if [ "$replaced" = 1 ]; then
    printf '%s\n' "  sustituido $label"
  else
    printf '%s\n' "  creado $label"
  fi
}

lar_init_env() {
  root=$1
  overwrite=$2
  dest=$root/data/.env
  if [ -e "$dest" ] && [ ! -f "$dest" ]; then
    lar_fail "data/.env existe y no es un archivo."
  fi
  replaced=0
  if [ -s "$dest" ]; then
    if [ "$overwrite" != 1 ]; then
      printf '%s\n' "  se conserva data/.env"
      return 0
    fi
    replaced=1
  fi

  old_umask=$(umask)
  umask 077
  cat > "$dest" <<EOF
# Generado por ./lar.sh init. No se versiona.
# init no sobrescribe este archivo si ya tiene contenido.
# MySQL local: usuario root, contraseña toor. No se crea ninguna base de datos.
# MinIO: usuario minioadmin, contraseña minioadmin. La API usa el puerto 9000 y la consola el 9001.
MYSQL57_ROOT_PASSWORD=toor
MYSQL8_ROOT_PASSWORD=toor
MARIADB1011_ROOT_PASSWORD=toor
MARIADB101_ROOT_PASSWORD=toor
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
EOF
  umask "$old_umask"
  chmod 600 "$dest"
  if [ "$replaced" = 1 ]; then
    printf '%s\n' "  sustituido data/.env"
  else
    printf '%s\n' "  creado data/.env"
  fi
}

lar_env_has_key() {
  file=$1
  key=$2
  [ -f "$file" ] || return 1
  awk -F= -v k="$key" '$1 == k { found = 1 } END { exit found ? 0 : 1 }' "$file"
}

lar_env_ensure() {
  key=$1
  value=$2
  file=$LAR_ROOT/data/.env
  if lar_env_has_key "$file" "$key"; then
    return 0
  fi
  last=$(tail -c 1 "$file" 2>/dev/null | od -An -tu1 | tr -d ' ')
  if [ -n "$last" ] && [ "$last" != "10" ]; then
    printf '\n' >> "$file"
  fi
  printf '%s=%s\n' "$key" "$value" >> "$file"
  printf '%s\n' "  data/.env: añadido $key"
}

lar_copy_if_empty() {
  dest=$1
  src=$2
  label=$3
  if [ -s "$dest" ]; then
    return 0
  fi
  if [ -e "$dest" ] && [ ! -f "$dest" ]; then
    lar_fail "$label existe y no es un archivo."
  fi
  if [ ! -f "$src" ]; then
    lar_fail "Falta la plantilla: $src"
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  printf '%s\n' "  creado $label"
}

lar_ensure_service_configs() {
  root=$1
  for dir in mysql8 mariadb1011 mariadb101 elasticsearch minio \
    config/mysql8 config/mariadb1011 config/mariadb101
  do
    mkdir -p "$root/data/$dir"
    if [ ! -e "$root/data/$dir/.gitkeep" ]; then
      : > "$root/data/$dir/.gitkeep"
    fi
  done
  lar_copy_if_empty \
    "$root/data/config/apache/apache.conf" \
    "$root/core/apache/conf/lar.conf" \
    "data/config/apache/apache.conf"
  lar_copy_if_empty \
    "$root/data/config/redis/redis.conf" \
    "$root/core/redis/redis.conf" \
    "data/config/redis/redis.conf"
  lar_copy_if_empty \
    "$root/data/config/mysql57/mysql.cnf" \
    "$root/core/mysql57/mysql.cnf" \
    "data/config/mysql57/mysql.cnf"
  lar_copy_if_empty \
    "$root/data/config/mysql8/mysql.cnf" \
    "$root/core/mysql8/mysql.cnf" \
    "data/config/mysql8/mysql.cnf"
  lar_copy_if_empty \
    "$root/data/config/mariadb1011/mariadb.cnf" \
    "$root/core/mariadb1011/mariadb.cnf" \
    "data/config/mariadb1011/mariadb.cnf"
  lar_copy_if_empty \
    "$root/data/config/mariadb101/mariadb.cnf" \
    "$root/core/mariadb101/mariadb.cnf" \
    "data/config/mariadb101/mariadb.cnf"
  lar_copy_if_empty \
    "$root/data/config/mailpit.env" \
    "$root/core/mailpit/mailpit.env" \
    "data/config/mailpit.env"
  while read -r version ignored; do
    case "$version" in
      ''|\#*)
        continue
        ;;
    esac
    lar_copy_if_empty \
      "$root/data/config/php/${version}/php.ini" \
      "$root/core/php/${version}/php.ini" \
      "data/config/php/${version}/php.ini"
  done < "$root/core/php/versions"
}

lar_init() {
  root=$1
  overwrite=${2:-0}
  printf '%s\n' "Inicializando LAR"
  lar_require_docker
  lar_init_dirs "$root"
  lar_init_copy \
    "$root/data/config/settings.yaml" \
    "$root/core/templates/settings.yaml" \
    "data/config/settings.yaml" \
    "$overwrite"
  lar_init_copy \
    "$root/data/config/sites.yaml" \
    "$root/core/templates/sites.yaml" \
    "data/config/sites.yaml" \
    "$overwrite"
  lar_init_env "$root" "$overwrite"
  lar_ensure_service_configs "$root"
  lar_config_load "$root/data/config/settings.yaml"
  printf '%s\n' "  configuración: válida (timezone $LAR_TIMEZONE, bind por defecto $LAR_DEFAULT_BIND)"
  printf '%s\n' "Init terminado. Para arrancar los servicios habilitados: ./lar.sh up"
}
