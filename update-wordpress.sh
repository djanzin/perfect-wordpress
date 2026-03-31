#!/usr/bin/env bash
# =============================================================================
#  WordPress Stack Updater
#  Updates: WordPress core, plugins, themes, WP-CLI, system packages, SSL
# =============================================================================
# Usage:
#   sudo bash update-wordpress.sh
#   sudo bash update-wordpress.sh --wp-path /var/www/wordpress --all
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
[[ $EUID -ne 0 ]] && error "Bitte als root ausführen: sudo bash $0"

# ─── Defaults ─────────────────────────────────────────────────────────────────
WP_PATH=""
UPDATE_SYSTEM=false
UPDATE_WPCLI=false
UPDATE_SSL=false
UPDATE_ALL=false

# ─── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --wp-path)   WP_PATH="$2";     shift 2 ;;
    --system)    UPDATE_SYSTEM=true; shift  ;;
    --wpcli)     UPDATE_WPCLI=true;  shift  ;;
    --ssl)       UPDATE_SSL=true;    shift  ;;
    --all)       UPDATE_ALL=true;    shift  ;;
    *) warn "Unbekannter Parameter: $1"; shift ;;
  esac
done

if [[ "$UPDATE_ALL" == true ]]; then
  UPDATE_SYSTEM=true
  UPDATE_WPCLI=true
  UPDATE_SSL=true
fi

# ─── WordPress Pfad ermitteln ─────────────────────────────────────────────────
if [[ -z "$WP_PATH" ]]; then
  # Automatisch suchen
  for candidate in /var/www/wordpress /var/www/html /var/www/*/; do
    if [[ -f "${candidate}/wp-config.php" ]]; then
      WP_PATH="$candidate"
      break
    fi
  done
fi

[[ -z "$WP_PATH" || ! -f "${WP_PATH}/wp-config.php" ]] && \
  error "WordPress nicht gefunden. Pfad angeben: --wp-path /pfad/zu/wordpress"

WP_DOMAIN=$(basename "$WP_PATH")
[[ "$WP_DOMAIN" == "wordpress" ]] && \
  WP_DOMAIN=$(grep -i "WP_HOME\|siteurl" "${WP_PATH}/wp-config.php" 2>/dev/null \
    | head -1 | sed "s/.*['\"]https\?:\/\/\([^'\"]*\)['\"].*/\1/" || echo "wordpress")

WP_BIN=$(command -v wp 2>/dev/null || true)
[[ -z "$WP_BIN" || ! -x "$WP_BIN" ]] && WP_BIN="/usr/local/bin/wp"
WP_CLI=("$WP_BIN" --path="$WP_PATH" --allow-root)

section "WordPress Stack Updater"
echo -e "  WordPress-Pfad : ${CYAN}${WP_PATH}${RESET}"
echo -e "  System-Update  : ${CYAN}${UPDATE_SYSTEM}${RESET}"
echo -e "  WP-CLI Update  : ${CYAN}${UPDATE_WPCLI}${RESET}"
echo -e "  SSL Renewal    : ${CYAN}${UPDATE_SSL}${RESET}"
echo ""

# ─── 1. System-Pakete ─────────────────────────────────────────────────────────
if [[ "$UPDATE_SYSTEM" == true ]]; then
  section "System-Update"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get upgrade -y -qq
  success "System-Pakete aktualisiert."
fi

# ─── 2. WP-CLI ────────────────────────────────────────────────────────────────
if [[ "$UPDATE_WPCLI" == true ]]; then
  section "WP-CLI Update"
  if command -v wp &>/dev/null; then
    WP_CLI_CURRENT=$(wp --info --allow-root 2>/dev/null | grep 'WP-CLI version' | awk '{print $3}' || echo "unbekannt")
    info "Aktuelle Version: ${WP_CLI_CURRENT}"
    curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
      -o /usr/local/bin/wp
    chmod +x /usr/local/bin/wp
    WP_CLI_NEW=$(wp --info --allow-root 2>/dev/null | grep 'WP-CLI version' | awk '{print $3}' || echo "unbekannt")
    success "WP-CLI aktualisiert auf ${WP_CLI_NEW}."
  else
    warn "WP-CLI nicht gefunden — überspringe."
  fi
fi

# ─── 3. WordPress Core ────────────────────────────────────────────────────────
section "WordPress Core Update"
WP_VERSION_BEFORE=$("${WP_CLI[@]}" core version 2>/dev/null || echo "unbekannt")
info "Aktuelle WP-Version: ${WP_VERSION_BEFORE}"

if "${WP_CLI[@]}" core check-update 2>/dev/null | grep -q 'update available'; then
  "${WP_CLI[@]}" core update
  "${WP_CLI[@]}" core update-db
  WP_VERSION_AFTER=$("${WP_CLI[@]}" core version 2>/dev/null || echo "unbekannt")
  success "WordPress Core aktualisiert: ${WP_VERSION_BEFORE} → ${WP_VERSION_AFTER}"
else
  success "WordPress Core ist aktuell (${WP_VERSION_BEFORE})."
fi

# ─── 4. Plugins ───────────────────────────────────────────────────────────────
section "Plugin-Updates"
PLUGINS_WITH_UPDATES=$("${WP_CLI[@]}" plugin list --update=available --format=count 2>/dev/null || echo "0")
if [[ "$PLUGINS_WITH_UPDATES" -gt 0 ]]; then
  info "${PLUGINS_WITH_UPDATES} Plugin(s) mit verfügbaren Updates..."
  "${WP_CLI[@]}" plugin update --all
  success "Alle Plugins aktualisiert."
else
  success "Alle Plugins sind aktuell."
fi

# ─── 5. Themes ────────────────────────────────────────────────────────────────
section "Theme-Updates"
THEMES_WITH_UPDATES=$("${WP_CLI[@]}" theme list --update=available --format=count 2>/dev/null || echo "0")
if [[ "$THEMES_WITH_UPDATES" -gt 0 ]]; then
  info "${THEMES_WITH_UPDATES} Theme(s) mit verfügbaren Updates..."
  "${WP_CLI[@]}" theme update --all
  success "Alle Themes aktualisiert."
else
  success "Alle Themes sind aktuell."
fi

# ─── 6. Cache leeren ──────────────────────────────────────────────────────────
section "Cache leeren"

# WordPress & Redis Cache
"${WP_CLI[@]}" cache flush 2>/dev/null && info "WordPress Object Cache geleert." || true

# FastCGI Cache leeren
if [[ -d "/var/cache/nginx/fastcgi" ]]; then
  find /var/cache/nginx/fastcgi -type f -delete 2>/dev/null || true
  success "Nginx FastCGI Cache geleert."
fi

# Nginx neu laden
nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null && \
  info "Nginx neu geladen." || true

# PHP-FPM OPcache leeren
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;" 2>/dev/null || echo "8.3")
systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null && \
  info "PHP-FPM OPcache geleert." || true

success "Alle Caches geleert."

# ─── 7. SSL-Zertifikat erneuern ───────────────────────────────────────────────
if [[ "$UPDATE_SSL" == true ]]; then
  section "SSL-Zertifikat erneuern"
  if command -v certbot &>/dev/null; then
    certbot renew --quiet --nginx 2>/dev/null && \
      success "SSL-Zertifikate erneuert." || \
      warn "Certbot Renewal fehlgeschlagen — ggf. bereits aktuell oder Reverse Proxy aktiv."
  else
    warn "Certbot nicht installiert — überspringe."
  fi
fi

# ─── 8. Service-Status ────────────────────────────────────────────────────────
section "Service-Status"
for svc in nginx "php${PHP_VERSION}-fpm" mariadb redis-server; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo -e "  ${GREEN}[OK]${RESET}    $svc"
  else
    echo -e "  ${YELLOW}[WARN]${RESET}  $svc — nicht aktiv"
  fi
done

# ─── Abschluss ────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}${GREEN}════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  Update abgeschlossen — $(date '+%Y-%m-%d %H:%M')${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════${RESET}\n"
