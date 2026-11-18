#!/bin/sh
# Loads a subset of settings.yaml: scalars and one-level sections.
# This file is included from lar.sh.

if [ "${0##*/}" = "config.sh" ]; then
  printf '%s\n' "This file is loaded from ./lar.sh" >&2
  exit 1
fi

lar_fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

lar_config_fail() {
  printf '%s:%s: %s\n' "$1" "$2" "$3" >&2
  exit 1
}

lar_config_defaults() {
  LAR_TIMEZONE='Europe/Madrid'
  LAR_DEFAULT_BIND='local'

  LAR_PORT_HTTP=80
  LAR_PORT_HTTPS=443
  LAR_PORT_MYSQL57=3306
  LAR_PORT_MYSQL8=3307
  LAR_PORT_MARIADB1011=3309
  LAR_PORT_MARIADB101=33066
  LAR_PORT_ELASTICSEARCH=9200
  LAR_PORT_ELASTICSEARCH_TRANSPORT=9300
  LAR_PORT_MINIO=9000
  LAR_PORT_MINIO_CONSOLE=9001
  LAR_PORT_REDIS=6379
  LAR_PORT_MAILPIT_SMTP=1025
  LAR_PORT_MAILPIT_WEB=8025

  LAR_SERVICE_PROXY=true
  LAR_SERVICE_APACHE=true
  LAR_SERVICE_NGINX=true
  LAR_SERVICE_PHP=true
  LAR_SERVICE_MYSQL57=true
  LAR_SERVICE_MYSQL8=true
  LAR_SERVICE_MARIADB1011=true
  LAR_SERVICE_MARIADB101=true
  LAR_SERVICE_ELASTICSEARCH=true
  LAR_SERVICE_MINIO=true
  LAR_SERVICE_REDIS=true
  LAR_SERVICE_MAILPIT=true

  LAR_BIND_HTTP=''
  LAR_BIND_HTTPS=''
  LAR_BIND_MYSQL57=''
  LAR_BIND_MYSQL8=''
  LAR_BIND_MARIADB1011=''
  LAR_BIND_MARIADB101=''
  LAR_BIND_ELASTICSEARCH=''
  LAR_BIND_MINIO=''
  LAR_BIND_REDIS=''
  LAR_BIND_MAILPIT=''

  LAR_CONFIG_SEEN='|'
}

lar_config_seen_add() {
  item=$1
  case "$LAR_CONFIG_SEEN" in
    *"|$item|"*)
      return 1
      ;;
  esac
  LAR_CONFIG_SEEN="${LAR_CONFIG_SEEN}${item}|"
  return 0
}

lar_config_parse_port() {
  value=$1
  file=$2
  line=$3
  case "$value" in
    ''|*[!0-9]*)
      lar_config_fail "$file" "$line" "the port must be a number between 1 and 65535"
      ;;
    0*)
      lar_config_fail "$file" "$line" "the port cannot be 0 or have leading zeros"
      ;;
  esac
  if [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
    lar_config_fail "$file" "$line" "the port must be between 1 and 65535"
  fi
  LAR_PARSED_VALUE=$value
}

lar_config_parse_bool() {
  value=$1
  file=$2
  line=$3
  case "$value" in
    true|false)
      LAR_PARSED_VALUE=$value
      ;;
    *)
      lar_config_fail "$file" "$line" "the value must be true or false"
      ;;
  esac
}

lar_config_parse_bind() {
  value=$1
  file=$2
  line=$3
  case "$value" in
    local|lan)
      LAR_PARSED_VALUE=$value
      ;;
    *)
      lar_config_fail "$file" "$line" "the bind must be local or lan"
      ;;
  esac
}

lar_config_unquote() {
  value=$1
  case "$value" in
    \"*\")
      value=${value#\"}
      value=${value%\"}
      ;;
    \'*\')
      value=${value#\'}
      value=${value%\'}
      ;;
  esac
  LAR_PARSED_VALUE=$value
}

lar_config_assign() {
  section=$1
  key=$2
  value=$3
  file=$4
  line=$5

  case "$section" in
    root)
      case "$key" in
        timezone)
          LAR_TIMEZONE=$value
          ;;
        default_bind)
          lar_config_parse_bind "$value" "$file" "$line"
          LAR_DEFAULT_BIND=$LAR_PARSED_VALUE
          ;;
        *)
          lar_config_fail "$file" "$line" "unknown key: $key"
          ;;
      esac
      ;;
    ports)
      lar_config_parse_port "$value" "$file" "$line"
      case "$key" in
        http) LAR_PORT_HTTP=$LAR_PARSED_VALUE ;;
        https) LAR_PORT_HTTPS=$LAR_PARSED_VALUE ;;
        mysql57) LAR_PORT_MYSQL57=$LAR_PARSED_VALUE ;;
        mysql8) LAR_PORT_MYSQL8=$LAR_PARSED_VALUE ;;
        mariadb1011) LAR_PORT_MARIADB1011=$LAR_PARSED_VALUE ;;
        mariadb101) LAR_PORT_MARIADB101=$LAR_PARSED_VALUE ;;
        elasticsearch) LAR_PORT_ELASTICSEARCH=$LAR_PARSED_VALUE ;;
        elasticsearch_transport) LAR_PORT_ELASTICSEARCH_TRANSPORT=$LAR_PARSED_VALUE ;;
        minio) LAR_PORT_MINIO=$LAR_PARSED_VALUE ;;
        minio_console) LAR_PORT_MINIO_CONSOLE=$LAR_PARSED_VALUE ;;
        redis) LAR_PORT_REDIS=$LAR_PARSED_VALUE ;;
        mailpit_smtp) LAR_PORT_MAILPIT_SMTP=$LAR_PARSED_VALUE ;;
        mailpit_web) LAR_PORT_MAILPIT_WEB=$LAR_PARSED_VALUE ;;
        *)
          lar_config_fail "$file" "$line" "unknown port: $key"
          ;;
      esac
      ;;
    services)
      lar_config_parse_bool "$value" "$file" "$line"
      case "$key" in
        proxy) LAR_SERVICE_PROXY=$LAR_PARSED_VALUE ;;
        apache) LAR_SERVICE_APACHE=$LAR_PARSED_VALUE ;;
        nginx) LAR_SERVICE_NGINX=$LAR_PARSED_VALUE ;;
        php) LAR_SERVICE_PHP=$LAR_PARSED_VALUE ;;
        mysql57) LAR_SERVICE_MYSQL57=$LAR_PARSED_VALUE ;;
        mysql8) LAR_SERVICE_MYSQL8=$LAR_PARSED_VALUE ;;
        mariadb1011) LAR_SERVICE_MARIADB1011=$LAR_PARSED_VALUE ;;
        mariadb101) LAR_SERVICE_MARIADB101=$LAR_PARSED_VALUE ;;
        elasticsearch) LAR_SERVICE_ELASTICSEARCH=$LAR_PARSED_VALUE ;;
        minio) LAR_SERVICE_MINIO=$LAR_PARSED_VALUE ;;
        redis) LAR_SERVICE_REDIS=$LAR_PARSED_VALUE ;;
        mailpit) LAR_SERVICE_MAILPIT=$LAR_PARSED_VALUE ;;
        *)
          lar_config_fail "$file" "$line" "unknown service: $key"
          ;;
      esac
      ;;
    binds)
      lar_config_parse_bind "$value" "$file" "$line"
      case "$key" in
        http) LAR_BIND_HTTP=$LAR_PARSED_VALUE ;;
        https) LAR_BIND_HTTPS=$LAR_PARSED_VALUE ;;
        mysql57) LAR_BIND_MYSQL57=$LAR_PARSED_VALUE ;;
        mysql8) LAR_BIND_MYSQL8=$LAR_PARSED_VALUE ;;
        mariadb1011) LAR_BIND_MARIADB1011=$LAR_PARSED_VALUE ;;
        mariadb101) LAR_BIND_MARIADB101=$LAR_PARSED_VALUE ;;
        elasticsearch) LAR_BIND_ELASTICSEARCH=$LAR_PARSED_VALUE ;;
        minio) LAR_BIND_MINIO=$LAR_PARSED_VALUE ;;
        redis) LAR_BIND_REDIS=$LAR_PARSED_VALUE ;;
        mailpit) LAR_BIND_MAILPIT=$LAR_PARSED_VALUE ;;
        *)
          lar_config_fail "$file" "$line" "unknown bind: $key"
          ;;
      esac
      ;;
    *)
      lar_config_fail "$file" "$line" "unknown section: $section"
      ;;
  esac
}

lar_config_apply_binds() {
  [ -n "$LAR_BIND_HTTP" ] || LAR_BIND_HTTP=$LAR_DEFAULT_BIND
  [ -n "$LAR_BIND_HTTPS" ] || LAR_BIND_HTTPS=$LAR_BIND_HTTP
  [ -n "$LAR_BIND_MYSQL57" ] || LAR_BIND_MYSQL57=$LAR_DEFAULT_BIND
  [ -n "$LAR_BIND_MYSQL8" ] || LAR_BIND_MYSQL8=$LAR_DEFAULT_BIND
  [ -n "$LAR_BIND_MARIADB1011" ] || LAR_BIND_MARIADB1011=$LAR_DEFAULT_BIND
  [ -n "$LAR_BIND_MARIADB101" ] || LAR_BIND_MARIADB101=$LAR_DEFAULT_BIND
  [ -n "$LAR_BIND_ELASTICSEARCH" ] || LAR_BIND_ELASTICSEARCH=$LAR_DEFAULT_BIND
  [ -n "$LAR_BIND_MINIO" ] || LAR_BIND_MINIO=$LAR_DEFAULT_BIND
  [ -n "$LAR_BIND_REDIS" ] || LAR_BIND_REDIS=$LAR_DEFAULT_BIND
  [ -n "$LAR_BIND_MAILPIT" ] || LAR_BIND_MAILPIT=$LAR_DEFAULT_BIND
}

lar_config_validate() {
  file=$1
  case "$LAR_TIMEZONE" in
    ''|*[!A-Za-z0-9/_+-]*|*..*|/*|*/)
      lar_config_fail "$file" "-" "invalid timezone: $LAR_TIMEZONE"
      ;;
  esac

  seen_ports='|'
  for port in \
    "$LAR_PORT_HTTP" \
    "$LAR_PORT_HTTPS" \
    "$LAR_PORT_MYSQL57" \
    "$LAR_PORT_MYSQL8" \
    "$LAR_PORT_MARIADB1011" \
    "$LAR_PORT_MARIADB101" \
    "$LAR_PORT_ELASTICSEARCH" \
    "$LAR_PORT_ELASTICSEARCH_TRANSPORT" \
    "$LAR_PORT_MINIO" \
    "$LAR_PORT_MINIO_CONSOLE" \
    "$LAR_PORT_REDIS" \
    "$LAR_PORT_MAILPIT_SMTP" \
    "$LAR_PORT_MAILPIT_WEB"
  do
    case "$seen_ports" in
      *"|$port|"*)
        lar_config_fail "$file" "-" "port $port is repeated"
        ;;
    esac
    seen_ports="${seen_ports}${port}|"
  done
}

lar_config_load() {
  file=$1
  if [ ! -f "$file" ]; then
    lar_fail "Configuration file does not exist: $file"
  fi

  lar_config_defaults
  section=''
  line_no=0

  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    line=$(printf '%s' "$line" | tr -d '\r')
    case "$line" in
      *'	'*)
        lar_config_fail "$file" "$line_no" "use spaces instead of tabs"
        ;;
    esac

    trimmed=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$trimmed" in
      ''|'#'*)
        continue
        ;;
    esac
    trimmed=$(printf '%s' "$trimmed" | sed 's/[[:space:]]#.*$//')

    case "$line" in
      [[:space:]]*)
        nested=1
        ;;
      *)
        nested=0
        ;;
    esac

    case "$trimmed" in
      *:*)
        key=$(printf '%s' "$trimmed" | sed 's/:.*$//' | sed 's/[[:space:]]*$//')
        value=$(printf '%s' "$trimmed" | sed 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//')
        ;;
      *)
        lar_config_fail "$file" "$line_no" "unrecognized line"
        ;;
    esac

    case "$key" in
      ''|*[!a-z0-9_]*)
        lar_config_fail "$file" "$line_no" "invalid key: $key"
        ;;
    esac

    lar_config_unquote "$value"
    value=$LAR_PARSED_VALUE

    if [ -z "$value" ]; then
      if [ "$nested" -eq 1 ]; then
        lar_config_fail "$file" "$line_no" "the section must be in the first column"
      fi
      case "$key" in
        ports|services|binds)
          section=$key
          ;;
        *)
          lar_config_fail "$file" "$line_no" "missing value for $key"
          ;;
      esac
      continue
    fi

    if [ "$nested" -eq 0 ]; then
      section=''
      target=root
    else
      if [ -z "$section" ]; then
        lar_config_fail "$file" "$line_no" "the key is inside a section that does not exist"
      fi
      target=$section
    fi

    if ! lar_config_seen_add "$target.$key"; then
      lar_config_fail "$file" "$line_no" "duplicate key: $key"
    fi

    lar_config_assign "$target" "$key" "$value" "$file" "$line_no"
  done < "$file"

  lar_config_apply_binds
  lar_config_validate "$file"
}
