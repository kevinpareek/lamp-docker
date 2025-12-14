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
    *   **Local**: Zero-config self-signed certs for `.localhost` domains.
    *   **Public**: Automatic Let's Encrypt certificates via **Certbot**.
*   **🛠 Developer Tools**:
    *   **phpMyAdmin**: Database management.
    *   **Mailpit**: Catch-all SMTP server for email testing.
    *   **Xdebug**: Ready-to-go debugging.
*   **🤖 Automation**: A powerful `lamp.sh` script to manage sites, certs, and configs.

---

## 🚀 Getting Started

### Prerequisites
*   Docker Desktop (or Engine + Compose)
*   Git & Bash

### Installation

1.  **Clone & Enter:**
    ```bash
    git clone https://github.com/kevinpareek/turbo-stack.git
    cd turbo-stack
    ```

2.  **Configure:**
    Run the wizard to choose your PHP version, Database, and Stack Mode.
    ```bash
    ./lamp.sh config
    ```

3.  **Launch:**
    ```bash
    ./lamp.sh start
    ```

    ### 🌐 Accessing the Dashboard
    You can access the dashboard via:
    *   **http://localhost**
    *   **http://127.0.0.1**
    *   **http://turbostack.in** (Recommended)

    **🔒 SSL/HTTPS:**
    *   **Supported:** [https://turbostack.in](https://turbostack.in)
    *   **Not Supported:** `https://localhost`

---

## 🛠️ The `lamp` Helper Script

Manage your entire stack with simple commands.

| Command | Description |
| :--- | :--- |
| `lamp start` | Start all services. |
| `lamp stop` | Stop services. |
| `lamp restart` | Restart the stack. |
| `lamp build` | Rebuild images (e.g., after adding PHP extensions). |
| `lamp config` | Change PHP version, DB, or Stack Mode. |
| `lamp addapp <name> <domain>` | Create a new site (e.g., `lamp addapp myapp myapp.test`). |
| `lamp code <name>` | Open a project in VS Code. |
| `lamp ssl <domain>` | Force SSL generation (Certbot). |
| `lamp backup` / `restore` | Backup or restore all data. |

### Tool Shortcuts
| Command | Description | URL |
| :--- | :--- | :--- |
| `lamp pma` | phpMyAdmin | [http://localhost:8080](http://localhost:8080) |
| `lamp mail` | Mailpit | [http://localhost:8025](http://localhost:8025) |
| `lamp redis-cli` | Redis CLI | - |
| `lamp cmd` | PHP Shell | - |

---

## ⚙️ Architecture & Modes

You can switch modes in `.env` or via `lamp config`.

### 1. Hybrid Mode (Default)
**Nginx (Proxy) ➡ Varnish ➡ Apache ➡ PHP**
*   Combines Nginx's static file handling with Apache's `.htaccess` flexibility.
*   Ideal for legacy apps, WordPress, or projects needing Apache-specific rules.

### 2. Thunder Mode (LEMP)
**Nginx ➡ PHP-FPM**
*   Pure Nginx performance.
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
├── bin/                 # Dockerfiles (PHP, Nginx, DBs)
├── config/              # Configuration Files
│   ├── initdb/          # SQL scripts to run on DB init
│   ├── mariadb/         # Custom my.cnf
│   ├── nginx/           # Nginx sites & templates
│   ├── php/             # php.ini, supervisord
│   ├── ssl/             # Default SSL certs
│   ├── varnish/         # VCL configurations
│   └── vhosts/          # Apache VHosts
├── data/                # Persistent Data (DB, Redis, Backups)
├── logs/                # Logs (Apache, Nginx, MySQL)
├── sites/               # Generated Configs (Do not edit manually)
│   ├── apache/          # Active Apache VHosts
│   ├── nginx/           # Active Nginx Configs
│   └── ssl/             # Let's Encrypt Certs
├── www/                 # Document Root
│   ├── applications/    # Your Projects
│   └── index.php        # Dashboard
└── lamp.sh              # Automation Script
```

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
Edit `./bin/php<version>/Dockerfile` (e.g., `./bin/php8.2/Dockerfile`) and run `lamp build`.

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
