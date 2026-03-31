#!/usr/bin/env bash
# =============================================================================
#  WordPress Production Installer
#  Stack: Ubuntu LTS / Debian · Nginx + FastCGI Cache · PHP-FPM + OPcache
#         MariaDB · Redis Object Cache · UFW · Fail2ban · WP-CLI
# =============================================================================
# Usage:
#   sudo bash install-wordpress.sh
#   sudo bash install-wordpress.sh --domain example.com --email admin@example.com \
#     --php 8.4 --memory 256M --lang de_DE --timezone Europe/Berlin --ssl
#
# Tested on: Ubuntu 24.04 LTS · Debian 13 (Trixie)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ─── Colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; }

# ─── Root check ───────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Dieses Script muss als root ausgeführt werden. Bitte 'sudo bash $0' verwenden."

# ─── OS detection ─────────────────────────────────────────────────────────────
if grep -qi 'ubuntu' /etc/os-release; then
  OS_TYPE="ubuntu"
elif grep -qi 'debian' /etc/os-release; then
  OS_TYPE="debian"
else
  error "Nicht unterstütztes OS. Ubuntu 24.04+ oder Debian 13+ erforderlich."
fi
info "Erkanntes Betriebssystem: $OS_TYPE"

# ─── Default configuration ────────────────────────────────────────────────────
WP_DOMAIN=""
WP_ADMIN_EMAIL=""
WP_SITE_TITLE="My WordPress Site"
WP_ADMIN_USER="admin"
WP_DIR="/var/www/wordpress"
NGINX_FASTCGI_CACHE_DIR="/var/cache/nginx/fastcgi"
PHP_VERSION="8.3"
PHP_MEMORY_LIMIT="256M"
WP_LANG="de_DE"
WP_TIMEZONE="Europe/Berlin"
INSTALL_SSL=false

# ─── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)       WP_DOMAIN="$2";        shift 2 ;;
    --email)        WP_ADMIN_EMAIL="$2";   shift 2 ;;
    --title)        WP_SITE_TITLE="$2";    shift 2 ;;
    --admin-user)   WP_ADMIN_USER="$2";    shift 2 ;;
    --php)          PHP_VERSION="$2";      shift 2 ;;
    --memory)       PHP_MEMORY_LIMIT="$2"; shift 2 ;;
    --lang)         WP_LANG="$2";          shift 2 ;;
    --timezone)     WP_TIMEZONE="$2";      shift 2 ;;
    --ssl)          INSTALL_SSL=true;      shift   ;;
    *) warn "Unbekannter Parameter: $1"; shift ;;
  esac
done

# ─── Interactive prompts (if not provided via args) ────────────────────────────
section "WordPress Production Installer — Konfiguration"

if [[ -z "$WP_DOMAIN" ]]; then
  read -rp "$(echo -e "${BOLD}Domain (z.B. example.com):${RESET} ")" WP_DOMAIN
fi
[[ -z "$WP_DOMAIN" ]] && error "Domain darf nicht leer sein."

if [[ -z "$WP_ADMIN_EMAIL" ]]; then
  read -rp "$(echo -e "${BOLD}Admin E-Mail:${RESET} ")" WP_ADMIN_EMAIL
fi
[[ -z "$WP_ADMIN_EMAIL" ]] && error "E-Mail darf nicht leer sein."

read -rp "$(echo -e "${BOLD}Site-Titel [My WordPress Site]:${RESET} ")" _title
WP_SITE_TITLE="${_title:-$WP_SITE_TITLE}"

read -rp "$(echo -e "${BOLD}WP Admin-Benutzername [admin]:${RESET} ")" _user
WP_ADMIN_USER="${_user:-$WP_ADMIN_USER}"

# ─── PHP-Version auswählen ────────────────────────────────────────────────────
if [[ "$PHP_VERSION" == "8.3" ]]; then
  echo -e "\n${BOLD}PHP-Version auswählen:${RESET}"
  echo -e "  1) PHP 8.1"
  echo -e "  2) PHP 8.2"
  echo -e "  3) PHP 8.3  ${CYAN}[Standard / empfohlen]${RESET}"
  echo -e "  4) PHP 8.4"
  echo -e "  5) PHP 8.5  ${YELLOW}(Entwicklungsversion)${RESET}"
  read -rp "$(echo -e "${BOLD}Auswahl [1-5, Standard: 3]:${RESET} ")" _php_choice
  case "${_php_choice:-3}" in
    1) PHP_VERSION="8.1" ;;
    2) PHP_VERSION="8.2" ;;
    3) PHP_VERSION="8.3" ;;
    4) PHP_VERSION="8.4" ;;
    5) PHP_VERSION="8.5" ; warn "PHP 8.5 ist eine Entwicklungsversion — nicht für Produktion empfohlen." ;;
    *) warn "Ungültige Auswahl, verwende PHP 8.3."; PHP_VERSION="8.3" ;;
  esac
fi

# ─── PHP Memory Limit auswählen ───────────────────────────────────────────────
if [[ "$PHP_MEMORY_LIMIT" == "256M" ]]; then
  echo -e "\n${BOLD}PHP Memory Limit auswählen:${RESET}"
  echo -e "  1) 128M   ${CYAN}(kleiner VPS / wenig RAM)${RESET}"
  echo -e "  2) 256M   ${CYAN}[Standard / empfohlen]${RESET}"
  echo -e "  3) 512M   ${CYAN}(mittelgroße Seiten)${RESET}"
  echo -e "  4) 1024M  ${CYAN}(große / hochfrequentierte Seiten)${RESET}"
  read -rp "$(echo -e "${BOLD}Auswahl [1-4, Standard: 2]:${RESET} ")" _mem_choice
  case "${_mem_choice:-2}" in
    1) PHP_MEMORY_LIMIT="128M"  ;;
    2) PHP_MEMORY_LIMIT="256M"  ;;
    3) PHP_MEMORY_LIMIT="512M"  ;;
    4) PHP_MEMORY_LIMIT="1024M" ;;
    *) warn "Ungültige Auswahl, verwende 256M."; PHP_MEMORY_LIMIT="256M" ;;
  esac
fi

# ─── Sprache & Zeitzone ───────────────────────────────────────────────────────
if [[ "$WP_LANG" == "de_DE" ]]; then
  read -rp "$(echo -e "${BOLD}WordPress-Sprache [de_DE]:${RESET} ")" _lang
  WP_LANG="${_lang:-de_DE}"
fi
if [[ "$WP_TIMEZONE" == "Europe/Berlin" ]]; then
  read -rp "$(echo -e "${BOLD}Zeitzone [Europe/Berlin]:${RESET} ")" _tz
  WP_TIMEZONE="${_tz:-Europe/Berlin}"
fi

# ─── SSL mit Let's Encrypt? ───────────────────────────────────────────────────
if [[ "$INSTALL_SSL" == false ]]; then
  read -rp "$(echo -e "${BOLD}SSL mit Let's Encrypt einrichten? [j/N]:${RESET} ")" _ssl
  [[ "${_ssl,,}" == "j" || "${_ssl,,}" == "y" ]] && INSTALL_SSL=true
fi

# ─── Generate random secrets ──────────────────────────────────────────────────
DB_NAME="wp_$(tr -dc 'a-z0-9' </dev/urandom | head -c 8 || true)"
DB_USER="wpuser_$(tr -dc 'a-z0-9' </dev/urandom | head -c 6 || true)"
DB_PASS="$(tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom | head -c 32 || true)"
# DB_ROOT_PASS nicht mehr benötigt — MariaDB root nutzt unix_socket Auth
WP_ADMIN_PASS="$(tr -dc 'A-Za-z0-9!@#$%' </dev/urandom | head -c 24 || true)"
REDIS_PASS="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}Installationsparameter:${RESET}"
echo -e "  Domain        : ${CYAN}${WP_DOMAIN}${RESET}"
echo -e "  WP-Verzeichnis: ${CYAN}${WP_DIR}${RESET}"
echo -e "  PHP-Version   : ${CYAN}${PHP_VERSION}${RESET}"
echo -e "  Memory Limit  : ${CYAN}${PHP_MEMORY_LIMIT}${RESET}"
echo -e "  Sprache       : ${CYAN}${WP_LANG}${RESET}"
echo -e "  Zeitzone      : ${CYAN}${WP_TIMEZONE}${RESET}"
echo -e "  SSL           : ${CYAN}${INSTALL_SSL}${RESET}"
echo -e "  DB Name       : ${CYAN}${DB_NAME}${RESET}"
echo -e "  DB User       : ${CYAN}${DB_USER}${RESET}"
echo ""
read -rp "$(echo -e "${BOLD}Jetzt installieren? [j/N]:${RESET} ")" CONFIRM
[[ "${CONFIRM,,}" != "j" && "${CONFIRM,,}" != "y" ]] && echo "Abgebrochen." && exit 0

# ─── Credentials speichern ────────────────────────────────────────────────────
CREDS_FILE="/root/.wp_install_credentials_${WP_DOMAIN}.txt"
cat > "$CREDS_FILE" <<EOF
# WordPress Installation Credentials — $(date)
# BITTE SICHER AUFBEWAHREN!
Domain:          https://${WP_DOMAIN}
WP Admin User:   ${WP_ADMIN_USER}
WP Admin Pass:   ${WP_ADMIN_PASS}
WP Admin Email:  ${WP_ADMIN_EMAIL}
DB Name:         ${DB_NAME}
DB User:         ${DB_USER}
DB Password:     ${DB_PASS}
DB Root Access:  unix_socket (sudo mysql -uroot)
Redis Password:  ${REDIS_PASS}
EOF
chmod 600 "$CREDS_FILE"
info "Zugangsdaten gespeichert: $CREDS_FILE"

# =============================================================================
# 1. SYSTEM UPDATE
# =============================================================================
section "1/9 — System Update"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  curl wget gnupg2 lsb-release ca-certificates \
  unzip zip git htop ncdu tree net-tools
# software-properties-common nur auf Ubuntu nötig (für add-apt-repository)
if [[ "$OS_TYPE" == "ubuntu" ]]; then
  apt-get install -y -qq software-properties-common
fi
success "System aktualisiert."

# ─── Swap-Datei anlegen (falls < 1 GB Swap vorhanden) ────────────────────────
SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
if [[ "$SWAP_TOTAL" -lt 1024 ]]; then
  info "Kein/wenig Swap erkannt (${SWAP_TOTAL}MB) — lege 2GB Swap an..."
  fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile
  mkswap /swapfile -q
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -w vm.swappiness=10 >/dev/null
  echo 'vm.swappiness=10' >> /etc/sysctl.conf
  success "2GB Swap angelegt und aktiviert."
else
  info "Swap bereits vorhanden (${SWAP_TOTAL}MB) — überspringe."
fi

# =============================================================================
# 2. NGINX + FastCGI Cache
# =============================================================================
section "2/9 — Nginx + FastCGI Cache"
apt-get install -y -qq nginx libnginx-mod-http-cache-purge \
  libnginx-mod-http-brotli-filter libnginx-mod-http-brotli-static
systemctl enable nginx

# FastCGI Cache Verzeichnis
mkdir -p "$NGINX_FASTCGI_CACHE_DIR"
chown -R www-data:www-data /var/cache/nginx

# Nginx globale Optimierungen
cat > /etc/nginx/nginx.conf <<'NGINXCONF'
user www-data;
worker_processes auto;
worker_rlimit_nofile 65535;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections  4096;
    multi_accept        on;
    use                 epoll;
}

http {
    # Basic
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    keepalive_requests  1000;
    types_hash_max_size 2048;
    server_tokens       off;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] '
                    '"$request" $status $body_bytes_sent '
                    '"$http_referer" "$http_user_agent" '
                    'rt=$request_time uc="$upstream_cache_status"';
    access_log /var/log/nginx/access.log main buffer=16k flush=2m;
    error_log  /var/log/nginx/error.log warn;

    # GZIP
    gzip              on;
    gzip_vary         on;
    gzip_proxied      any;
    gzip_comp_level   5;
    gzip_min_length   256;
    gzip_types
        text/plain text/css text/xml text/javascript
        application/javascript application/x-javascript
        application/json application/xml application/rss+xml
        application/atom+xml image/svg+xml font/opentype
        application/vnd.ms-fontobject application/x-font-ttf;

    # Brotli (bessere Komprimierung als gzip, ~15-25% effizienter)
    brotli              on;
    brotli_comp_level   6;
    brotli_min_length   256;
    brotli_types
        text/plain text/css text/xml text/javascript
        application/javascript application/x-javascript
        application/json application/xml application/rss+xml
        application/atom+xml image/svg+xml font/opentype
        application/vnd.ms-fontobject application/x-font-ttf;

    # FastCGI Cache Zone
    fastcgi_cache_path /var/cache/nginx/fastcgi
        levels=1:2
        keys_zone=WORDPRESS:100m
        inactive=60m
        max_size=1g
        use_temp_path=off;
    fastcgi_cache_key "$scheme$request_method$host$request_uri";

    # Timeouts
    client_body_timeout   12;
    client_header_timeout 12;
    send_timeout          10;
    client_max_body_size  64m;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
NGINXCONF

# Nginx FastCGI Params Snippet
cat > /etc/nginx/snippets/fastcgi-params-wp.conf <<'FASTCGI'
fastcgi_param SCRIPT_FILENAME     $document_root$fastcgi_script_name;
fastcgi_param QUERY_STRING        $query_string;
fastcgi_param REQUEST_METHOD      $request_method;
fastcgi_param CONTENT_TYPE        $content_type;
fastcgi_param CONTENT_LENGTH      $content_length;
fastcgi_param SCRIPT_NAME         $fastcgi_script_name;
fastcgi_param REQUEST_URI         $request_uri;
fastcgi_param DOCUMENT_URI        $document_uri;
fastcgi_param DOCUMENT_ROOT       $document_root;
fastcgi_param SERVER_PROTOCOL     $server_protocol;
fastcgi_param GATEWAY_INTERFACE   CGI/1.1;
fastcgi_param SERVER_SOFTWARE     nginx/$nginx_version;
fastcgi_param REMOTE_ADDR         $remote_addr;
fastcgi_param REMOTE_PORT         $remote_port;
fastcgi_param SERVER_ADDR         $server_addr;
fastcgi_param SERVER_PORT         $server_port;
fastcgi_param SERVER_NAME         $server_name;
fastcgi_param HTTPS               $https if_not_empty;
fastcgi_param HTTP_PROXY          "";
FASTCGI

# Security Headers Snippet
cat > /etc/nginx/snippets/security-headers.conf <<'SECHEADERS'
add_header X-Frame-Options           "SAMEORIGIN"           always;
add_header X-XSS-Protection          "1; mode=block"        always;
add_header X-Content-Type-Options    "nosniff"              always;
add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
add_header Permissions-Policy        "camera=(), microphone=(), geolocation=()" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
SECHEADERS

# WordPress Nginx Vhost
cat > "/etc/nginx/sites-available/${WP_DOMAIN}.conf" <<VHOST
# ─── FastCGI Cache Skip Rules ─────────────────────────────────────────────────
map \$http_cookie \$skip_cache_cookie {
    default 0;
    "~*wordpress_logged_in"   1;
    "~*comment_author"        1;
    "~*woocommerce_items_in_cart" 1;
    "~*wp-postpass_"          1;
}

map \$request_method \$skip_cache_method {
    default 0;
    POST    1;
}

map \$query_string \$skip_cache_query {
    default 0;
    "~*.+"  1;
}

upstream php${PHP_VERSION}-fpm {
    server unix:/run/php/php${PHP_VERSION}-fpm.sock;
    keepalive 32;
}

server {
    listen 80;
    listen [::]:80;
    server_name ${WP_DOMAIN} www.${WP_DOMAIN};

    # Redirect to HTTPS (nach Certbot-Einrichtung aktivieren)
    # return 301 https://\$host\$request_uri;

    root ${WP_DIR};
    index index.php index.html;

    # Logging
    access_log /var/log/nginx/${WP_DOMAIN}-access.log main;
    error_log  /var/log/nginx/${WP_DOMAIN}-error.log warn;

    include /etc/nginx/snippets/security-headers.conf;

    # ─── FastCGI Cache Status Header ──────────────────────────────────────────
    add_header X-Cache-Status \$upstream_cache_status always;

    # ─── Cache bypass logic ───────────────────────────────────────────────────
    set \$skip_cache 0;
    if (\$skip_cache_cookie) { set \$skip_cache 1; }
    if (\$skip_cache_method) { set \$skip_cache 1; }
    if (\$skip_cache_query)  { set \$skip_cache 1; }
    if (\$request_uri ~* "(/wp-admin/|/xmlrpc.php|/wp-login.php|wp-.*.php|/feed/|index.php|sitemap.xml)") {
        set \$skip_cache 1;
    }

    # ─── WordPress Permalink ──────────────────────────────────────────────────
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # ─── PHP-FPM + FastCGI Cache ──────────────────────────────────────────────
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;

        fastcgi_pass   php${PHP_VERSION}-fpm;
        fastcgi_index  index.php;
        fastcgi_read_timeout 300;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;

        include /etc/nginx/snippets/fastcgi-params-wp.conf;

        # FastCGI Cache
        fastcgi_cache            WORDPRESS;
        fastcgi_cache_valid       200 301 302 1h;
        fastcgi_cache_valid       404 1m;
        fastcgi_cache_use_stale  error timeout updating http_500 http_503;
        fastcgi_cache_lock       on;
        fastcgi_cache_bypass     \$skip_cache;
        fastcgi_no_cache         \$skip_cache;
        fastcgi_cache_background_update on;
        fastcgi_cache_min_uses   1;
    }

    # ─── Static Assets ────────────────────────────────────────────────────────
    location ~* \.(css|js|ico|gif|jpe?g|png|webp|avif|svg|woff2?|ttf|eot|otf)$ {
        expires     max;
        access_log  off;
        log_not_found off;
        add_header  Cache-Control "public, immutable";
        add_header  Vary "Accept-Encoding";
    }

    # ─── Security: Block access to sensitive files ─────────────────────────────
    location ~ /\.ht        { deny all; }
    location ~ /\.git       { deny all; }
    location = /xmlrpc.php  { deny all; }
    location ~* /(?:uploads|files)/.*\.php$ { deny all; }
    location = /wp-config.php { deny all; }

    # ─── Limit login page ─────────────────────────────────────────────────────
    location = /wp-login.php {
        limit_req zone=wplogin burst=3 nodelay;
        fastcgi_pass   php${PHP_VERSION}-fpm;
        fastcgi_index  index.php;
        include /etc/nginx/snippets/fastcgi-params-wp.conf;
    }

    # ─── Nginx Helper — FastCGI Cache Purge Endpoint ──────────────────────────
    location ~ /purge(/.*) {
        allow 127.0.0.1;
        deny  all;
        fastcgi_cache_purge WORDPRESS "\$scheme\$request_method\$host\$1";
    }
}

# ─── HTTPS Server Block (nach SSL-Einrichtung via Certbot aktiv) ──────────────
# server {
#     listen 443 ssl http2;
#     listen [::]:443 ssl http2;
#     server_name ${WP_DOMAIN} www.${WP_DOMAIN};
#
#     ssl_certificate     /etc/letsencrypt/live/${WP_DOMAIN}/fullchain.pem;
#     ssl_certificate_key /etc/letsencrypt/live/${WP_DOMAIN}/privkey.pem;
#     ssl_protocols       TLSv1.2 TLSv1.3;
#     ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
#     ssl_prefer_server_ciphers off;
#     ssl_session_cache   shared:SSL:10m;
#     ssl_session_timeout 1d;
#     ssl_stapling        on;
#     ssl_stapling_verify on;
#
#     root ${WP_DIR};
#     index index.php index.html;
#     # ... (gleiche location-Blöcke wie oben)
# }
VHOST

# Rate limiting Zone
cat > /etc/nginx/conf.d/rate-limiting.conf <<'RATELIMIT'
limit_req_zone $binary_remote_addr zone=wplogin:10m rate=2r/m;
RATELIMIT

# Default site deaktivieren, WordPress aktivieren
rm -f /etc/nginx/sites-enabled/default
ln -sf "/etc/nginx/sites-available/${WP_DOMAIN}.conf" "/etc/nginx/sites-enabled/${WP_DOMAIN}.conf"

nginx -t && systemctl reload nginx
success "Nginx konfiguriert mit FastCGI Cache."

# =============================================================================
# 3. PHP-FPM + OPcache
# =============================================================================
section "3/9 — PHP ${PHP_VERSION}-FPM + OPcache"
if [[ "$OS_TYPE" == "ubuntu" ]]; then
  add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
else
  # Debian: packages.sury.org (ondrej's offizielles Debian-Repo)
  rm -f /etc/apt/trusted.gpg.d/sury-php.gpg
  curl -fsSL https://packages.sury.org/php/apt.gpg \
    | gpg --dearmor -o /etc/apt/trusted.gpg.d/sury-php.gpg
  echo "deb https://packages.sury.org/php/ $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/sury-php.list
fi
apt-get update -qq
apt-get install -y -qq \
  "php${PHP_VERSION}-fpm" \
  "php${PHP_VERSION}-mysql" \
  "php${PHP_VERSION}-redis" \
  "php${PHP_VERSION}-curl" \
  "php${PHP_VERSION}-gd" \
  "php${PHP_VERSION}-mbstring" \
  "php${PHP_VERSION}-xml" \
  "php${PHP_VERSION}-xmlrpc" \
  "php${PHP_VERSION}-soap" \
  "php${PHP_VERSION}-intl" \
  "php${PHP_VERSION}-zip" \
  "php${PHP_VERSION}-bcmath" \
  "php${PHP_VERSION}-imagick" \
  "php${PHP_VERSION}-opcache" \
  "php${PHP_VERSION}-cli"

# Standard www.conf Pool entfernen — verhindert Socket-Konflikt mit wordpress.conf
rm -f "/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

# PHP-FPM Pool Optimierung
cat > "/etc/php/${PHP_VERSION}/fpm/pool.d/wordpress.conf" <<PHPPOOL
[wordpress]
user  = www-data
group = www-data

listen = /run/php/php${PHP_VERSION}-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode  = 0660

; Prozess-Manager: dynamisch
pm                   = dynamic
pm.max_children      = 50
pm.start_servers     = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.max_requests      = 500
pm.process_idle_timeout = 10s

; Request-Timeouts
request_terminate_timeout = 300s
request_slowlog_timeout   = 5s
slowlog                   = /var/log/php${PHP_VERSION}-fpm-slow.log

; Sicherheit
security.limit_extensions = .php

; Environment
env[HOSTNAME]  = \$HOSTNAME
env[PATH]      = /usr/local/bin:/usr/bin:/bin
env[TMP]       = /tmp
env[TMPDIR]    = /tmp
env[TEMP]      = /tmp

; PHP Einstellungen (WordPress-optimiert)
php_admin_value[error_log]         = /var/log/php${PHP_VERSION}-fpm-error.log
php_admin_flag[log_errors]         = on
php_value[upload_max_filesize]     = 64M
php_value[post_max_size]           = 64M
php_value[memory_limit]            = ${PHP_MEMORY_LIMIT}
php_value[max_execution_time]      = 300
php_value[max_input_vars]          = 3000
php_value[max_input_time]          = 300
php_value[session.gc_maxlifetime]  = 1440
PHPPOOL

# PHP.ini Optimierungen
PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
sed -i "s|^;date.timezone.*|date.timezone = ${WP_TIMEZONE}|"  "$PHP_INI"
sed -i 's/^upload_max_filesize.*/upload_max_filesize = 64M/'  "$PHP_INI"
sed -i 's/^post_max_size.*/post_max_size = 64M/'              "$PHP_INI"
sed -i "s/^memory_limit.*/memory_limit = ${PHP_MEMORY_LIMIT}/"  "$PHP_INI"
sed -i 's/^max_execution_time.*/max_execution_time = 300/'    "$PHP_INI"
sed -i 's/^max_input_time.*/max_input_time = 300/'            "$PHP_INI"
sed -i 's/^;max_input_vars.*/max_input_vars = 3000/'          "$PHP_INI"
sed -i 's/^expose_php.*/expose_php = Off/'                    "$PHP_INI"

# OPcache Tuning (separate Datei — System's opcache.ini bleibt unberührt)
# zend_extension wird bereits vom php-opcache Paket geladen — nicht doppelt laden!
cat > "/etc/php/${PHP_VERSION}/fpm/conf.d/99-opcache-wordpress.ini" <<'OPCACHE'
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.max_wasted_percentage=10
opcache.validate_timestamps=0
opcache.revalidate_freq=0
opcache.save_comments=1
opcache.fast_shutdown=1
opcache.jit=tracing
opcache.jit_buffer_size=128M
OPCACHE

# Standard Pool deaktivieren, WordPress Pool aktivieren
systemctl enable "php${PHP_VERSION}-fpm"
systemctl restart "php${PHP_VERSION}-fpm"
success "PHP ${PHP_VERSION}-FPM mit OPcache konfiguriert."

# =============================================================================
# 4. MARIADB
# =============================================================================
section "4/9 — MariaDB"

# Vorherige MariaDB-Installation bereinigen (verhindert Passwort-Konflikte bei Wiederholung)
if dpkg -l mariadb-server 2>/dev/null | grep -q '^ii'; then
  info "Vorherige MariaDB-Installation erkannt — bereinige für Neuinstallation..."
  systemctl stop mariadb 2>/dev/null || true
  apt-get purge -y -qq --auto-remove mariadb-server mariadb-client mariadb-common 2>/dev/null || true
  rm -rf /var/lib/mysql /etc/mysql/mariadb.conf.d/99-wordpress.cnf
  info "MariaDB bereinigt."
fi

apt-get install -y -qq mariadb-server mariadb-client
systemctl enable mariadb

# MariaDB Optimierungen
cat > /etc/mysql/mariadb.conf.d/99-wordpress.cnf <<'MYCNF'
[mysqld]
# Zeichensatz
character-set-server  = utf8mb4
collation-server      = utf8mb4_unicode_ci
innodb_file_per_table = 1

# Performance
innodb_buffer_pool_size       = 256M
innodb_buffer_pool_instances  = 1
innodb_log_file_size          = 64M
innodb_log_buffer_size        = 16M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method           = O_DIRECT
innodb_read_io_threads        = 4
innodb_write_io_threads       = 4

# Query Cache (MariaDB)
query_cache_type   = 1
query_cache_size   = 64M
query_cache_limit  = 2M

# Verbindungen
max_connections     = 150
max_allowed_packet  = 64M
thread_cache_size   = 8
table_open_cache    = 4000

# Slow Query Log
slow_query_log      = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time     = 2

# Sicherheit
bind-address = 127.0.0.1
skip-name-resolve

[client]
default-character-set = utf8mb4
MYCNF

systemctl restart mariadb

# MariaDB absichern und DB anlegen
mysql -uroot <<SQLSETUP
-- Root behält unix_socket-Auth (sicherer auf Debian/Ubuntu — kein Passwort nötig bei OS-Root)
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQLSETUP

success "MariaDB konfiguriert und Datenbank '${DB_NAME}' erstellt."

# =============================================================================
# 5. REDIS OBJECT CACHE
# =============================================================================
section "5/9 — Redis Object Cache"
apt-get install -y -qq redis-server

cat > /etc/redis/redis.conf <<REDISCONF
# Redis Konfiguration — WordPress Object Cache
daemonize yes
supervised systemd
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log

# Netzwerk (nur localhost)
bind 127.0.0.1 -::1
port 6379
protected-mode yes
requirepass ${REDIS_PASS}

# Speicher
maxmemory 128mb
maxmemory-policy allkeys-lru
maxmemory-samples 5

# Persistenz deaktivieren (nur Cache)
save ""
appendonly no

# Performance
tcp-keepalive 300
timeout 300
tcp-backlog 511
REDISCONF

systemctl enable redis-server
systemctl restart redis-server
success "Redis konfiguriert (127.0.0.1:6379, maxmemory=128mb, LRU)."

# =============================================================================
# 6. UFW FIREWALL + FAIL2BAN
# =============================================================================
section "6/9 — UFW Firewall + Fail2ban"
apt-get install -y -qq ufw fail2ban

# UFW Regeln
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
success "UFW aktiviert: SSH, HTTP, HTTPS erlaubt."

# Fail2ban — WordPress + Nginx Jail
cat > /etc/fail2ban/jail.local <<'F2B'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
banaction = ufw

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 24h

[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/*error.log

[nginx-limit-req]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/*error.log
maxretry = 10

[wordpress-auth]
enabled  = true
port     = http,https
filter   = wordpress-auth
logpath  = /var/log/nginx/*access.log
maxretry = 5
bantime  = 24h
F2B

# Fail2ban Filter für WP Login
cat > /etc/fail2ban/filter.d/wordpress-auth.conf <<'F2BFILTER'
[Definition]
failregex = ^<HOST> .* "POST /wp-login.php
            ^<HOST> .* "POST /xmlrpc.php
ignoreregex =
F2BFILTER

systemctl enable fail2ban
systemctl restart fail2ban
success "Fail2ban mit WordPress- und Nginx-Jails aktiviert."

# =============================================================================
# 7. WORDPRESS DOWNLOAD + KONFIGURATION
# =============================================================================
section "7/9 — WordPress installieren"
mkdir -p "$WP_DIR"
cd /tmp

# WordPress herunterladen
curl -sSLo /tmp/wordpress.tar.gz "https://wordpress.org/latest.tar.gz"
tar -xzf /tmp/wordpress.tar.gz -C /tmp/
cp -a /tmp/wordpress/. "$WP_DIR/"
rm -rf /tmp/wordpress /tmp/wordpress.tar.gz

# Berechtigungen setzen
chown -R www-data:www-data "$WP_DIR"
find "$WP_DIR" -type d -exec chmod 755 {} \;
find "$WP_DIR" -type f -exec chmod 644 {} \;
chmod 440 "$WP_DIR/wp-config.php" 2>/dev/null || true

# wp-config.php erstellen
WP_SECURITY_KEYS=$(curl -sSL https://api.wordpress.org/secret-key/1.1/salt/)
PHP_MAX_MEMORY_LIMIT="$(( ${PHP_MEMORY_LIMIT%M} * 2 ))M"

cat > "$WP_DIR/wp-config.php" <<WPCONFIG
<?php
/**
 * WordPress Konfiguration — Auto-generiert von install-wordpress.sh
 */

// ─── Datenbank ────────────────────────────────────────────────────────────────
define( 'DB_NAME',     '${DB_NAME}' );
define( 'DB_USER',     '${DB_USER}' );
define( 'DB_PASSWORD', '${DB_PASS}' );
define( 'DB_HOST',     'localhost' );
define( 'DB_CHARSET',  'utf8mb4' );
define( 'DB_COLLATE',  'utf8mb4_unicode_ci' );

// ─── Sicherheitsschlüssel (auto-generiert) ────────────────────────────────────
${WP_SECURITY_KEYS}

// ─── Datenbanktabellen-Präfix ─────────────────────────────────────────────────
\$table_prefix = 'wp_$(tr -dc 'a-z' </dev/urandom | head -c 4 || true)_';

// ─── Redis Object Cache ───────────────────────────────────────────────────────
define( 'WP_REDIS_HOST',     '127.0.0.1' );
define( 'WP_REDIS_PORT',     6379 );
define( 'WP_REDIS_PASSWORD', '${REDIS_PASS}' );
define( 'WP_REDIS_DATABASE', 0 );
define( 'WP_REDIS_TIMEOUT',  1 );
define( 'WP_REDIS_READ_TIMEOUT', 1 );
define( 'WP_REDIS_PREFIX',   '${DB_NAME}:' );

// ─── Performance ──────────────────────────────────────────────────────────────
define( 'WP_MEMORY_LIMIT',     '${PHP_MEMORY_LIMIT}' );
define( 'WP_MAX_MEMORY_LIMIT', '${PHP_MAX_MEMORY_LIMIT}' );
define( 'WP_POST_REVISIONS',   5 );
define( 'AUTOSAVE_INTERVAL',   300 );
define( 'EMPTY_TRASH_DAYS',    14 );
define( 'WP_CACHE',            true );

// ─── Sicherheit ───────────────────────────────────────────────────────────────
define( 'DISALLOW_FILE_EDIT', true );
define( 'FORCE_SSL_ADMIN',    true );
define( 'WP_DEBUG',           false );
define( 'WP_DEBUG_LOG',       false );
define( 'WP_DEBUG_DISPLAY',   false );
define( 'SCRIPT_DEBUG',       false );

// ─── Upload & Update ──────────────────────────────────────────────────────────
define( 'UPLOADS',            'wp-content/uploads' );
define( 'IMAGE_EDIT_OVERWRITE', true );

// ─── Multisite (deaktiviert) ──────────────────────────────────────────────────
// define( 'WP_ALLOW_MULTISITE', true );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}
require_once ABSPATH . 'wp-settings.php';
WPCONFIG

chmod 440 "$WP_DIR/wp-config.php"
chown www-data:www-data "$WP_DIR/wp-config.php"

# .htaccess
cat > "$WP_DIR/.htaccess" <<'HTACCESS'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTACCESS

success "WordPress heruntergeladen und konfiguriert."

# =============================================================================
# 8. WP-CLI
# =============================================================================
section "8/9 — WP-CLI"
curl -sSLo /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x /usr/local/bin/wp

# WP-CLI als www-data ausführen — Alias
cat > /usr/local/bin/wpcli <<ALIAS
#!/bin/bash
sudo -u www-data wp "\$@"
ALIAS
chmod +x /usr/local/bin/wpcli

# WordPress via WP-CLI installieren
sudo -u www-data wp core install \
  --path="$WP_DIR" \
  --url="http://${WP_DOMAIN}" \
  --title="${WP_SITE_TITLE}" \
  --admin_user="${WP_ADMIN_USER}" \
  --admin_password="${WP_ADMIN_PASS}" \
  --admin_email="${WP_ADMIN_EMAIL}" \
  --skip-email

# Redis Object Cache Plugin installieren & aktivieren
sudo -u www-data wp plugin install redis-cache --activate --path="$WP_DIR"
sudo -u www-data wp redis enable --path="$WP_DIR"

# Nginx Helper installieren & konfigurieren
sudo -u www-data wp plugin install nginx-helper --activate --path="$WP_DIR"
sudo -u www-data wp option update rt_wp_nginx_helper_options \
  '{"enable_purge":"1","cache_method":"enable_fastcgi","purge_method":"unlink_files","enable_map":"0","enable_log":"0","log_level":"INFO","log_filesize":"5","enable_stamp":"0","purge_homepage_on_edit":"1","purge_homepage_on_del":"1","purge_archive_on_edit":"1","purge_archive_on_del":"1","purge_page_on_mod":"1","purge_page_on_new_comment":"1","purge_page_on_deleted_comment":"1"}' \
  --format=json --path="$WP_DIR"
success "Nginx Helper installiert und konfiguriert (FastCGI-Cache-Purge aktiv)."

# Standard-Plugins & Themes bereinigen
sudo -u www-data wp plugin delete hello akismet --path="$WP_DIR" 2>/dev/null || true
sudo -u www-data wp theme delete twentytwenty twentytwentyone twentytwentytwo --path="$WP_DIR" 2>/dev/null || true

# Permalinks setzen (SEO-optimiert)
sudo -u www-data wp rewrite structure '/%postname%/' --hard --path="$WP_DIR"
sudo -u www-data wp rewrite flush --hard --path="$WP_DIR"

# Standard-Einstellungen
sudo -u www-data wp option update timezone_string "${WP_TIMEZONE}" --path="$WP_DIR"
sudo -u www-data wp option update date_format "d.m.Y" --path="$WP_DIR"
sudo -u www-data wp option update time_format "H:i" --path="$WP_DIR"
sudo -u www-data wp option update WPLANG "${WP_LANG}" --path="$WP_DIR"
sudo -u www-data wp option update blogdescription "" --path="$WP_DIR"
sudo -u www-data wp option update comment_registration 1 --path="$WP_DIR"
sudo -u www-data wp option update default_ping_status closed --path="$WP_DIR"
sudo -u www-data wp option update default_comment_status closed --path="$WP_DIR"

success "WP-CLI installiert und WordPress konfiguriert."

# =============================================================================
# 9. LOGROTATE + CRON + FINALISIERUNG
# =============================================================================
section "9/9 — Logrotation, Cron & finale Optimierungen"

# cron-Daemon sicherstellen (auf Debian 13 nicht vorinstalliert)
if ! command -v crontab &>/dev/null; then
  apt-get install -y -qq --no-install-recommends cron
  systemctl enable cron 2>/dev/null || true
fi

# Logrotation für Nginx / PHP / MySQL
cat > /etc/logrotate.d/wordpress-stack <<'LOGROTATE'
/var/log/nginx/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        nginx -s reopen
    endscript
}

/var/log/php*-fpm*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
}

/var/log/mysql/slow.log {
    weekly
    rotate 4
    compress
    delaycompress
    notifempty
}
LOGROTATE

# WordPress Cron über System-Cron (WP-Cron deaktivieren)
cat >> "$WP_DIR/wp-config.php" <<'DISABLEWPCRON'

// WP-Cron über System-Cron ersetzen (performance)
define( 'DISABLE_WP_CRON', true );
DISABLEWPCRON

(crontab -l 2>/dev/null; echo "*/5 * * * * www-data /usr/local/bin/wp --path=${WP_DIR} cron event run --due-now --quiet") | crontab -

# ─── Automatische Datenbank-Backups (täglich, 7 Tage Rotation) ────────────────
mkdir -p /root/backups/mysql
chmod 700 /root/backups/mysql
cat > /etc/cron.daily/wp-db-backup <<DBBACKUP
#!/bin/bash
BACKUP_DIR="/root/backups/mysql"
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)
mysqldump -uroot --single-transaction --routines --triggers \
  '${DB_NAME}' | gzip > "\${BACKUP_DIR}/${DB_NAME}_\${TIMESTAMP}.sql.gz"
# Backups älter als 7 Tage löschen
find "\${BACKUP_DIR}" -name "*.sql.gz" -mtime +7 -delete
DBBACKUP
chmod 750 /etc/cron.daily/wp-db-backup
success "Automatische DB-Backups konfiguriert (/root/backups/mysql, 7 Tage Rotation)."

# ─── SSL mit Let's Encrypt (Certbot) ──────────────────────────────────────────
if [[ "$INSTALL_SSL" == true ]]; then
  info "Installiere Certbot und richte SSL ein..."
  apt-get install -y -qq certbot python3-certbot-nginx
  certbot --nginx --non-interactive --agree-tos \
    -m "${WP_ADMIN_EMAIL}" \
    -d "${WP_DOMAIN}" \
    -d "www.${WP_DOMAIN}" \
    --redirect
  # HTTPS-Redirect im Vhost aktivieren
  sed -i 's|# return 301 https://|return 301 https://|' \
    "/etc/nginx/sites-available/${WP_DOMAIN}.conf"
  systemctl reload nginx
  success "SSL-Zertifikat eingerichtet. HTTPS aktiv."
else
  info "SSL übersprungen. Manuell einrichten: certbot --nginx -d ${WP_DOMAIN}"
fi

# MySQL Slow Log Verzeichnis anlegen
mkdir -p /var/log/mysql
chown mysql:mysql /var/log/mysql

# Abschließende Service-Neustarts
systemctl restart "php${PHP_VERSION}-fpm"
systemctl restart mariadb
systemctl restart redis-server
nginx -t && systemctl reload nginx

# Kurz warten bis alle Dienste stabil sind
sleep 3

# ─── Service-Status Abschlusskontrolle ────────────────────────────────────────
echo -e "\n${BOLD}Service-Status:${RESET}"
FAILED_SERVICES=()
for svc in nginx "php${PHP_VERSION}-fpm" mariadb redis-server fail2ban; do
  if systemctl is-active --quiet "$svc"; then
    echo -e "  ${GREEN}[OK]${RESET}    $svc"
  else
    echo -e "  ${RED}[FEHLER]${RESET} $svc — nicht aktiv! Versuche Neustart..."
    systemctl start "$svc" 2>/dev/null || true
    sleep 2
    if systemctl is-active --quiet "$svc"; then
      echo -e "  ${GREEN}[OK]${RESET}    $svc (nach Neustart)"
    else
      echo -e "  ${RED}[FEHLER]${RESET} $svc — Start fehlgeschlagen. Bitte prüfen: journalctl -u $svc"
      FAILED_SERVICES+=("$svc")
    fi
  fi
done

if [[ ${#FAILED_SERVICES[@]} -gt 0 ]]; then
  warn "Folgende Dienste konnten nicht gestartet werden: ${FAILED_SERVICES[*]}"
fi

# =============================================================================
# ABSCHLUSSBERICHT
# =============================================================================
section "✅ Installation abgeschlossen!"

echo -e ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║          WORDPRESS ERFOLGREICH INSTALLIERT                   ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo -e ""
SITE_PROTO="http"; [[ "$INSTALL_SSL" == true ]] && SITE_PROTO="https"
echo -e "  ${BOLD}Website URL:${RESET}      ${SITE_PROTO}://${WP_DOMAIN}"
echo -e "  ${BOLD}WP Admin:${RESET}         ${SITE_PROTO}://${WP_DOMAIN}/wp-admin"
echo -e "  ${BOLD}Admin User:${RESET}       ${WP_ADMIN_USER}"
echo -e "  ${BOLD}Admin Passwort:${RESET}   ${WP_ADMIN_PASS}"
echo -e "  ${BOLD}Admin Email:${RESET}      ${WP_ADMIN_EMAIL}"
echo -e ""
echo -e "  ${BOLD}Datenbank:${RESET}        ${DB_NAME} @ 127.0.0.1"
echo -e "  ${BOLD}DB Benutzer:${RESET}      ${DB_USER}"
echo -e "  ${BOLD}Redis:${RESET}            127.0.0.1:6379 (Object Cache aktiv)"
echo -e "  ${BOLD}PHP Version:${RESET}      ${PHP_VERSION} (Memory: ${PHP_MEMORY_LIMIT})"
echo -e "  ${BOLD}FastCGI Cache:${RESET}    ${NGINX_FASTCGI_CACHE_DIR}"
echo -e "  ${BOLD}DB Backup:${RESET}        /root/backups/mysql (täglich, 7 Tage)"
echo -e ""
echo -e "  ${BOLD}Credentials-Datei:${RESET}"
echo -e "    ${CYAN}${CREDS_FILE}${RESET}"
echo -e ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}NÄCHSTE SCHRITTE:${RESET}"
echo -e ""
if [[ "$INSTALL_SSL" == true ]]; then
echo -e "  ${GREEN}1. SSL bereits eingerichtet (Let's Encrypt aktiv)${RESET}"
else
echo -e "  ${BOLD}1. SSL-Zertifikat (Let's Encrypt):${RESET}"
echo -e "     ${CYAN}apt install -y certbot python3-certbot-nginx${RESET}"
echo -e "     ${CYAN}certbot --nginx -d ${WP_DOMAIN} -d www.${WP_DOMAIN}${RESET}"
fi
echo -e ""
echo -e "  ${BOLD}2. DNS prüfen (A-Record zeigt auf diese IP):${RESET}"
echo -e "     ${CYAN}dig +short ${WP_DOMAIN}${RESET}"
echo -e ""
echo -e "  ${BOLD}3. FastCGI Cache testen:${RESET}"
echo -e "     ${CYAN}curl -I http://${WP_DOMAIN} | grep X-Cache-Status${RESET}"
echo -e ""
echo -e "  ${BOLD}4. Redis Status prüfen:${RESET}"
echo -e "     ${CYAN}redis-cli -a '${REDIS_PASS}' ping${RESET}"
echo -e ""
echo -e "  ${BOLD}5. WP-CLI nutzen:${RESET}"
echo -e "     ${CYAN}wpcli --info${RESET}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e ""
warn "Alle Zugangsdaten wurden gespeichert in: ${CREDS_FILE}"
warn "HTTPS-Redirect in Nginx ist auskommentiert — nach Certbot aktivieren!"
echo -e ""
