#!/bin/sh
# Reads sites.yaml and the Apache VirtualHosts. Included from lar.sh.

if [ "${0##*/}" = "sites.sh" ]; then
  printf '%s\n' "This file is loaded from ./lar.sh" >&2
  exit 1
fi

lar_php_base_port() {
  base_wanted=$1
  LAR_SITE_PORT=''
  while read -r base_version base_listen; do
    case "$base_version" in
      ''|\#*)
        continue
        ;;
    esac
    if [ "$base_version" = "$base_wanted" ]; then
      LAR_SITE_PORT=$base_listen
      return 0
    fi
  done < "$LAR_ROOT/core/php/versions"
  return 1
}

lar_sites_reset() {
  LAR_SITE_NAMES=''
  LAR_SITE_DOMAINS=''
  LAR_SITE_MANIFEST=$LAR_ROOT/data/.sites.manifest
  LAR_SITE_MOUNTS=$LAR_ROOT/data/.site-mounts
  LAR_SITE_OVERRIDES=$LAR_ROOT/data/.site-overrides
  rm -f "$LAR_SITE_MANIFEST" "$LAR_SITE_MOUNTS" "$LAR_SITE_OVERRIDES"
}

lar_sites_add_name() {
  name=$1
  case " $LAR_SITE_NAMES " in
    *" $name "*)
      return 1
      ;;
  esac
  LAR_SITE_NAMES="$LAR_SITE_NAMES $name"
  return 0
}

lar_sites_add_mount() {
  mount_service=$1
  mount_path=$2
  mount_target=${3:-$mount_path}
  mount_line=$(printf '%s\t%s\t%s' "$mount_service" "$mount_path" "$mount_target")
  if [ -f "$LAR_SITE_MOUNTS" ] && grep -F -x "$mount_line" "$LAR_SITE_MOUNTS" >/dev/null 2>&1; then
    return 0
  fi
  printf '%s\n' "$mount_line" >> "$LAR_SITE_MOUNTS"
}

lar_sites_add_override() {
  override_site=$1
  override_key=$2
  override_value=$3
  if [ -z "$override_value" ]; then
    lar_config_fail "$file" "$line_no" "missing value for $override_key"
  fi
  case "$override_value" in
    *'"'*|*"'"*|*'#'*|*'['*|*'	'*)
      lar_config_fail "$file" "$line_no" "invalid value for $override_key"
      ;;
  esac
  if [ -f "$LAR_SITE_OVERRIDES" ] && awk -F '	' -v s="$override_site" -v k="$override_key" '$1 == s && $2 == k { found = 1 } END { exit found ? 0 : 1 }' "$LAR_SITE_OVERRIDES"; then
    lar_config_fail "$file" "$line_no" "repeated directive: $override_key"
  fi
  printf '%s\t%s\t%s\n' "$override_site" "$override_key" "$override_value" >> "$LAR_SITE_OVERRIDES"
}

lar_php_ini_file() {
  version=$1
  if [ -s "$LAR_ROOT/data/config/php/$version/php.ini" ]; then
    printf '%s\n' "$LAR_ROOT/data/config/php/$version/php.ini"
    return 0
  fi
  printf '%s\n' "$LAR_ROOT/core/php/$version/php.ini"
}

lar_ini_has() {
  ini=$1
  directive=$2
  awk -v wanted="$directive" '
    {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*=.*/, "", line)
      if (line == wanted) {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  ' "$ini"
}

lar_take_port() {
  LAR_PORT_POOL=$((LAR_PORT_POOL + 1))
  LAR_SITE_PORT=$LAR_PORT_POOL
}

lar_sites_check_overrides() {
  check_name=$1
  check_php=$2
  check_ini=$(lar_php_ini_file "$check_php")
  if [ ! -f "$check_ini" ]; then
    lar_fail "No ini for PHP $check_php."
  fi
  if [ ! -f "$LAR_SITE_OVERRIDES" ]; then
    return 0
  fi
  while IFS='	' read -r override_site override_key override_value; do
    if [ "$override_site" != "$check_name" ] || [ "$override_key" = "xdebug" ]; then
      continue
    fi
    if ! lar_ini_has "$check_ini" "$override_key"; then
      lar_fail "Site $check_name defines $override_key and that directive is not in the PHP $check_php ini."
    fi
  done < "$LAR_SITE_OVERRIDES"
}

lar_sites_xdebug_mode() {
  case "$1" in
    true|debug)
      LAR_XDEBUG_MODE=debug
      ;;
    false)
      LAR_XDEBUG_MODE=off
      ;;
    coverage)
      LAR_XDEBUG_MODE=coverage
      ;;
    debug,coverage|coverage,debug)
      LAR_XDEBUG_MODE=debug,coverage
      ;;
    *)
      return 1
      ;;
  esac
}

lar_sites_xdebug_lines() {
  xdebug_name=$1
  xdebug_php=$2
  xdebug_value=$(awk -F '	' -v site_name="$xdebug_name" '$1 == site_name && $2 == "xdebug" { print $3 }' "$LAR_SITE_OVERRIDES")
  if [ -z "$xdebug_value" ]; then
    return 0
  fi
  if ! lar_sites_xdebug_mode "$xdebug_value"; then
    lar_fail "invalid xdebug for $xdebug_name: $xdebug_value"
  fi
  case "$xdebug_php" in
    5.6|7.0|7.1)
      case "$LAR_XDEBUG_MODE" in
        debug|debug,coverage)
          printf '%s\n' "php_admin_value[xdebug.remote_enable] = 1"
          printf '%s\n' "php_admin_value[xdebug.remote_autostart] = 1"
          printf '%s\n' "php_admin_value[xdebug.remote_host] = host.docker.internal"
          printf '%s\n' "php_admin_value[xdebug.remote_port] = 9003"
          ;;
        *)
          printf '%s\n' "php_admin_value[xdebug.remote_enable] = 0"
          printf '%s\n' "php_admin_value[xdebug.remote_autostart] = 0"
          ;;
      esac
      case "$LAR_XDEBUG_MODE" in
        coverage|debug,coverage)
          printf '%s\n' "php_admin_value[xdebug.coverage_enable] = 1"
          ;;
      esac
      ;;
    *)
      # Xdebug reads the mode when the worker starts. php_admin_value arrives too late; the environment variable does not.
      # FPM treats "off" as empty, so that case has no env line.
      if [ "$LAR_XDEBUG_MODE" != "off" ]; then
        printf '%s\n' "env[XDEBUG_MODE] = $LAR_XDEBUG_MODE"
      fi
      printf '%s\n' "php_admin_value[xdebug.mode] = $LAR_XDEBUG_MODE"
      case "$LAR_XDEBUG_MODE" in
        debug|debug,coverage)
          printf '%s\n' "php_admin_value[xdebug.start_with_request] = yes"
          printf '%s\n' "php_admin_value[xdebug.client_host] = host.docker.internal"
          printf '%s\n' "php_admin_value[xdebug.client_port] = 9003"
          ;;
        coverage)
          # The global ini sets start_with_request=no. default starts coverage and not the debugger.
          printf '%s\n' "php_admin_value[xdebug.start_with_request] = default"
          ;;
      esac
      ;;
  esac
}

lar_sites_write_pool() {
  pool_name=$1
  pool_php=$2
  pool_port=$3
  pool_dir=$LAR_ROOT/data/config/php/$pool_php/fpm
  mkdir -p "$pool_dir"
  pool_file=$pool_dir/$pool_name.conf
  {
    printf '%s\n' "; Generated by ./lar.sh. Recreated from sites.yaml."
    printf '%s\n' "[$pool_name]"
    printf '%s\n' "user = web"
    printf '%s\n' "group = web"
    printf '%s\n' "listen = $pool_port"
    printf '%s\n' "pm = dynamic"
    printf '%s\n' "pm.max_children = 5"
    printf '%s\n' "pm.start_servers = 2"
    printf '%s\n' "pm.min_spare_servers = 1"
    printf '%s\n' "pm.max_spare_servers = 3"
    printf '%s\n' "clear_env = no"
    awk -F '	' -v site_name="$pool_name" '
      $1 == site_name && $2 != "xdebug" {
        value = $3
        if (value == "true") value = "On"
        if (value == "false") value = "Off"
        print "php_admin_value[" $2 "] = " value
      }
    ' "$LAR_SITE_OVERRIDES"
    if ! awk -F '	' -v site_name="$pool_name" '$1 == site_name && $2 == "error_log" { found = 1 } END { exit found ? 0 : 1 }' "$LAR_SITE_OVERRIDES"; then
      printf '%s\n' "php_admin_value[error_log] = /var/log/php/${pool_name}-error.log"
    fi
    lar_sites_xdebug_lines "$pool_name" "$pool_php"
  } > "$pool_file"
  LAR_SITE_POOL=$pool_file
}

lar_sites_clear_pools() {
  while read -r version base_listen; do
    case "$version" in
      ''|\#*)
        continue
        ;;
    esac
    pool_dir=$LAR_ROOT/data/config/php/$version/fpm
    if [ ! -d "$pool_dir" ]; then
      continue
    fi
    for conf in "$pool_dir"/*.conf; do
      if [ ! -f "$conf" ]; then
        continue
      fi
      first=$(sed -n '1p' "$conf")
      case "$first" in
        "; Generated by ./lar.sh. Recreated from sites.yaml.")
          rm -f "$conf"
          ;;
      esac
    done
  done < "$LAR_ROOT/core/php/versions"
}

lar_site_realpath() {
  real_name=$1
  real_path=$2
  case "$real_path" in
    /*) ;;
    *) lar_fail "The path of $real_name must be absolute: $real_path" ;;
  esac
  case "$real_path" in
    *'"'*|*'	'*)
      lar_fail "Invalid path for $real_name: $real_path"
      ;;
  esac
  if [ ! -d "$real_path" ]; then
    lar_fail "Site directory does not exist for $real_name: $real_path"
  fi
  real_resolved=$(CDPATH= cd -- "$real_path" && pwd -P) || lar_fail "Cannot resolve the path of $real_name: $real_path"
  case "$real_resolved" in
    /)
      lar_fail "The path of $real_name cannot be /."
      ;;
  esac
  LAR_SITE_PATH=$real_resolved
}

lar_sites_configured_paths() {
  file=$LAR_ROOT/data/config/sites.yaml
  if [ ! -f "$file" ]; then
    return 0
  fi
  sed -n -e 's/^    path:[[:space:]]*//p' -e 's/^    public_path:[[:space:]]*//p' "$file" | while IFS= read -r value; do
    value=$(printf '%s' "$value" | sed 's/[[:space:]]#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$value" in
      \"*\") value=${value#\"}; value=${value%\"} ;;
      \'*\') value=${value#\'}; value=${value%\'} ;;
    esac
    case "$value" in
      /*) printf '%s\n' "$value" ;;
    esac
  done
}

lar_resolve_public() {
  pub_name=$1
  pub_root=$2
  pub_value=$3
  if [ -z "$pub_value" ]; then
    LAR_SITE_PUBLIC=$pub_root
    return 0
  fi
  case "$pub_value" in
    /*) pub_target=$pub_value ;;
    *) pub_target=$pub_root/$pub_value ;;
  esac
  case "$pub_target" in
    *'"'*|*'	'*)
      lar_fail "Invalid public_path for $pub_name."
      ;;
  esac
  if [ ! -d "$pub_target" ]; then
    lar_fail "public_path does not exist for $pub_name: $pub_target"
  fi
  pub_resolved=$(CDPATH= cd -- "$pub_target" && pwd -P) || lar_fail "Cannot resolve public_path of $pub_name: $pub_target"
  case "$pub_resolved" in
    /)
      lar_fail "public_path of $pub_name cannot be /."
      ;;
  esac
  LAR_SITE_PUBLIC=$pub_resolved
}

lar_site_body() {
  body_site=$1
  LAR_SITE_BODY=''
  if [ -f "$LAR_SITE_OVERRIDES" ]; then
    LAR_SITE_BODY=$(awk -F '	' -v site_name="$body_site" '$1 == site_name && $2 == "post_max_size" { print $3; exit }' "$LAR_SITE_OVERRIDES")
    if [ -z "$LAR_SITE_BODY" ]; then
      LAR_SITE_BODY=$(awk -F '	' -v site_name="$body_site" '$1 == site_name && $2 == "upload_max_filesize" { print $3; exit }' "$LAR_SITE_OVERRIDES")
    fi
  fi
  if [ -z "$LAR_SITE_BODY" ]; then
    LAR_SITE_BODY=64M
  fi
}

lar_body_bytes() {
  body=$1
  body_number=$(printf '%s' "$body" | tr -cd '0-9')
  case "$body" in
    *[Gg])
      LAR_BODY_BYTES=$((body_number * 1024 * 1024 * 1024))
      ;;
    *[Kk])
      LAR_BODY_BYTES=$((body_number * 1024))
      ;;
    *[Mm])
      LAR_BODY_BYTES=$((body_number * 1024 * 1024))
      ;;
    *[!0-9]*|'')
      LAR_BODY_BYTES=67108864
      ;;
    *)
      LAR_BODY_BYTES=$body_number
      ;;
  esac
  if [ -z "$body_number" ]; then
    LAR_BODY_BYTES=67108864
  fi
}

lar_sites_claim_host() {
  claim_host=$1
  case "$claim_host" in
    ''|-|.*|*.|*..*|*[!A-Za-z0-9.-]*)
      lar_fail "Invalid domain for $name: $claim_host"
      ;;
  esac
  case " $LAR_SITE_DOMAINS " in
    *" $claim_host "*)
      lar_fail "Domain $claim_host is repeated."
      ;;
  esac
  LAR_SITE_DOMAINS="$LAR_SITE_DOMAINS $claim_host"
}

lar_sites_take_alias() {
  alias_host=$1
  case "$alias_host" in
    ''|-|*[[:space:]]*|.*|*.|*..*|*[!A-Za-z0-9.-]*)
      lar_config_fail "$file" "$line_no" "invalid alias: $alias_host"
      ;;
  esac
  case " $site_alias " in
    *" $alias_host "*)
      lar_config_fail "$file" "$line_no" "repeated alias: $alias_host"
      ;;
  esac
  site_alias="$site_alias $alias_host"
}

lar_sites_write_apache() {
  conf_name=$1
  conf_domain=$2
  conf_path=$3
  conf_port=$4
  conf_alias=$5
  alias_line=''
  if [ -n "$conf_alias" ]; then
    alias_line="    ServerAlias ${conf_alias}
"
  fi
  lar_site_body "$conf_name"
  lar_body_bytes "$LAR_SITE_BODY"
  conf_dest=$LAR_ROOT/data/config/sites/$conf_name.conf
  if [ -n "$conf_port" ]; then
    cat > "$conf_dest" <<EOF
# Generated by ./lar.sh. Recreated from sites.yaml.
<VirtualHost *:80>
    ServerName ${conf_domain}
${alias_line}    DocumentRoot "${conf_path}"
    LimitRequestBody ${LAR_BODY_BYTES}
    <Directory "${conf_path}">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.php index.html
        <FilesMatch \\.php$>
            SetHandler "proxy:fcgi://php:${conf_port}"
        </FilesMatch>
    </Directory>
    SetEnvIf X-Forwarded-Proto "^https$" HTTPS=on
    ErrorLog /var/log/apache2/${conf_name}-error.log
    CustomLog /var/log/apache2/${conf_name}-access.log combined
</VirtualHost>
EOF
    return 0
  fi
  cat > "$conf_dest" <<EOF
# Generated by ./lar.sh. Recreated from sites.yaml.
<VirtualHost *:80>
    ServerName ${conf_domain}
${alias_line}    DocumentRoot "${conf_path}"
    LimitRequestBody ${LAR_BODY_BYTES}
    <Directory "${conf_path}">
        Options FollowSymLinks
        AllowOverride All
        Require all granted
        DirectoryIndex index.html
    </Directory>
    SetEnvIf X-Forwarded-Proto "^https$" HTTPS=on
    ErrorLog /var/log/apache2/${conf_name}-error.log
    CustomLog /var/log/apache2/${conf_name}-access.log combined
</VirtualHost>
EOF
}

lar_sites_write_nginx() {
  conf_name=$1
  conf_domain=$2
  conf_path=$3
  conf_port=$4
  conf_alias=$5
  names=$conf_domain
  if [ -n "$conf_alias" ]; then
    names="$conf_domain $conf_alias"
  fi
  lar_site_body "$conf_name"
  conf_dest=$LAR_ROOT/data/config/nginx/$conf_name.conf
  if [ -n "$conf_port" ]; then
    cat > "$conf_dest" <<EOF
# Generated by ./lar.sh. Recreated from sites.yaml.
server {
    listen 80;
    server_name ${names};
    access_log /var/log/nginx/${conf_name}-access.log;
    error_log /var/log/nginx/${conf_name}-error.log warn;
    root "${conf_path}";
    index index.php index.html;
    client_max_body_size ${LAR_SITE_BODY};
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \\.php\$ {
        try_files \$uri =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTPS \$lar_https if_not_empty;
        set \$lar_php php:${conf_port};
        fastcgi_pass \$lar_php;
    }
}
EOF
    return 0
  fi
  cat > "$conf_dest" <<EOF
# Generated by ./lar.sh. Recreated from sites.yaml.
server {
    listen 80;
    server_name ${names};
    access_log /var/log/nginx/${conf_name}-access.log;
    error_log /var/log/nginx/${conf_name}-error.log warn;
    root "${conf_path}";
    index index.html;
    client_max_body_size ${LAR_SITE_BODY};
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
}

lar_sites_cert_ensure() {
  cert_name=$1
  cert_names=$2
  if ! command -v openssl >/dev/null 2>&1; then
    lar_fail "openssl is required on the Mac to create the certificates."
  fi
  cert_dir=$LAR_ROOT/data/certs/$cert_name
  mkdir -p "$cert_dir"
  cert_stamp=$(printf '%s' "$cert_names" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ *$//')
  if [ -s "$cert_dir/cert.pem" ] && [ -s "$cert_dir/key.pem" ] && [ -f "$cert_dir/names" ]; then
    cert_current=$(sed -n '1p' "$cert_dir/names")
    if [ "$cert_current" = "$cert_stamp" ]; then
      return 0
    fi
  fi
  cert_cn=$(printf '%s' "$cert_names" | awk '{ print $1 }')
  cert_san=''
  for cert_host in $cert_names; do
    cert_san="${cert_san}DNS:${cert_host},"
  done
  cert_san=${cert_san%,}
  cert_conf=$(mktemp)
  cat > "$cert_conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${cert_cn}
[ext]
subjectAltName = ${cert_san}
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF
  openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
    -keyout "$cert_dir/key.pem" -out "$cert_dir/cert.pem" \
    -config "$cert_conf" >/dev/null 2>&1 \
    || lar_fail "Could not create the certificate for $cert_name."
  rm -f "$cert_conf"
  printf '%s\n' "$cert_stamp" > "$cert_dir/names"
  chmod 644 "$cert_dir/cert.pem" "$cert_dir/key.pem"
}

lar_sites_write_https_map() {
  cat > "$LAR_ROOT/data/config/nginx/00-https.conf" <<'EOF'
# Generated by ./lar.sh. Recreated from sites.yaml.
map $http_x_forwarded_proto $lar_https {
    default "";
    https   on;
}
EOF
}

lar_sites_write_proxy_tls_default() {
  lar_sites_cert_ensure _default localhost
  cat > "$LAR_ROOT/data/config/proxy/00-default.conf" <<'EOF'
# Generated by ./lar.sh. Recreated from sites.yaml.
server {
    listen 80 default_server;
    server_name _;
    return 404;
}

server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/nginx/lar-certs/_default/cert.pem;
    ssl_certificate_key /etc/nginx/lar-certs/_default/key.pem;
    return 404;
}
EOF
}

lar_sites_write_proxy() {
  conf_name=$1
  conf_domain=$2
  conf_server=$3
  conf_alias=$4
  conf_https=$5
  names=$conf_domain
  if [ -n "$conf_alias" ]; then
    names="$conf_domain $conf_alias"
  fi
  ssl_lines=''
  if [ "$conf_https" = "true" ]; then
    ssl_lines="    listen 443 ssl;
    ssl_certificate /etc/nginx/lar-certs/${conf_name}/cert.pem;
    ssl_certificate_key /etc/nginx/lar-certs/${conf_name}/key.pem;
"
  fi
  lar_site_body "$conf_name"
  conf_dest=$LAR_ROOT/data/config/proxy/$conf_name.conf
  cat > "$conf_dest" <<EOF
# Generated by ./lar.sh. Recreated from sites.yaml.
server {
    listen 80;
${ssl_lines}    server_name ${names};
    access_log /var/log/nginx/${conf_name}-access.log;
    error_log /var/log/nginx/${conf_name}-error.log warn;
    client_max_body_size ${LAR_SITE_BODY};
    location / {
        set \$lar_upstream ${conf_server};
        proxy_pass http://\$lar_upstream:80;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header Connection "";
    }
}
EOF
}

lar_sites_write_edge_default() {
  edge_dir=$1
  mkdir -p "$edge_dir"
  cat > "$edge_dir/00-default.conf" <<'EOF'
# Generated by ./lar.sh. Recreated from sites.yaml.
server {
    listen 80 default_server;
    server_name _;
    return 404;
}
EOF
}

lar_sites_clear_generated() {
  dir=$1
  if [ ! -d "$dir" ]; then
    return 0
  fi
  for conf in "$dir"/*.conf; do
    if [ ! -f "$conf" ]; then
      continue
    fi
    first=$(sed -n '1p' "$conf")
    case "$first" in
      "# Generated by ./lar.sh. Recreated from sites.yaml.")
        rm -f "$conf"
        ;;
    esac
  done
}

lar_sites_drop_overrides() {
  drop_name=$1
  if [ ! -f "$LAR_SITE_OVERRIDES" ]; then
    return 0
  fi
  drop_tmp=$(mktemp)
  awk -F '	' -v site_name="$drop_name" '$1 != site_name' "$LAR_SITE_OVERRIDES" > "$drop_tmp"
  mv "$drop_tmp" "$LAR_SITE_OVERRIDES"
}

lar_sites_flush() {
  if [ -z "$site" ]; then
    return 0
  fi
  if [ -z "$site_domain" ] || [ -z "$site_path" ]; then
    lar_fail "$file: site $site is missing domain or path."
  fi
  if [ -z "$site_server" ]; then
    site_server=apache
  fi
  if [ -z "$site_php" ]; then
    lar_sites_drop_overrides "$site"
    site_php='-'
  fi
  if [ -z "$site_public" ]; then
    site_public='-'
  fi
  if [ -z "$site_node" ]; then
    site_node='-'
  fi
  site_alias=${site_alias# }
  for alias_host in $site_alias; do
    if [ "$alias_host" = "$site_domain" ]; then
      lar_fail "$file: alias $alias_host is the same as the domain of $site."
    fi
  done
  if [ "$site_list" = "alias" ] && [ -z "$site_alias" ]; then
    lar_fail "$file: alias of $site has no domain."
  fi
  if [ -z "$site_alias" ]; then
    site_alias='-'
  fi
  if [ -z "$site_https" ]; then
    site_https=false
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$site" "$site_domain" "$site_path" "$site_public" "$site_php" "$site_server" "$site_node" "$site_enabled" "$site_alias" "$site_https" >> "$LAR_SITE_MANIFEST"
  site=''
  site_domain=''
  site_path=''
  site_public=''
  site_php=''
  site_server=apache
  site_node=''
  site_alias=''
  site_list=''
  site_enabled=true
  site_https=false
}

lar_sites_parse() {
  section=''
  site=''
  site_domain=''
  site_path=''
  site_public=''
  site_php=''
  site_server=apache
  site_node=''
  site_alias=''
  site_list=''
  site_enabled=true
  site_https=false
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
    leading=${line%%[! ]*}
    indent=${#leading}

    if [ "$indent" -eq 6 ]; then
      if [ "$section" != "sites" ] || [ -z "$site" ] || [ "$site_list" != "alias" ]; then
        lar_config_fail "$file" "$line_no" "the list only goes under alias"
      fi
      case "$trimmed" in
        -*) ;;
        *)
          lar_config_fail "$file" "$line_no" "each alias goes on a line that starts with -"
          ;;
      esac
      alias_item=$(printf '%s' "$trimmed" | sed 's/^-[[:space:]]*//')
      if [ -z "$alias_item" ]; then
        lar_config_fail "$file" "$line_no" "empty alias"
      fi
      lar_config_unquote "$alias_item"
      lar_sites_take_alias "$LAR_PARSED_VALUE"
      continue
    fi

    case "$trimmed" in
      *:*)
        key=$(printf '%s' "$trimmed" | sed 's/:[[:space:]].*$//; s/:$//')
        value=$(printf '%s' "$trimmed" | sed 's/^.*:[[:space:]]*//; s/:$//')
        if [ "$key" = "$trimmed" ]; then
          value=''
        fi
        ;;
      *)
        lar_config_fail "$file" "$line_no" "unrecognized line"
        ;;
    esac
    case "$key" in
      ''|*[!a-z0-9_.]*)
        lar_config_fail "$file" "$line_no" "invalid key: $key"
        ;;
    esac
    lar_config_unquote "$value"
    value=$LAR_PARSED_VALUE

    if [ "$indent" -eq 0 ]; then
      lar_sites_flush
      if [ "$key" != "sites" ]; then
        lar_config_fail "$file" "$line_no" "unknown key: $key"
      fi
      case "$value" in
        ''|'[]')
          section=sites
          ;;
        *)
          lar_config_fail "$file" "$line_no" "sites does not take a value on the same line"
          ;;
      esac
      continue
    fi

    if [ "$section" != "sites" ]; then
      lar_config_fail "$file" "$line_no" "the key is outside sites"
    fi

    if [ "$indent" -eq 2 ]; then
      lar_sites_flush
      case "$key" in
        *.*)
          lar_config_fail "$file" "$line_no" "invalid key: $key"
          ;;
      esac
      if [ -n "$value" ]; then
        lar_config_fail "$file" "$line_no" "site $key does not take a value on the same line"
      fi
      if ! lar_sites_add_name "$key"; then
        lar_config_fail "$file" "$line_no" "duplicate site: $key"
      fi
      site=$key
      site_server=apache
      site_public=''
      site_node=''
      site_alias=''
      site_list=''
      site_https=false
      continue
    fi

    if [ "$indent" -ne 4 ] || [ -z "$site" ]; then
      lar_config_fail "$file" "$line_no" "domain, path, public_path, php, server, node, alias, https, and ini directives go at the same level"
    fi
    if [ "$key" != "alias" ]; then
      if [ "$site_list" = "alias" ] && [ -z "${site_alias# }" ]; then
        lar_config_fail "$file" "$line_no" "alias has no domain"
      fi
      site_list=''
    fi
    case "$key" in
      domain) site_domain=$value ;;
      alias)
        if [ -n "$site_alias" ] || [ "$site_list" = "alias" ]; then
          lar_config_fail "$file" "$line_no" "alias is repeated"
        fi
        if [ -n "$value" ]; then
          lar_sites_take_alias "$value"
        else
          site_list=alias
        fi
        ;;
      path) site_path=$value ;;
      public_path)
        if [ -z "$value" ]; then
          lar_config_fail "$file" "$line_no" "public_path cannot be empty"
        fi
        case "$value" in
          *'"'*|*'	'*|-)
            lar_config_fail "$file" "$line_no" "public_path does not allow quotes or tabs"
            ;;
        esac
        site_public=$value
        ;;
      php)
        if [ -z "$value" ]; then
          lar_config_fail "$file" "$line_no" "php must be the version, for example \"5.6\""
        fi
        site_php=$value
        ;;
      server)
        case "$value" in
          apache|nginx) site_server=$value ;;
          *) lar_config_fail "$file" "$line_no" "server must be apache or nginx" ;;
        esac
        ;;
      node)
        case "$value" in
          ''|*[!0-9.]*|.*|*.|*..*|-)
            lar_config_fail "$file" "$line_no" "node must be a version, for example \"20\" or \"14.15.0\""
            ;;
        esac
        node_dots=$(printf '%s' "$value" | tr -cd '.')
        if [ "${#node_dots}" -gt 2 ]; then
          lar_config_fail "$file" "$line_no" "node must be a version, for example \"20\" or \"14.15.0\""
        fi
        site_node=$value
        ;;
      enabled)
        case "$value" in
          true|false) site_enabled=$value ;;
          *) lar_config_fail "$file" "$line_no" "enabled must be true or false" ;;
        esac
        ;;
      https)
        case "$value" in
          true|false) site_https=$value ;;
          *) lar_config_fail "$file" "$line_no" "https must be true or false" ;;
        esac
        ;;
      xdebug)
        if ! lar_sites_xdebug_mode "$value"; then
          lar_config_fail "$file" "$line_no" "xdebug must be false, true, coverage, or debug,coverage"
        fi
        lar_sites_add_override "$site" "xdebug" "$value"
        ;;
      *)
        lar_sites_add_override "$site" "$key" "$value"
        ;;
    esac
  done < "$file"
  lar_sites_flush
}

lar_sites_prepare() {
  file=$LAR_ROOT/data/config/sites.yaml
  lar_sites_reset
  if [ ! -f "$file" ]; then
    lar_fail "Missing data/config/sites.yaml. Run ./lar.sh init."
  fi
  lar_sites_parse

  lar_sites_clear_generated "$LAR_ROOT/data/config/sites"
  lar_sites_clear_generated "$LAR_ROOT/data/config/nginx"
  lar_sites_clear_generated "$LAR_ROOT/data/config/proxy"
  lar_sites_clear_pools
  mkdir -p "$LAR_ROOT/data/config/nginx" "$LAR_ROOT/data/config/proxy"
  lar_sites_write_edge_default "$LAR_ROOT/data/config/nginx"
  lar_sites_write_https_map
  lar_sites_write_edge_default "$LAR_ROOT/data/config/proxy"
  LAR_HTTPS_SITES=0
  if [ ! -s "$LAR_SITE_MANIFEST" ]; then
    rm -f "$LAR_SITE_MANIFEST"
    printf '%s\n' "  sites: none"
    return 0
  fi

  LAR_PORT_POOL=9100

  while IFS='	' read -r name domain path public php server node enabled aliases https; do
    if [ "$public" = "-" ]; then
      public=''
    fi
    if [ "$php" = "-" ]; then
      php=''
    fi
    if [ "$node" = "-" ]; then
      node=''
    fi
    if [ "$aliases" = "-" ]; then
      aliases=''
    fi
    if [ "$https" != "true" ]; then
      https=false
    fi
    port=''
    if [ -n "$php" ]; then
      if ! lar_php_base_port "$php"; then
        lar_fail "Invalid PHP version for $name: $php"
      fi
      port=$LAR_SITE_PORT
    fi
    if [ "$enabled" != "true" ]; then
      continue
    fi
    lar_site_realpath "$name" "$path"
    path=$LAR_SITE_PATH
    lar_resolve_public "$name" "$path" "$public"
    if [ -n "$php" ] && ! lar_service_enabled php; then
      lar_fail "Site $name uses PHP $php and the php service is disabled in settings.yaml."
    fi
    if ! lar_service_enabled "$server"; then
      lar_fail "Site $name uses $server and that service is disabled in settings.yaml."
    fi
    lar_sites_claim_host "$domain"
    for alias_host in $aliases; do
      lar_sites_claim_host "$alias_host"
    done
    lar_sites_add_mount "$server" "$path"
    lar_sites_add_mount php "$path"
    case "$LAR_SITE_PUBLIC/" in
      "$path/"*) ;;
      *)
        lar_sites_add_mount "$server" "$LAR_SITE_PUBLIC"
        lar_sites_add_mount php "$LAR_SITE_PUBLIC"
        ;;
    esac
    if [ -n "$php" ]; then
      if [ -f "$LAR_SITE_OVERRIDES" ] && awk -F '	' -v site_name="$name" '$1 == site_name { found = 1 } END { exit found ? 0 : 1 }' "$LAR_SITE_OVERRIDES"; then
        lar_sites_check_overrides "$name" "$php"
      fi
      lar_take_port
      port=$LAR_SITE_PORT
      lar_sites_write_pool "$name" "$php" "$port"
    fi
    case "$server" in
      apache)
        lar_sites_write_apache "$name" "$domain" "$LAR_SITE_PUBLIC" "$port" "$aliases"
        ;;
      nginx)
        lar_sites_write_nginx "$name" "$domain" "$LAR_SITE_PUBLIC" "$port" "$aliases"
        ;;
    esac
    if [ "$https" = "true" ]; then
      cert_names=$domain
      if [ -n "$aliases" ]; then
        cert_names="$domain $aliases"
      fi
      lar_sites_cert_ensure "$name" "$cert_names"
      LAR_HTTPS_SITES=1
    fi
    lar_sites_write_proxy "$name" "$domain" "$server" "$aliases" "$https"
    site_note=''
    if [ -n "$php" ]; then
      site_note="$site_note, PHP $php"
    fi
    if [ -n "$node" ]; then
      site_note="$site_note, node $node"
    fi
    if [ -n "$aliases" ]; then
      site_note="$site_note, alias $aliases"
    fi
    if [ "$https" = "true" ]; then
      site_note="$site_note, https"
    fi
    if [ "$LAR_SITE_PUBLIC" != "$path" ]; then
      site_note="$site_note, public $LAR_SITE_PUBLIC"
    fi
    printf '%s\n' "  site $domain → $path ($server$site_note)"
  done < "$LAR_SITE_MANIFEST"
  rm -f "$LAR_SITE_MANIFEST"
  if [ "$LAR_HTTPS_SITES" = 1 ]; then
    lar_sites_write_proxy_tls_default
  fi
}

lar_sites_hosts_render() {
  hosts_file=$1
  dest=$2
  mode=$3
  names=$(printf '%s' "${LAR_SITE_DOMAINS-}" | sed 's/^ *//; s/ *$//')
  block=$(mktemp)
  if [ "$mode" = "apply" ] && [ -n "$names" ]; then
    printf '%s\n' '#LAR-SITES-START' "127.0.0.1 $names" '#LAR-SITES-END' > "$block"
  fi
  if [ -s "$block" ]; then
    status=0
    awk '
      NR == FNR { block = block $0 ORS; next }
      $0 == "#LAR-SITES-START" {
        if (inside) exit 2
        inside = 1
        next
      }
      $0 == "#LAR-SITES-END" {
        if (!inside) exit 2
        inside = 0
        replaced = 1
        printf "%s", block
        next
      }
      inside { next }
      { print }
      END {
        if (inside) exit 2
        if (!replaced) printf "%s", block
      }
    ' "$block" "$hosts_file" > "$dest" || status=$?
  else
    status=0
    awk '
      $0 == "#LAR-SITES-START" {
        if (inside) exit 2
        inside = 1
        next
      }
      $0 == "#LAR-SITES-END" {
        if (!inside) exit 2
        inside = 0
        next
      }
      inside { next }
      { print }
      END {
        if (inside) exit 2
      }
    ' "$hosts_file" > "$dest" || status=$?
  fi
  rm -f "$block"
  if [ "$status" -eq 2 ]; then
    rm -f "$dest"
    lar_fail "/etc/hosts has incomplete LAR-SITES markers."
  fi
  if [ "$status" -ne 0 ]; then
    rm -f "$dest"
    lar_fail "Could not prepare /etc/hosts."
  fi
}

lar_sites_hosts_install() {
  src=$1
  hosts_prompt=$2
  case "$(uname -s)" in
    Darwin)
      if ! osascript <<EOF
do shell script "cp '$src' /etc/hosts" with prompt "$hosts_prompt" with administrator privileges
EOF
      then
        rm -f "$src"
        lar_fail "/etc/hosts was not changed."
      fi
      ;;
    *)
      if [ -w /etc/hosts ]; then
        cp "$src" /etc/hosts
      else
        rm -f "$src"
        lar_fail "Cannot write /etc/hosts."
      fi
      ;;
  esac
  rm -f "$src"
}

lar_sites_hosts_sync() {
  if [ "$(uname -s)" != "Darwin" ]; then
    return 0
  fi
  if [ ! -r /etc/hosts ]; then
    lar_fail "Cannot read /etc/hosts."
  fi
  dest=$(mktemp)
  lar_sites_hosts_render /etc/hosts "$dest" apply
  if cmp -s /etc/hosts "$dest"; then
    rm -f "$dest"
    return 0
  fi
  lar_sites_hosts_install "$dest" "LAR wants to update /etc/hosts"
  printf '%s\n' "  /etc/hosts updated"
}

lar_sites_hosts_clear() {
  if [ "$(uname -s)" != "Darwin" ]; then
    return 0
  fi
  if [ ! -r /etc/hosts ]; then
    lar_fail "Cannot read /etc/hosts."
  fi
  if ! grep -q '^#LAR-SITES-START$' /etc/hosts; then
    return 0
  fi
  dest=$(mktemp)
  lar_sites_hosts_render /etc/hosts "$dest" remove
  if cmp -s /etc/hosts "$dest"; then
    rm -f "$dest"
    return 0
  fi
  lar_sites_hosts_install "$dest" "LAR wants to remove the domains from /etc/hosts"
  printf '%s\n' "  domains removed from /etc/hosts"
}

lar_sites_hosts_hint() {
  if [ -z "$LAR_SITE_DOMAINS" ]; then
    return 0
  fi
  missing=''
  for domain in $LAR_SITE_DOMAINS; do
    if [ -r /etc/hosts ] && grep -F -q "$domain" /etc/hosts; then
      continue
    fi
    missing="$missing $domain"
  done
  missing=$(printf '%s' "$missing" | sed 's/^ *//')
  if [ -z "$missing" ]; then
    return 0
  fi
  printf '%s\n' "Add this line to /etc/hosts to open the sites in the browser:"
  printf '%s\n' "  127.0.0.1 $missing"
}

lar_php_container_running() {
  running=$(docker inspect -f '{{.State.Running}}' lar-php 2>/dev/null || true)
  if [ "$running" != "true" ]; then
    lar_fail "The lar-php container is not running. Run ./lar.sh up."
  fi
}

lar_site_by_name() {
  wanted=$1
  LAR_MATCH_NAME=''
  LAR_MATCH_PHP=''
  LAR_MATCH_NODE=''
  LAR_MATCH_PATH=''
  file=$LAR_ROOT/data/config/sites.yaml
  if [ ! -f "$file" ]; then
    lar_fail "Missing data/config/sites.yaml. Run ./lar.sh init."
  fi
  LAR_SITE_NAMES=''
  LAR_SITE_MANIFEST=$(mktemp)
  LAR_SITE_OVERRIDES=$(mktemp)
  lar_sites_parse
  found=0
  if [ -s "$LAR_SITE_MANIFEST" ]; then
    while IFS='	' read -r name domain path public php server node enabled aliases https; do
      if [ "$name" != "$wanted" ]; then
        continue
      fi
      found=1
      if [ "$enabled" != "true" ]; then
        rm -f "$LAR_SITE_MANIFEST" "$LAR_SITE_OVERRIDES"
        lar_fail "Site $wanted is disabled."
      fi
      if [ "$public" = "-" ]; then
        public=''
      fi
      if [ "$php" = "-" ]; then
        php=''
      fi
      if [ "$node" = "-" ]; then
        node=''
      fi
      if [ ! -d "$path" ]; then
        rm -f "$LAR_SITE_MANIFEST" "$LAR_SITE_OVERRIDES"
        lar_fail "Folder does not exist for $wanted: $path"
      fi
      lar_site_realpath "$name" "$path"
      LAR_MATCH_NAME=$name
      LAR_MATCH_PHP=$php
      LAR_MATCH_NODE=$node
      LAR_MATCH_PATH=$LAR_SITE_PATH
    done < "$LAR_SITE_MANIFEST"
  fi
  rm -f "$LAR_SITE_MANIFEST" "$LAR_SITE_OVERRIDES"
  if [ "$found" -eq 0 ]; then
    lar_fail "Site $wanted does not exist."
  fi
}

lar_version_rank() {
  rank_version=$1
  rank_major=${rank_version%%.*}
  case "$rank_version" in
    *.*) rank_rest=${rank_version#*.} ;;
    *) rank_rest=0 ;;
  esac
  rank_minor=${rank_rest%%.*}
  case "$rank_rest" in
    *.*) rank_patch=${rank_rest#*.} ;;
    *) rank_patch=0 ;;
  esac
  rank_patch=${rank_patch%%.*}
  printf '%s\n' "$((rank_major * 1000000 + rank_minor * 1000 + rank_patch))"
}

lar_highest_listed() {
  list_file=$1
  LAR_HIGHEST_VERSION=''
  highest_rank=-1
  if [ ! -f "$list_file" ]; then
    return 0
  fi
  while read -r listed_version listed_extra; do
    case "$listed_version" in
      ''|\#*) continue ;;
    esac
    listed_rank=$(lar_version_rank "$listed_version")
    if [ "$listed_rank" -gt "$highest_rank" ]; then
      highest_rank=$listed_rank
      LAR_HIGHEST_VERSION=$listed_version
    fi
  done < "$list_file"
}

lar_list_restore() {
  if [ -n "${LAR_LIST_STTY:-}" ]; then
    stty "$LAR_LIST_STTY" </dev/tty 2>/dev/null || true
  fi
  printf '\033[?25h' >/dev/tty 2>/dev/null || true
}

lar_list_label() {
  list_label="$1  $2  $3"
  if [ -n "$4" ] && [ "$4" != "-" ]; then
    list_label="$list_label  PHP $4"
  fi
  if [ -n "$5" ] && [ "$5" != "-" ]; then
    list_label="$list_label  node $5"
  fi
  if [ "$6" != "true" ]; then
    list_label="$list_label  disabled"
  fi
  printf '%s\n' "$list_label"
}

lar_list_draw() {
  if [ "$list_drawn" -eq 1 ]; then
    printf '\033[%sA' "$list_lines" >/dev/tty
  fi
  list_i=0
  while IFS=$(printf '\t') read -r list_row_name list_row_enabled list_row_label; do
    list_i=$((list_i + 1))
    if [ "$list_i" -eq "$list_cursor" ]; then
      list_mark='>'
    else
      list_mark=' '
    fi
    printf '\r\033[2K%s %s\n' "$list_mark" "$list_row_label" >/dev/tty
  done < "$list_rows"
  printf '\r\033[2K%s\n' "$list_hint" >/dev/tty
  list_drawn=1
}

lar_list_read() {
  stty -echo -icanon min 1 time 0 </dev/tty
  list_key=$(dd bs=1 count=1 </dev/tty 2>/dev/null || true)
  if [ "$list_key" = "$(printf '\033')" ]; then
    stty -echo -icanon min 0 time 1 </dev/tty
    list_more=$(dd bs=1 count=1 </dev/tty 2>/dev/null || true)
    if [ -n "$list_more" ]; then
      list_more=$list_more$(dd bs=1 count=1 </dev/tty 2>/dev/null || true)
    fi
    stty -echo -icanon min 1 time 0 </dev/tty
    if [ -z "$list_more" ]; then
      list_key=quit
    else
      list_key=$(printf '\033')"$list_more"
    fi
  fi
}

lar_list() {
  if [ "$#" -ne 0 ]; then
    printf '%s\n' "list does not accept arguments." >&2
    exit 2
  fi
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    lar_fail "list is used from a terminal."
  fi
  file=$LAR_ROOT/data/config/sites.yaml
  if [ ! -f "$file" ]; then
    lar_fail "Missing data/config/sites.yaml. Run ./lar.sh init."
  fi
  LAR_SITE_NAMES=''
  LAR_SITE_MANIFEST=$(mktemp)
  LAR_SITE_OVERRIDES=$(mktemp)
  list_rows=$(mktemp)
  lar_sites_parse
  if [ -s "$LAR_SITE_MANIFEST" ]; then
    while IFS=$(printf '\t') read -r list_name list_domain list_project list_public list_php list_server list_node list_enabled list_aliases list_https; do
      lar_list_label "$list_name" "$list_domain" "$list_server" "$list_php" "$list_node" "$list_enabled" | while IFS= read -r list_label; do
        printf '%s\t%s\t%s\n' "$list_name" "$list_enabled" "$list_label"
      done >> "$list_rows"
    done < "$LAR_SITE_MANIFEST"
  fi
  rm -f "$LAR_SITE_MANIFEST" "$LAR_SITE_OVERRIDES"
  list_count=$(wc -l < "$list_rows" | tr -d ' ')
  if [ "$list_count" -eq 0 ]; then
    rm -f "$list_rows"
    printf '%s\n' "There are no sites in data/config/sites.yaml."
    return 0
  fi
  list_cursor=1
  list_drawn=0
  list_lines=$((list_count + 1))
  list_hint='  arrows, enter opens, q quits'
  list_up=$(printf '\033[A')
  list_up2=$(printf '\033OA')
  list_down=$(printf '\033[B')
  list_down2=$(printf '\033OB')
  list_enter=$(printf '\r')
  LAR_LIST_STTY=$(stty -g </dev/tty)
  trap 'lar_list_restore; exit 130' INT
  trap 'lar_list_restore; exit 143' TERM
  trap 'lar_list_restore' EXIT
  printf '\033[?25l' >/dev/tty
  while true; do
    lar_list_draw
    lar_list_read
    if [ "$list_key" = "$list_up" ] || [ "$list_key" = "$list_up2" ]; then
      list_hint='  arrows, enter opens, q quits'
      if [ "$list_cursor" -gt 1 ]; then
        list_cursor=$((list_cursor - 1))
      fi
    elif [ "$list_key" = "$list_down" ] || [ "$list_key" = "$list_down2" ]; then
      list_hint='  arrows, enter opens, q quits'
      if [ "$list_cursor" -lt "$list_count" ]; then
        list_cursor=$((list_cursor + 1))
      fi
    elif [ "$list_key" = q ] || [ "$list_key" = Q ] || [ "$list_key" = quit ]; then
      lar_list_restore
      trap - EXIT INT TERM
      rm -f "$list_rows"
      return 0
    elif [ "$list_key" = "$list_enter" ] || [ -z "$list_key" ]; then
      list_pick=$(awk -F '\t' -v n="$list_cursor" 'NR == n { print $1 "\t" $2; exit }' "$list_rows")
      list_pick_name=${list_pick%%	*}
      list_pick_enabled=${list_pick#*	}
      if [ "$list_pick_enabled" != "true" ]; then
        list_hint="  $list_pick_name is disabled."
      else
        break
      fi
    fi
  done
  lar_list_restore
  trap - EXIT INT TERM
  rm -f "$list_rows"
  lar_shell "$list_pick_name"
}

lar_shell() {
  if [ "$#" -gt 1 ]; then
    printf '%s\n' "Usage: ./lar.sh shell [site]" >&2
    exit 2
  fi
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    lar_fail "shell is used from a terminal."
  fi
  lar_php_container_running
  if [ "$#" -eq 0 ]; then
    exec docker exec -it -u web -w /home/web lar-php zsh
  fi
  lar_site_by_name "$1"
  if [ -z "$LAR_MATCH_PHP" ]; then
    lar_highest_listed "$LAR_ROOT/core/php/versions"
    LAR_MATCH_PHP=$LAR_HIGHEST_VERSION
  fi
  if [ -z "$LAR_MATCH_NODE" ]; then
    lar_highest_listed "$LAR_ROOT/core/php/node-versions"
    LAR_MATCH_NODE=$LAR_HIGHEST_VERSION
  fi
  set -- docker exec -it -u web -e LAR_SHELL_CHECK=1 -w "$LAR_MATCH_PATH"
  if [ -n "$LAR_MATCH_PHP" ]; then
    set -- "$@" -e "LAR_PHP_VERSION=$LAR_MATCH_PHP"
  fi
  if [ -n "$LAR_MATCH_NODE" ]; then
    set -- "$@" -e "LAR_NODE_VERSION=$LAR_MATCH_NODE"
  fi
  exec "$@" lar-php zsh
}
