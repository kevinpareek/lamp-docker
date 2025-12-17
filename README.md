# 🚀 PHP Turbo Stack (Docker LAMP & LEMP)

**The most complete, flexible, and production-ready local development environment for PHP.**

Stop wasting time configuring servers. This stack gives you everything you need—**Apache, Nginx, MySQL/MariaDB, Redis, Varnish, Memcached, Mailpit, and more**—all in one powerful Docker setup.

> **🔮 Future Roadmap:** Check out the [Coming Soon](#-coming-soon) section to see exciting features we're working on!

---

## ✨ Why PHP Turbo Stack?

*   **🔥 Dual Modes**:
    *   **Hybrid Mode**: Nginx (Proxy) → Varnish → Apache (Webserver). Best for compatibility.
    *   **Thunder Mode**: Nginx (Webserver) → PHP-FPM. Best for performance.
*   **🐘 Multiple PHP Versions**: Switch instantly between PHP 7.4 to 8.4.
*   **💾 Database Freedom**: Choose MySQL (5.7 - 8.4) or MariaDB (10.3 - 11.4).
    *   *Coming Soon: MongoDB & PostgreSQL support.*
*   **⚡ Caching Suite**: Pre-configured **Redis**, **Memcached**, and **Varnish**.
*   **🔒 Smart SSL**:
    *   **Local**: Zero-config trusted certificates for `.localhost` domains via **mkcert**.
    *   **Public**: Automatic Let's Encrypt certificates via **Certbot**.
*   **🛠 Developer Tools**:
    *   **phpMyAdmin**: Database management.
    *   **Mailpit**: Catch-all SMTP server for email testing.
    *   **Xdebug**: Ready-to-go debugging.
*   **🤖 Automation**: A powerful `tbs.sh` (Turbo Stack) script to manage sites, certs, and configs.

---

## 🚀 Getting Started

### Prerequisites

The stack is designed to work on **macOS, Linux, Windows, and other Unix-like systems**. Requirements vary based on your installation type (local development vs. live/production).

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

*   **macOS**: 
    *   Apple Silicon (M1/M2/M3): Fully supported; MariaDB recommended for best compatibility
    *   Intel Macs: All database options available
*   **Linux**: 
    *   Works on most distributions (Ubuntu, Debian, CentOS, Fedora, Arch, etc.)
    *   May require `sudo` for Docker commands (add user to `docker` group)
*   **Windows**: 
    *   Requires WSL 2 (Windows Subsystem for Linux) for Docker Desktop
    *   Use Git Bash or WSL terminal for running `tbs.sh` script
*   **Other Unix-like Systems** (FreeBSD, OpenBSD, etc.):
    *   Docker Engine support varies; check Docker documentation for your OS
    *   Bash compatibility required for `tbs.sh` script

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

## 🛠️ The `tbs` Helper Script

Manage your entire stack with simple commands.

| Command | Description |
| :--- | :--- |
| `tbs` | Open the interactive Turbo Stack menu. |
| `tbs start` | Start all services (Docker Compose profiles based on `STACK_MODE` and `APP_ENV`). |
| `tbs stop` | Stop services and remove orphans. |
| `tbs restart` | Restart the stack with the current profiles. |
| `tbs build` | Rebuild images (e.g., after adding PHP extensions) and start the stack. |
| `tbs status` | Show running containers (`docker compose ps`). |
| `tbs logs [service]` | Stream logs for all services or for a specific service. |
| `tbs config` | Wizard to change PHP version, DB, environment, or Stack Mode and update `.env` |
| `tbs addapp <name> [domain]` | Create a new site (Apache + Nginx vhost, SSL, document root under `www/applications`). Default domain: `<name>.localhost`. |
| `tbs removeapp <name> [domain]` | Remove app vhost(s), optional app files, and related SSL certs. |
| `tbs code <name>` | Open a project folder in VS Code. `tbs code` (without name) lets you pick an app. |
| `tbs ssl <domain>` | Force SSL generation for an existing domain (Certbot for live, mkcert for local). |
| `tbs ssl-localhost` | Generate trusted SSL certs for `localhost` and reload Nginx/Apache. |
| `tbs phpconfig <app>` | Configure per-application PHP settings (memory, upload limits, timeouts, etc.). |
| `tbs backup` | Backup all user databases and `www/applications` to `data/backup`. |
| `tbs restore` | Restore databases and app files from a backup archive. |

### Project Creators
| Command | Description |
| :--- | :--- |
| `tbs create laravel <name>` | Create a new Laravel project with Composer |
| `tbs create wordpress <name>` | Create WordPress site with auto database setup |
| `tbs create symfony <name>` | Create a new Symfony project |
| `tbs create blank <name>` | Create a blank PHP project |

### Database Management
| Command | Description |
| :--- | :--- |
| `tbs db list` | List all databases |
| `tbs db create <name>` | Create a new database |
| `tbs db drop <name>` | Drop a database (with confirmation) |
| `tbs db import <name> <file>` | Import SQL file (supports .sql and .sql.gz) |
| `tbs db export <name>` | Export database to SQL file |
| `tbs db user <name> [pass] [db]` | Create MySQL user with database access |

### Shell Access
| Command | Description |
| :--- | :--- |
| `tbs shell` | Interactive container shell selection |
| `tbs shell php` | Access PHP/Webserver container |
| `tbs shell mysql` | Access MySQL/MariaDB container |
| `tbs shell redis` | Access Redis container |
| `tbs shell nginx` | Access Nginx container |

### System Information
| Command | Description |
| :--- | :--- |
| `tbs info` | Show complete stack status and configuration |
| `tbs info php` | Show PHP version and loaded extensions |
| `tbs info mysql` | Show MySQL version and databases |
| `tbs info redis` | Show Redis server information |

### Tool Shortcuts
| Command | Description | URL |
| :--- | :--- | :--- |
| `tbs pma` | phpMyAdmin | [http://localhost:8080](http://localhost:8080) |
| `tbs mail` | Mailpit | [http://localhost:8025](http://localhost:8025) |
| `tbs redis-cli` | Redis CLI | - |
| `tbs cmd` | PHP Shell | - |

#### If `tbs` is not found (manual install)
The script auto-installs a shim, but if your shell still cannot find `tbs`, set it up once:
- Linux/mac/WSL/Git Bash:
  ```bash
  mkdir -p ~/.local/bin
  cat > ~/.local/bin/tbs <<'EOF'
  #!/bin/bash
  exec "/path/to/your/clone/tbs.sh" "$@"
  EOF
  chmod +x ~/.local/bin/tbs
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
  source ~/.bashrc
  ```
- Windows PowerShell (User PATH):
  ```powershell
  $bin="$HOME\.local\bin"; New-Item -ItemType Directory -Force -Path $bin | Out-Null
  Set-Content -Path "$bin\tbs.cmd" -Value "@echo off`n\"%ProgramFiles%\Git\bin\bash.exe\" \"D:/path/to/your/clone/tbs.sh\" %*"
  [Environment]::SetEnvironmentVariable("Path", "$bin;" + $env:Path, "User")
  ```
- Windows CMD (per-session):
  ```cmd
  set "PATH=%UserProfile%\.local\bin;%PATH%"
  ```
Then open a new shell and run `tbs status`.

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

## � Per-Application PHP Configuration

Turbo Stack allows you to customize PHP settings for individual applications without affecting other apps.

### Using `tbs phpconfig`

```bash
# Configure PHP settings for a specific app
tbs phpconfig myapp

# Interactive menu to select an app
tbs phpconfig
```

### Available Settings

| Setting | Description | Default |
| :--- | :--- | :--- |
| `memory_limit` | Maximum memory per script | `256M` |
| `upload_max_filesize` | Maximum upload file size | `64M` |
| `post_max_size` | Maximum POST data size | `64M` |
| `max_execution_time` | Script timeout (seconds) | `300` |
| `max_input_time` | Input parsing timeout | `300` |
| `max_input_vars` | Maximum input variables | `5000` |

### How It Works

- **Hybrid Mode (Apache)**: Creates a `user.ini` file in your app's root directory
- **Thunder Mode (PHP-FPM)**: Creates a dedicated FPM pool config in `sites/php/pools/`

### Config File Locations

| Mode | Config Location | Auto-reload |
| :--- | :--- | :--- |
| Hybrid | `www/applications/<app>/user.ini` | Yes (every 5 min) |
| Thunder | `sites/php/pools/<app>.conf` | Requires `tbs restart` |

> **Note:** Per-app configs in `sites/php/pools/` are gitignored by default, keeping your repository clean.

---

## 🎛️ Per-Application Configuration

Turbo Stack provides comprehensive per-application control through the `tbs appconfig` command.

### Using `tbs appconfig`

```bash
# Show all apps and their configuration status
tbs appconfig

# View configuration for a specific app
tbs appconfig myapp show

# Toggle Varnish caching for an app
tbs appconfig myapp varnish enable
tbs appconfig myapp varnish disable

# Change webroot (e.g., for Laravel's public folder)
tbs appconfig myapp webroot public

# Domain management
tbs appconfig myapp domain add staging.example.com
tbs appconfig myapp domain remove staging.example.com
tbs appconfig myapp domain primary www.example.com

# Create dedicated database for app
tbs appconfig myapp database

# Reset file permissions
tbs appconfig myapp permissions

# Supervisor (background workers/queues)
tbs appconfig myapp supervisor add laravel-queue "php artisan queue:work"
tbs appconfig myapp supervisor remove laravel-queue
tbs appconfig myapp supervisor list

# Cron jobs
tbs appconfig myapp cron add "every-minute" "* * * * *" "php artisan schedule:run"
tbs appconfig myapp cron remove "every-minute"
tbs appconfig myapp cron list

# Application logs
tbs appconfig myapp logs enable
tbs appconfig myapp logs disable
tbs appconfig myapp logs tail
```

### Configuration Storage

Each app's configuration is stored as JSON in `sites/apps/<app_name>.json`:

```json
{
  "name": "myapp",
  "domains": ["myapp.localhost", "www.myapp.com"],
  "primary_domain": "myapp.localhost",
  "webroot": "public",
  "varnish": true,
  "database": {
    "name": "myapp_db",
    "user": "myapp_user",
    "created": true
  },
  "logs": {
    "enabled": true,
    "path": "logs"
  },
  "supervisor": {
    "enabled": true,
    "programs": ["laravel-queue"]
  },
  "cron": {
    "enabled": true,
    "jobs": ["scheduler"]
  },
  "ssh": {
    "enabled": true,
    "username": "myapp_ssh",
    "password": "auto_generated",
    "port": 2244
  },
  "permissions": {
    "owner": "myapp_ssh",
    "group": "myapp_ssh"
  }
}
```

### Feature Overview

| Feature | Command | Description |
| :--- | :--- | :--- |
| **Varnish Toggle** | `varnish enable/disable` | Enable/disable caching per app |
| **Custom Webroot** | `webroot <path>` | Change document root (e.g., `public`) |
| **Domain Management** | `domain add/remove/primary` | Manage multiple domains |
| **Database per App** | `database` | Create dedicated MySQL user & database |
| **SSH/SFTP Access** | `ssh enable/disable/reset` | Per-app SSH user with isolated access |
| **Permissions Reset** | `permissions` | Reset ownership to www-data |
| **Supervisor Jobs** | `supervisor add/remove/list` | Manage background workers |
| **Cron Jobs** | `cron add/remove/list` | Manage scheduled tasks |
| **App Logs** | `logs enable/disable/tail` | Per-app logging configuration |

### Per-App SSH/SFTP Access

Each application can have its own SSH/SFTP user for secure file access:

```bash
# Enable SSH for an app (generates random username/password)
tbs appconfig myapp ssh enable

# Output:
#   Username: myapp_ssh
#   Password: <random_16_char>
#   Port:     2244

# Connect via SFTP
sftp -P 2244 myapp_ssh@localhost

# Regenerate password
tbs appconfig myapp ssh reset

# Disable/Delete access
tbs appconfig myapp ssh disable
tbs appconfig myapp ssh delete
```

**Key Features:**
- **Unique SSH user** per application
- **Auto-generated** secure credentials
- **Chroot jail** - users can only access their app directory
- **File ownership** - app files owned by SSH user (not www-data)
- **Toggle on/off** without deleting credentials

> **Note:** Start SSH service with: `docker compose --profile ssh up -d ssh`

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
│   ├── nginx/           # Active Nginx configs per app / mode
│   ├── php/pools/       # Per-app PHP-FPM pool configs (gitignored)
│   └── ssl/             # Generated SSL certs (mkcert / Let's Encrypt)
├── www/                 # Web root inside containers
│   ├── applications/    # Your project folders (created via `tbs addapp`)
│   └── index.php        # Landing page
└── tbs.sh               # Turbo Stack helper/automation script
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

## ⚠️ Production Usage
1.  Set `APP_ENV=production` in `.env`.
2.  **Change all passwords** in `.env`.
3.  Disable `INSTALL_XDEBUG`.
4.  Ensure `STACK_MODE` is set correctly for your needs.

For more details, see `SECURITY.md`. For release notes, see `CHANGELOG.md`.

---

## 🔮 Coming Soon

We're constantly improving Turbo Stack! Here's what's on our roadmap:

### 🐘 PHP Enhancements

| Feature | Description | Status |
| :--- | :--- | :---: |
| **PHP 8.5** | Support for upcoming PHP 8.5 release | 🔜 Planned |
| **ionCube Loader** | ionCube PHP Encoder support for encoded applications | 🔜 Planned |

### 🎛️ Per-Application Controls

| Feature | Description | Status |
| :--- | :--- | :---: |
| **Varnish Toggle** | Enable/disable Varnish caching per application | ✅ Done |
| **SSH Shell Access** | Secure shell access to individual app containers | ✅ Done |
| **Supervisord Jobs** | Per-app background process management (queues, workers) | ✅ Done |
| **Cron Jobs** | Application-specific scheduled tasks | ✅ Done |
| **Custom Webroot** | Change document root path (e.g., `public`, `web`, `public_html`) | ✅ Done |
| **Permission Reset** | One-click file/folder ownership & permission reset | ✅ Done |

### 🌐 Domain & Routing

| Feature | Description | Status |
| :--- | :--- | :---: |
| **Multi-Domain Support** | Add multiple domains/aliases per application | ✅ Done |
| **Domain Management** | Add, remove, change domains (with primary domain protection) | ✅ Done |
| **Web Rules** | Custom header rules and URL rewrite rules per app | 🔜 Planned |

### 📁 Application Structure Improvements

| Feature | Description | Status |
| :--- | :--- | :---: |
| **App-Specific Logs** | Logs stored in `applications/<app>/logs/` | ✅ Done |
| **New Webroot Standard** | Document root at `applications/<app>/public_html/` | 🔜 Planned |
| **App Data Directory** | Dedicated data storage at `applications/<app>/app_data/` | 🔜 Planned |

### 💾 Database Enhancements

| Feature | Description | Status |
| :--- | :--- | :---: |
| **Per-App Database** | Auto-create MySQL database & user per application | ✅ Done |
| **MongoDB Support** | Full MongoDB integration | 🔜 Planned |
| **PostgreSQL Support** | Full PostgreSQL integration | 🔜 Planned |

### 🚀 Stack Modes

| Feature | Description | Status |
| :--- | :--- | :---: |
| **Node.js Mode** | Full Node.js application support with PM2 | 🔜 Planned |

### 📊 Monitoring & Observability

| Feature | Description | Status |
| :--- | :--- | :---: |
| **New Relic APM** | Application Performance Monitoring (optional, paid) | 🔜 Planned |
| **Prometheus + Grafana** | Self-hosted metrics & beautiful dashboards | 🔜 Planned |
| **Sentry** | Error tracking & crash reporting | 🔜 Planned |
| **Health Checks** | Automated service health monitoring | 🔜 Planned |

---

> 💡 **Want to contribute?** Pick a feature from the roadmap and submit a PR! Check our [Contributing](#-contributing) section.

---

## 🤝 Contributing
Pull Requests are welcome!

## 📄 License
MIT License.
