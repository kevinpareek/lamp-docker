# 🚀 PHP Turbo Stack (Docker LAMP & LEMP)

**The most complete, flexible, and production-ready local development environment for PHP.**

Stop wasting time configuring servers. This stack gives you everything you need—**Apache, Nginx, MySQL/MariaDB, Redis, Varnish, Memcached, Mailpit, and more**—all in one powerful Docker setup.

> **🔮 Future Roadmap:** We are actively working on adding support for **Node.js**, **MongoDB**, and **PostgreSQL**. Stay tuned!

---

## ✨ Why PHP Turbo Stack?

*   **🔥 Dual Modes**:
    *   **Hybrid Mode**: Nginx (Proxy) → Varnish → Apache (Webserver). Best for compatibility.
    *   **Thunder Mode**: Nginx (Webserver) → PHP-FPM. Best for performance.
*   **🐘 Multiple PHP Versions**: Switch instantly between PHP 5.4 to 8.4.
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
The stack is designed to work on **macOS, Linux, and Windows**. Ensure you have the following installed:

*   **Docker Desktop** (or Engine + Compose)
*   **Git** & **Bash** (Git Bash recommended for Windows)
*   **Required Utilities**: `curl`, `sed` (Standard on macOS/Linux; included with Git Bash on Windows)
*   **mkcert** (For trusted local SSL) - *The script can automatically install this for you!*

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
| `tbs backup` | Backup all user databases and `www/applications` to `data/backup`. |
| `tbs restore` | Restore databases and app files from a backup archive. |

### Tool Shortcuts
| Command | Description | URL |
| :--- | :--- | :--- |
| `tbs pma` | phpMyAdmin | [http://localhost:8080](http://localhost:8080) |
| `tbs mail` | Mailpit | [http://localhost:8025](http://localhost:8025) |
| `tbs redis-cli` | Redis CLI | - |
| `tbs cmd` | PHP Shell | - |

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
*   *Note: `.htaccess` files are ignored in this mode.*

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

## 📂 Directory Structure

```text
├── bin/                 # Docker build context for PHP, Nginx, MySQL/MariaDB images
├── config/              # Source-of-truth configuration (mounted into containers)
│   ├── initdb/          # Put .sql/.sql.gz files here → auto-run on first DB container start
│   ├── mariadb/         # Custom MySQL/MariaDB configs (e.g. my.cnf)
│   ├── nginx/           # Nginx templates, partials, and mode configs
│   ├── php/             # php.ini variants, FPM pool, supervisord configs
│   ├── varnish/         # VCL configurations for Hybrid / Thunder modes
│   └── vhosts/          # Base Apache vhost templates used by tbs.sh
├── data/                # Persistent data volumes (DB, Redis, backups)
├── logs/                # Logs for web, DB, and services (Apache, Nginx, MySQL, etc.)
├── sites/               # Generated configs (managed by tbs.sh – do NOT edit manually)
│   ├── apache/          # Active Apache vhosts for your apps
│   ├── nginx/           # Active Nginx configs per app / mode
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
| **Memcached** | 11211 | `11211` (Internal Only) |

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

---

## 🤝 Contributing
Pull Requests are welcome!

## 📄 License
MIT License.
