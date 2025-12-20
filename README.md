# 🚀 PHP Turbo Stack (Docker LAMP & LEMP)

[![Version](https://img.shields.io/badge/version-1.0.2-blue.svg)](https://github.com/kevinpareek/turbo-stack/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-ready-brightgreen.svg)](https://www.docker.com/)
[![PHP](https://img.shields.io/badge/PHP-7.4--8.4-777BB4.svg)](https://www.php.net/)

**The most complete, flexible, and production-ready Docker LAMP & LEMP environment for PHP developers.**

Stop wasting time configuring servers. Get everything you need—**Apache, Nginx, MySQL/MariaDB, Redis, Varnish, Memcached, Mailpit, and more**—in one powerful, optimized Docker setup.

> 📖 **Quick Links:** [Installation](#installation) • [Commands](#️-the-tbs-command) • [Configuration](#️-configuration-via-env) • [Roadmap](#-coming-soon)

---

## ✨ Why PHP Turbo Stack?

| Feature | Description |
|---------|-------------|
| 🔥 **Dual Modes** | **Hybrid** (Nginx → Varnish → Apache) for compatibility, **Thunder** (Nginx → PHP-FPM) for performance |
| 🐘 **PHP 7.4 - 8.4** | Switch PHP versions instantly with a single command |
| 💾 **MySQL & MariaDB** | Choose from MySQL 5.7-8.4 or MariaDB 10.3-11.4 |
| ⚡ **Caching Suite** | Pre-configured Redis, Memcached, and Varnish |
| 🔒 **Smart SSL** | Auto SSL via mkcert (local) or Let's Encrypt (production) |
| 🛠 **Dev Tools** | phpMyAdmin, Mailpit (email testing), Xdebug ready |
| 🤖 **CLI Automation** | Powerful `tbs` command to manage everything |

---

## 🚀 Getting Started

### ⚡ Quick Start (TL;DR)

```bash
git clone https://github.com/kevinpareek/turbo-stack.git && cd turbo-stack
./tbs.sh config    # Choose PHP, Database, Mode
./tbs.sh start     # Launch the stack
```

Open **http://localhost** and you're ready! 🎉

---

### Prerequisites

<details>
<summary><strong>📋 Click to expand detailed requirements</strong></summary>

The stack works on **macOS, Linux, Windows, and other Unix-like systems**.

#### Common Requirements (All Environments)

*   **Docker**:
    *   **macOS**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) (recommended) or Docker Engine + Compose
    *   **Linux**: Docker Engine + Docker Compose v2 plugin (or Docker Desktop)
    *   **Windows**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) (includes WSL 2)
    *   **Other OS**: Docker Engine + Docker Compose v2 plugin
*   **Docker Compose v2**: Required (included with Docker Desktop; install separately for Docker Engine)
*   **Git**: For cloning the repository
*   **Bash Shell**:
    *   **macOS/Linux**: Built-in (bash 4.0+)
    *   **Windows**: [Git Bash](https://git-scm.com/downloads) (recommended) or WSL 2
    *   **Other OS**: bash 4.0+ or compatible shell
*   **System Utilities**:
    *   `curl` - HTTP client (standard on macOS/Linux; included with Git Bash on Windows)
    *   `sed` - Text stream editor (standard on macOS/Linux; included with Git Bash on Windows)
*   **Ports Available**: Ensure ports `80` (HTTP) and `443` (HTTPS) are not in use by other services
*   **System Resources**: Minimum 2GB RAM, 10GB free disk space (more recommended for production)

#### Local Development Requirements

*   **mkcert**: For generating trusted SSL certificates for `.localhost` domains
    *   *The script can automatically install mkcert for you!*
    *   **macOS**: Requires Homebrew (`brew install mkcert nss`)
    *   **Linux**: Requires `libnss3-tools` (via apt/yum/pacman package managers)
    *   **Windows**: Requires Chocolatey (`choco install mkcert`) or manual installation

#### Live/Production Requirements

*   **Domain & DNS**: Your domain(s) must point to the server's IP address before SSL generation
*   **Ports**: Ports `80` and `443` must be publicly accessible (firewall configured)
*   **Server Access**: SSH access with sudo/root privileges (for initial setup)
*   **Security**: Change all default passwords in `.env` before deployment (see [SECURITY.md](SECURITY.md))

#### OS-Specific Notes

| OS | Notes |
|----|-------|
| **macOS** | Apple Silicon (M1/M2/M3) fully supported; MariaDB recommended |
| **Linux** | Ubuntu, Debian, CentOS, Fedora, Arch - may need `sudo` for Docker |
| **Windows** | Requires WSL 2 + Docker Desktop; use Git Bash or WSL terminal |
| **Other Unix** | Check Docker docs for your OS; bash 4.0+ required |

</details>

### Installation

1.  **Clone & Enter:**
    ```bash
    git clone https://github.com/kevinpareek/turbo-stack.git
    cd turbo-stack
    ```

2.  **Configure:**
    Run the **TBS (Turbo Stack)** wizard to choose your PHP version, Database, and Stack Mode.
    ```bash
    ./tbs.sh config
    ```

3.  **Launch:**
    ```bash
    ./tbs.sh start
    ```

    ### 🌐 Accessing the Dashboard
    You can access the dashboard via:
    *   **http://localhost**
    *   **http://127.0.0.1**

---

## 🛠️ The `tbs` Command

Manage your entire stack with simple, intuitive commands.

### Core Commands
| Command | Description |
| :--- | :--- |
| `tbs` | Open interactive menu |
| `tbs start` | Start all services |
| `tbs stop` | Stop all services |
| `tbs restart` | Restart the stack |
| `tbs build` | Rebuild images and start |
| `tbs status` | Show running containers |
| `tbs logs [service]` | Stream logs |
| `tbs config` | Configuration wizard |
| `tbs info` | Show stack info |

### App Management (`tbs app`)
| Command | Description |
| :--- | :--- |
| `tbs app` | Interactive app manager |
| `tbs app add <name>` | Create new app (auto SSH, SSL, vhost) |
| `tbs app rm [app]` | Delete app |
| `tbs app db [app]` | Database management |
| `tbs app ssh [app]` | SSH/SFTP settings |
| `tbs app domain [app]` | Manage domains |
| `tbs app ssl [app]` | SSL certificates |
| `tbs app php [app]` | PHP configuration |
| `tbs app config [app]` | App settings (varnish, webroot, etc.) |
| `tbs app code [app]` | Open in VS Code |
| `tbs app open [app]` | Open in browser |
| `tbs app info [app]` | Show app config |
| `tbs app supervisor [app]` | Manage background workers |
| `tbs app cron [app]` | Manage cron jobs |
| `tbs app logs [app]` | App logging |

> Database management is app-scoped via `tbs app db <app>`, which covers create, import/export, reset password, and delete. Databases and MySQL users share the same app-prefixed name (for example, `myapp_abcd`).

### Project Creators (`tbs create`)
| Command | Description |
| :--- | :--- |
| `tbs create laravel <name>` | New Laravel project |
| `tbs create wordpress <name>` | WordPress with auto database |
| `tbs create symfony <name>` | New Symfony project |
| `tbs create blank <name>` | Blank PHP project |

### Shell & Tools
| Command | Description |
| :--- | :--- |
| `tbs shell [php\|mysql\|redis\|nginx]` | Container shell access |
| `tbs pma` | Open phpMyAdmin |
| `tbs mail` | Open Mailpit |
| `tbs redis-cli` | Redis CLI |
| `tbs code [app]` | Open in VS Code |

### Backup & Restore
| Command | Description |
| :--- | :--- |
| `tbs backup` | Backup databases + apps |
| `tbs restore` | Restore from backup |

### SSH Admin
| Command | Description |
| :--- | :--- |
| `tbs sshadmin` | Show admin SSH credentials |
| `tbs sshadmin password` | Reset admin password |

#### Global `tbs` Command
The script auto-installs a global shim. If your shell can't find `tbs`, restart your terminal or run:
```bash
source ~/.bashrc   # or ~/.zshrc for Zsh
```

---

## ⚙️ Configuration via `.env`

Most behavior is controlled through `.env` (created from `sample.env` and maintained by `tbs config`):

- **Core settings**
  - `INSTALLATION_TYPE` — `local` (mkcert for `.localhost`) or `live` (Let's Encrypt via Certbot).
  - `APP_ENV` — `development` or `production` (controls PHP INI, debug tools, profiles).
  - `STACK_MODE` — `hybrid` (Apache + Nginx) or `thunder` (Nginx + PHP-FPM).
  - `PHPVERSION` — one of the PHP Docker images under `bin/` (e.g. `php8.3`).
  - `DATABASE` — one of the MySQL/MariaDB images under `bin/` (e.g. `mysql5.7`, `mariadb10.11`).
- **Paths & volumes**
  - `DOCUMENT_ROOT` (default `./www`), `APPLICATIONS_DIR_NAME` (default `applications`).
  - `VHOSTS_DIR` (`./sites/apache`), `NGINX_CONF_DIR` (`./sites/nginx`), `SSL_DIR` (`./sites/ssl`).
  - Data & logs: `MYSQL_DATA_DIR`, `MYSQL_LOG_DIR`, `REDIS_DATA_DIR`, `BACKUP_DIR`, etc.
- **Ports**
  - HTTP/HTTPS: `HOST_MACHINE_UNSECURE_HOST_PORT`, `HOST_MACHINE_SECURE_HOST_PORT`.
  - DB & tools: `HOST_MACHINE_MYSQL_PORT`, `HOST_MACHINE_PMA_PORT`, `HOST_MACHINE_REDIS_PORT`.
- **Database credentials**
  - `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD` (change for production!).
  - **Host**: `dbhost` (internal container name) or `localhost` (from host machine).

Run `./tbs.sh config` anytime to re-run the wizard and safely update `.env`.

---

## ⚙️ Architecture & Modes

You can switch modes in `.env` or via `tbs config`.

### 1. Hybrid Mode (Default)
**Flow:** `User` ➡ `Nginx (Proxy)` ➡ `Varnish (Cache)` ➡ `Apache (Webserver)` ➡ `PHP`

*   **Best for:** Compatibility, Legacy Apps, WordPress.
*   **How it works:**
    *   **Nginx** handles SSL and static files.
    *   **Varnish** caches dynamic content.
    *   **Apache** executes PHP and supports `.htaccess` files.

### 2. Thunder Mode (High Performance)
**Flow:** `User` ➡ `Nginx (Frontend)` ➡ `Varnish (Cache)` ➡ `Nginx (Backend)` ➡ `PHP-FPM`

*   **Best for:** High Traffic, Modern Frameworks (Laravel, Symfony), APIs.
*   **How it works:**
    *   **Apache is completely removed** from the request path.
    *   **Nginx** acts as both the frontend (SSL) and backend (FastCGI manager).
    *   **PHP-FPM** handles code execution directly for maximum speed.
    *   *Note: `.htaccess` files are NOT supported in this mode.*
*   Ideal for Laravel, Symfony, and high-performance modern apps.

### 3. Node.js Mode (Coming Soon)
**Nginx ➡ Node.js**
*   Full support for Node.js applications.
*   Integrated with the rest of the stack (Redis, MySQL, etc.).

---

## 🧩 Stack Components & Roles

*   **Nginx (Reverse Proxy):** The entry point for all requests. Handles SSL termination and serves static files.
*   **Varnish (HTTP Accelerator):** Caches dynamic content from the webserver to serve requests instantly (Hybrid Mode).
*   **Apache / PHP-FPM:** The backend engines that execute your PHP code.
*   **Redis:** Advanced key-value store. Perfect for caching, session management, and queues.
*   **Memcached:** Simple, high-performance memory object caching system.
*   **Mailpit:** Catches all emails sent by PHP. View them in the browser instead of spamming real users.

---

## 🎛️ Per-Application Features

Each app created via `tbs app add` automatically gets:
- **Unique app_user ID** - Random 12-char identifier for isolation
- **SSH/SFTP access** - Auto-generated secure credentials
- **SSL certificates** - Via mkcert (local) or Let's Encrypt (production)
- **Dedicated directory structure** - `public_html/`, `logs/`, `tmp/`, etc.

### App Configuration (`tbs app config`)

```bash
# Interactive config menu
tbs app config myapp

# Direct commands
tbs app config myapp varnish on/off    # Toggle Varnish caching
tbs app config myapp webroot public    # Change document root
tbs app config myapp perms             # Reset file permissions
tbs app config myapp show              # Show full config JSON
```

### Database per App (`tbs app db`)

```bash
tbs app db myapp              # Interactive database menu
# Options: Create, Show credentials, Reset password, Import, Export, Delete
```

### SSH/SFTP Access (`tbs app ssh`)

```bash
tbs app ssh myapp             # Interactive SSH menu
# Options: Show credentials, Enable, Reset password, Disable

# Connect via SFTP
sftp -P 2244 <app_user>@localhost
```

### Domain Management (`tbs app domain`)

```bash
tbs app domain myapp          # Manage domains
# Options: Add domain, Remove domain
```

### PHP Configuration (`tbs app php`)

```bash
tbs app php myapp             # PHP config menu
# Options: Create .user.ini, Create FPM pool, Edit configs
```

### Background Workers & Cron

```bash
# Supervisor (background processes)
tbs app supervisor myapp add worker    # Add new worker
tbs app supervisor myapp list          # List workers
tbs app supervisor myapp rm worker     # Remove worker

# Cron jobs
tbs app cron myapp add                 # Add cron job
tbs app cron myapp list                # List jobs
```

### Configuration Storage

Each app config is stored as JSON in `sites/apps/<app_user>.json`:

```json
{
  "app_user": "abc123xyz",
  "name": "myapp",
  "domains": ["abc123xyz.localhost"],
  "primary_domain": "abc123xyz.localhost",
  "webroot": "public_html",
  "varnish": true,
  "database": { "name": "myapp", "user": "myapp", "created": true },
  "ssh": { "enabled": true, "username": "abc123xyz", "password": "***", "port": 2244 }
}
```

---

## 🔒 Security Features

Turbo Stack includes built-in security rules to protect your applications from common attack vectors.

### Blocked Files & Extensions

The following files and patterns are automatically blocked from public access:

| Category | Blocked Patterns |
| :--- | :--- |
| **Version Control** | `.git`, `.svn`, `.hg` |
| **Environment Files** | `.env`, `.env.*` |
| **Database Files** | `.sql`, `.sql.gz`, `.sqlite`, `.db` |
| **Backup Files** | `.bak`, `.backup`, `.old`, `.orig` |
| **Config Files** | `.yml`, `.yaml`, `.xml`, `.json`, `.ini`, `.conf` |
| **Sensitive Files** | `.htpasswd`, `.htaccess`, `.pem`, `.key`, `.crt`, `.log` |
| **PHP Internals** | `composer.json`, `composer.lock`, `phpunit.xml`, `artisan` |

### Production Hardening

In production mode (`APP_ENV=production`), additional security measures are applied:

- **`open_basedir`**: Restricts PHP file access to web root only
- **`disable_functions`**: Dangerous functions like `exec`, `shell_exec`, `system` are disabled
- **Session Security**: `httponly`, `secure`, and `samesite` flags enabled
- **Error Display**: Errors logged to file, not displayed to users

> **Tip:** Always review `config/php/php.production.ini` before deploying to production.

---

## �📂 Directory Structure

```text
├── bin/                 # Docker build context for PHP, Nginx, MySQL/MariaDB images
├── config/              # Source-of-truth configuration (mounted into containers)
│   ├── initdb/          # Put .sql/.sql.gz files here → auto-run on first DB container start
│   ├── mariadb/         # Custom MySQL/MariaDB configs (e.g. my.cnf)
│   ├── nginx/           # Nginx templates, partials, and mode configs
│   ├── php/             # php.ini variants, FPM pool, supervisord configs
│   │   └── templates/   # Per-app config templates (user.ini, FPM pool)
│   ├── varnish/         # VCL configurations for Hybrid / Thunder modes
│   └── vhosts/          # Base Apache vhost templates used by tbs.sh
├── data/                # Persistent data volumes (DB, Redis, backups)
├── logs/                # Logs for web, DB, and services (Apache, Nginx, MySQL, etc.)
├── sites/               # Generated configs (managed by tbs.sh – do NOT edit manually)
│   ├── apache/          # Active Apache vhosts for your apps
│   ├── apps/            # App configuration JSON files
│   ├── nginx/           # Active Nginx configs per app / mode
│   ├── php/pools/       # Per-app PHP-FPM pool configs (gitignored)
│   ├── ssh/             # SSH user configs per app
│   └── ssl/             # Generated SSL certs (mkcert / Let's Encrypt)
├── www/                 # Web root inside containers
│   ├── applications/    # Your project folders (created via `tbs app add`)
│   └── index.php        # Landing page
└── tbs.sh               # Turbo Stack CLI script
```

**Database auto-init:** Any `.sql` (or compressed `.sql.gz`) file you drop into `config/initdb` will be picked up and executed automatically when the database container starts for the first time—perfect for seeding schemas, users, and sample data.

---

## 🔧 Technical Reference

### Default Credentials
*   **MySQL/MariaDB**: User: `root`, Pass: `root`, DB: `docker`
*   **phpMyAdmin**: User: `root`, Pass: `root`

### Services & Ports
| Service | Internal Port | Host Port (Default) |
| :--- | :--- | :--- |
| **Web (HTTP)** | 80 | `80` |
| **Web (HTTPS)** | 443 | `443` |
| **MySQL/MariaDB** | 3306 | `3306` |
| **phpMyAdmin** | 80 | `8080` |
| **Mailpit (UI)** | 8025 | `8025` |
| **Mailpit (SMTP)** | 1025 | `1025` |
| **Redis** | 6379 | `6379` |
| **Memcached** | 11211 | `11211` (bound to `127.0.0.1` by default) |

### Adding PHP Extensions
Edit `./bin/php<version>/Dockerfile` (e.g., `./bin/php8.2/Dockerfile`) and run `tbs build`.

### Xdebug Setup (VS Code)
Add this to `.vscode/launch.json`:
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Listen for Xdebug",
            "type": "php",
            "request": "launch",
            "port": 9003,
            "pathMappings": { "/var/www/html": "${workspaceFolder}" }
        }
    ]
}
```

---

## ⚠️ Production Checklist

- [ ] Set `APP_ENV=production` in `.env`
- [ ] Change all default passwords (`MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`)
- [ ] Set `INSTALL_XDEBUG=false`
- [ ] Configure proper `STACK_MODE` for your needs
- [ ] Review firewall rules (ports 80, 443)
- [ ] Setup backup strategy using `tbs backup`

> 📚 See [SECURITY.md](SECURITY.md) for hardening guide • [CHANGELOG.md](CHANGELOG.md) for release notes

---

## 🔧 Troubleshooting

### Container Health Check Failures

If containers show as "unhealthy" with errors like `exec ...: no such file or directory`, this is usually a line ending issue (CRLF vs LF).

**Quick Fix:**
```bash
tbs fix-line-endings  # Auto-fixes line endings
tbs build             # Rebuilds containers
```

> **Note:** `tbs start` and `tbs build` automatically fix line endings, so this issue should rarely occur.

### Other Common Issues

| Issue | Solution |
|-------|----------|
| **Port already in use** | Change ports in `.env` or stop conflicting services |
| **Permission denied** | On Linux: `sudo usermod -aG docker $USER` (then log out/in) |
| **SSL certificate errors** | Run `tbs ssl generate-default` for local development |
| **Database connection failed** | Verify `MYSQL_ROOT_PASSWORD` in `.env` matches your app config |

---

## 🔮 Coming Soon

We're constantly improving Turbo Stack! Here's what's on our roadmap:

| Category | Feature | Description |
| :--- | :--- | :--- |
| **🐘 PHP** | PHP 8.5 | Support for upcoming PHP 8.5 release |
| **🐘 PHP** | ionCube Loader | ionCube PHP Encoder support |
| **🌐 Routing** | Web Rules | Custom header & URL rewrite rules per app |
| **📁 Structure** | New Webroot Standard | Document root at `applications/<app>/public_html/` |
| **📁 Structure** | App Data Directory | Dedicated data storage at `applications/<app>/app_data/` |
| **💾 Database** | MongoDB Support | Full MongoDB integration |
| **💾 Database** | PostgreSQL Support | Full PostgreSQL integration |
| **🚀 Stack** | Node.js Mode | Full Node.js application support with PM2 |
| **📊 Monitoring** | New Relic APM | Application Performance Monitoring |
| **📊 Monitoring** | Prometheus + Grafana | Self-hosted metrics & dashboards |
| **📊 Monitoring** | Sentry | Error tracking & crash reporting |
| **📊 Monitoring** | Health Checks | Automated service health monitoring |

> 💡 **Want to contribute?** Pick a feature from the roadmap and submit a PR!

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  <strong>Made with ❤️ for PHP developers</strong><br>
  <sub>If you find this useful, please ⭐ star the repo!</sub>
</p>
