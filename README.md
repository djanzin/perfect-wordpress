# perfect-wordpress

![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?logo=ubuntu&logoColor=white)
![Debian 13](https://img.shields.io/badge/Debian-13_Trixie-A81D33?logo=debian&logoColor=white)
![PHP 8.1–8.5](https://img.shields.io/badge/PHP-8.1_|_8.2_|_8.3_|_8.4_|_8.5-777BB4?logo=php&logoColor=white)
![License MIT](https://img.shields.io/badge/License-MIT-green)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-djanzin-FFDD00?logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/djanzin)

Automated, production-ready WordPress installer for Ubuntu 24.04 LTS and Debian 13 (Trixie).

---

## English

### What it does

A single bash script that sets up a hardened, high-performance WordPress server from scratch in minutes. Interactive prompts guide you through every configuration option — no manual editing required.

**Stack:**
- **Web server:** Nginx + FastCGI cache (1 GB zone) + Brotli & Gzip compression
- **PHP:** PHP-FPM 8.1/8.2/8.3/8.4/8.5 (selectable) + OPcache JIT
- **Database:** MariaDB (tuned: 256 MB InnoDB buffer, slow query log)
- **Object cache:** Redis (128 MB LRU, object cache only)
- **Security:** UFW firewall + Fail2ban (SSH + Nginx + WordPress login jails)
- **Cache management:** Nginx Helper plugin (automatic FastCGI cache purge)
- **CLI:** WP-CLI with `wpcli` shortcut
- **SSL:** Optional Let's Encrypt / Certbot (automatic HTTPS redirect)
- **Backups:** Daily MariaDB dumps with 7-day rotation

### Requirements

- Ubuntu 24.04 LTS **or** Debian 13 (Trixie)
- Root / sudo access
- A domain name pointing to the server (required for SSL)

### One-line install (directly from GitHub)

```bash
curl -fsSL https://raw.githubusercontent.com/djanzin/perfect-wordpress/main/install-wordpress.sh -o /tmp/install-wp.sh && sudo bash /tmp/install-wp.sh
```

With flags (non-interactive):

```bash
curl -fsSL https://raw.githubusercontent.com/djanzin/perfect-wordpress/main/install-wordpress.sh -o /tmp/install-wp.sh && sudo bash /tmp/install-wp.sh --domain example.com --email admin@example.com --ssl
```

The script will interactively ask for:
- Domain name & admin email
- Site title & admin username
- PHP version (8.1 / 8.2 / **8.3** / 8.4 / 8.5 ⚠️ dev)
- PHP memory limit (128M / **256M** / 512M / 1024M)
- WordPress language (default: `de_DE`)
- Timezone (default: `Europe/Berlin`)
- SSL via Let's Encrypt (yes/no)

### Non-interactive usage

All options can be passed as flags to skip the interactive prompts:

```bash
sudo bash install-wordpress.sh \
  --domain example.com \
  --email admin@example.com \
  --title "My Site" \
  --admin-user admin \
  --php 8.3 \
  --memory 256M \
  --lang en_US \
  --timezone America/New_York \
  --ssl
```

### CLI options

| Flag | Description | Default |
|------|-------------|---------|
| `--domain` | Domain name (e.g. `example.com`) | — |
| `--email` | WordPress admin email | — |
| `--title` | WordPress site title | `My WordPress Site` |
| `--admin-user` | WordPress admin username | `admin` |
| `--php` | PHP version (`8.1`, `8.2`, `8.3`, `8.4`, `8.5`) | `8.3` |
| `--memory` | PHP memory limit (`128M`, `256M`, `512M`, `1024M`) | `256M` |
| `--lang` | WordPress language code | `de_DE` |
| `--timezone` | PHP/WordPress timezone | `Europe/Berlin` |
| `--ssl` | Install SSL certificate via Certbot | `false` |

### What gets installed (9 steps)

1. System update + base tools + **swap file** (auto-created if < 1 GB available)
2. Nginx + FastCGI cache + **Brotli compression** + cache purge module
3. PHP-FPM (selected version) + OPcache JIT (tracing mode, 128 MB JIT buffer)
4. MariaDB (InnoDB optimized, slow query log, hardened)
5. Redis object cache (128 MB LRU, no persistence)
6. UFW firewall + Fail2ban (SSH, Nginx, WordPress login jails)
7. WordPress core (latest) + `wp-config.php` (randomized table prefix, secure salts)
8. WP-CLI + Redis Cache plugin + **Nginx Helper** plugin (auto-configured)
9. Log rotation + system cron (replaces WP-Cron) + **daily DB backups**

### Credentials

All generated credentials (admin password, database, Redis) are saved to:

```
/root/.wp_install_credentials_<domain>.txt  (chmod 600)
```

Database backups are stored in:

```
/root/backups/mysql/  (daily, 7-day rotation)
```

<a href="https://www.buymeacoffee.com/djanzin"><img src="https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=%E2%98%95&slug=djanzin&button_colour=00354d&font_colour=ffffff&font_family=Cookie&outline_colour=ffffff&coffee_colour=FFDD00" /></a>

---

## Deutsch

### Was es macht

Ein einzelnes Bash-Script, das einen abgesicherten, leistungsstarken WordPress-Server in wenigen Minuten von Grund auf einrichtet. Interaktive Abfragen führen durch alle Konfigurationsoptionen — kein manuelles Editieren nötig.

**Stack:**
- **Webserver:** Nginx + FastCGI-Cache (1 GB Zone) + Brotli & Gzip Komprimierung
- **PHP:** PHP-FPM 8.1/8.2/8.3/8.4 (wählbar) + OPcache JIT
- **Datenbank:** MariaDB (optimiert: 256 MB InnoDB Buffer, Slow Query Log)
- **Object Cache:** Redis (128 MB LRU, nur Cache)
- **Sicherheit:** UFW Firewall + Fail2ban (SSH + Nginx + WordPress-Login Jails)
- **Cache-Verwaltung:** Nginx Helper Plugin (automatische FastCGI-Cache-Invalidierung)
- **CLI:** WP-CLI mit `wpcli` Shortcut
- **SSL:** Optionales Let's Encrypt / Certbot (automatischer HTTPS-Redirect)
- **Backups:** Tägliche MariaDB-Dumps mit 7-Tage-Rotation

### Voraussetzungen

- Ubuntu 24.04 LTS **oder** Debian 13 (Trixie)
- Root / sudo Zugang
- Ein Domainname der auf den Server zeigt (erforderlich für SSL)

### Ein-Befehl-Installation (direkt von GitHub)

```bash
curl -fsSL https://raw.githubusercontent.com/djanzin/perfect-wordpress/main/install-wordpress.sh -o /tmp/install-wp.sh && sudo bash /tmp/install-wp.sh
```

Mit Flags (nicht-interaktiv):

```bash
curl -fsSL https://raw.githubusercontent.com/djanzin/perfect-wordpress/main/install-wordpress.sh -o /tmp/install-wp.sh && sudo bash /tmp/install-wp.sh --domain example.com --email admin@example.com --ssl
```

Das Script fragt interaktiv nach:
- Domain & Admin-E-Mail
- Site-Titel & Admin-Benutzername
- PHP-Version (8.1 / 8.2 / **8.3** / 8.4)
- PHP Memory Limit (128M / **256M** / 512M / 1024M)
- WordPress-Sprache (Standard: `de_DE`)
- Zeitzone (Standard: `Europe/Berlin`)
- SSL via Let's Encrypt (ja/nein)

### Nicht-interaktive Nutzung

Alle Optionen können als Flags übergeben werden, um die interaktiven Abfragen zu überspringen:

```bash
sudo bash install-wordpress.sh \
  --domain example.com \
  --email admin@example.com \
  --title "Meine Seite" \
  --admin-user admin \
  --php 8.3 \
  --memory 256M \
  --lang de_DE \
  --timezone Europe/Berlin \
  --ssl
```

### Alle Optionen

| Flag | Beschreibung | Standard |
|------|-------------|---------|
| `--domain` | Domainname (z.B. `example.com`) | — |
| `--email` | WordPress Admin-E-Mail | — |
| `--title` | WordPress-Site-Titel | `My WordPress Site` |
| `--admin-user` | WordPress Admin-Benutzername | `admin` |
| `--php` | PHP-Version (`8.1`, `8.2`, `8.3`, `8.4`) | `8.3` |
| `--memory` | PHP Memory Limit (`128M`, `256M`, `512M`, `1024M`) | `256M` |
| `--lang` | WordPress-Sprachcode | `de_DE` |
| `--timezone` | PHP/WordPress-Zeitzone | `Europe/Berlin` |
| `--ssl` | SSL-Zertifikat via Certbot installieren | `false` |

### Was installiert wird (9 Schritte)

1. System-Update + Basis-Tools + **Swap-Datei** (automatisch angelegt falls < 1 GB vorhanden)
2. Nginx + FastCGI-Cache + **Brotli-Komprimierung** + Cache-Purge-Modul
3. PHP-FPM (gewählte Version) + OPcache JIT (Tracing-Modus, 128 MB JIT-Buffer)
4. MariaDB (InnoDB optimiert, Slow Query Log, gehärtet)
5. Redis Object Cache (128 MB LRU, keine Persistenz)
6. UFW Firewall + Fail2ban (SSH-, Nginx- und WordPress-Login-Jails)
7. WordPress Core (aktuell) + `wp-config.php` (zufälliger Tabellen-Präfix, sichere Salts)
8. WP-CLI + Redis Cache Plugin + **Nginx Helper** Plugin (automatisch konfiguriert)
9. Log-Rotation + System-Cron (ersetzt WP-Cron) + **tägliche DB-Backups**

### Zugangsdaten

Alle generierten Zugangsdaten (Admin-Passwort, Datenbank, Redis) werden gespeichert in:

```
/root/.wp_install_credentials_<domain>.txt  (chmod 600)
```

Datenbank-Backups befinden sich in:

```
/root/backups/mysql/  (täglich, 7 Tage Rotation)
```

<a href="https://www.buymeacoffee.com/djanzin"><img src="https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=%E2%98%95&slug=djanzin&button_colour=00354d&font_colour=ffffff&font_family=Cookie&outline_colour=ffffff&coffee_colour=FFDD00" /></a>

---

## License

MIT
