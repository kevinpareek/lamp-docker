# 🐳 Ultimate Docker LAMP Stack

Welcome to your new favorite local development environment! This project provides a robust, production-ready LAMP (Linux, Apache, MySQL/MariaDB, PHP) stack powered by Docker Compose. It's designed to be **easy to use**, **highly configurable**, and **developer-friendly**.

Whether you're a seasoned Docker pro or just getting started, this stack has you covered. We've included a powerful helper script, `lamp.sh`, to automate common tasks, but you can also use standard Docker commands if you prefer.

---

## ✨ Features

*   **Multiple PHP Versions**: Switch between PHP 5.4 to 8.5 easily.
*   **Database Choice**: Choose between MySQL (5.7, 8.0) or MariaDB (10.3 - 11.4).
*   **Automatic SSL**: Built-in `mkcert` integration for valid HTTPS on local domains.
*   **VHost Management**: Create new sites with a single command.
*   **Developer Tools**:
    *   **phpMyAdmin**: Database management.
    *   **Mailpit**: Catch-all SMTP server for testing emails.
    *   **Redis**: In-memory data structure store.
    *   **Xdebug**: Pre-configured for debugging.
*   **Backup & Restore**: One-click backup and restore functionality.

---

## 🚀 Getting Started

### Prerequisites

*   **Docker Desktop** (or Docker Engine + Compose Plugin)
*   **Git**
*   **Bash** (for the helper script)

### Installation

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/kevinpareek/lamp-docker.git
    cd lamp-docker
    ```

2.  **Configure your environment:**
    Run the configuration wizard to set up your preferences (PHP version, Database type, etc.).
    ```bash
    ./lamp.sh config
    ```

3.  **Start the stack:**
    ```bash
    ./lamp.sh start
    ```
    *This will build the images (if needed) and start the services. It also adds a `lamp` alias to your shell profile for easier access!*

---

## 🛠️ Using the `lamp` Helper Script

The `lamp.sh` script is your command center. Once installed, you can just type `lamp` followed by a command.

### Core Commands

| Command | Description |
| :--- | :--- |
| `lamp start` | Start all services and open the dashboard. |
| `lamp stop` | Stop all running services. |
| `lamp restart` | Restart the stack. |
| `lamp build` | Rebuild the Docker images (useful after changing PHP extensions). |
| `lamp config` | Re-run the configuration wizard. |

### Application Management

This is where the magic happens! Create new isolated environments for your projects instantly.

**Create a new app:**
```bash
lamp addapp <app_name> [domain]
```
*   **Example:** `lamp addapp myproject myproject.test`
*   Creates a new folder in `www/applications/myproject`.
*   Sets up Apache Virtual Host and Nginx Proxy.
*   Generates SSL certificates automatically.
*   Reloads the servers.
*   *Note: For custom domains like `.test`, make sure to add `127.0.0.1 myproject.test` to your machine's hosts file.*

**Open in VS Code:**
```bash
lamp code <app_name>
```

### Tools & Utilities

| Command | Description |
| :--- | :--- |
| `lamp cmd` | Open a Bash shell inside the PHP container. |
| `lamp pma` | Open phpMyAdmin in your browser. |
| `lamp mail` | Open Mailpit (email catcher) in your browser. |
| `lamp redis-cli` | Open the Redis command-line interface. |
| `lamp ssl <domain>` | Manually generate SSL certs for a domain. |

### Data Management

| Command | Description |
| :--- | :--- |
| `lamp backup` | Backup all databases and application files to `data/backup`. |
| `lamp restore` | Restore the stack from a previous backup. |

---

## 🐢 Using Without `lamp.sh` (Manual Mode)

Prefer standard Docker commands? No problem! Here is how to manage the stack manually.

### Basic Control

*   **Start:** `docker compose up -d`
*   **Stop:** `docker compose down`
*   **Logs:** `docker compose logs -f`

### Accessing Containers

*   **PHP Shell:** `docker compose exec webserver bash`
*   **MySQL Shell:** `docker compose exec database mysql -u root -p`
*   **Redis Shell:** `docker compose exec redis redis-cli`

### Adding a New App (The Hard Way)

Without the script, you'll need to do the following manually:
1.  Create a folder: `mkdir -p www/applications/myapp`
2.  Create an Apache VHost config in `config/vhosts/myapp.conf`.
3.  Create an Nginx config in `config/nginx/myapp.conf`.
4.  Generate SSL certs and place them in `config/ssl/`.
5.  Restart containers: `docker compose restart`

---

## 📂 Directory Structure

```text
├── bin/                 # Dockerfiles for different PHP/DB versions
├── config/              # Configuration files
│   ├── apache/          # Global Apache config
│   ├── nginx/           # Nginx proxy config
│   ├── php/             # PHP.ini settings
│   ├── vhosts/          # Apache Virtual Hosts (auto-generated)
│   └── ssl/             # SSL Certificates (auto-generated)
├── data/                # Persistent data
│   ├── mysql/           # Database files
│   └── backup/          # Backups created by lamp backup
├── logs/                # Server logs (Apache, Nginx, MySQL)
├── www/                 # Document Root
│   ├── applications/    # Your project folders go here
│   └── index.php        # Dashboard
├── docker-compose.yml   # Main Docker service definition
└── lamp.sh              # The magic helper script
```

---

## ❓ FAQ & Troubleshooting

**Q: My custom domain isn't working!**
A: Did you add it to your hosts file?
*   **Windows:** `C:\Windows\System32\drivers\etc\hosts`
*   **macOS/Linux:** `/etc/hosts`
Add the line: `127.0.0.1 yourdomain.com`

**Q: How do I change the PHP version?**
A: Run `lamp config` and select a different version, or edit the `.env` file directly and run `lamp build`.

**Q: Where are my database files?**
A: They are persisted in `data/mysql`. They survive container restarts.

**Q: I see "File already exists" errors.**
A: The `lamp.sh` script tries to be safe. If you're trying to overwrite something, you might need to delete the old one manually or check permissions.

---

Made with ❤️ for developers. Happy Coding!

- **phpMyAdmin:**
    ```sh
    ./lamp.sh pma
    ```
    Opens phpMyAdmin at `http://localhost:8080`.

- **Redis CLI:**
    ```sh
    ./lamp.sh redis-cli
    ```
    Opens Redis CLI inside the container.

## SSL Certificates

- **Generate SSL certificates for a domain:**
    ```sh
    ./lamp.sh ssl <domain>
    ```
    - `<domain>`: The domain for which to generate SSL certificates.

We use tool like [mkcert](https://github.com/FiloSottile/mkcert#installation) to create an SSL certificate. So need to 
install mkcert first to generate SSL certificates.


## Configuration

- This package comes with default configuration options. You can modify them by creating a `.env` file in your root directory. 
To make it easy, just copy the content from the `sample.env` file and update the environment variable values as per your need.

- The installed version of PHP and MYSQL depends on your `.env` file.


### Apache Modules

By default, the following modules are enabled:
- rewrite
- headers

> If you want to enable more modules, update `./bin/phpX/Dockerfile`. Rebuild the Docker image by running `docker compose 
build` and restart the Docker containers.


### Extensions

By default, the following extensions are installed (may differ for PHP versions <7.x.x):
- mysqli
- pdo_sqlite
- pdo_mysql
- mbstring
- zip
- intl
- mcrypt
- curl
- json
- iconv
- xml
- xmlrpc
- gd

> If you want to install more extensions, update `./bin/webserver/Dockerfile`. Rebuild the Docker image by running `docker 
compose build` and restart the Docker containers.

## phpMyAdmin

phpMyAdmin is configured to run on port 8080. Use the following default credentials:
- URL: `http://localhost:8080/`
- Username: `root`
- Password: `tiger`

## Xdebug

Xdebug comes installed by default, and its version depends on the PHP version chosen in the `.env` file.

**Xdebug versions:**
- PHP <= 7.3: Xdebug 2.X.X
- PHP >= 7.4: Xdebug 3.X.X

To use Xdebug, enable the settings in the `./config/php/php.ini` file according to the chosen PHP version.

Example:
```ini
# Xdebug 2
#xdebug.remote_enable=1
#xdebug.remote_autostart=1
#xdebug.remote_connect_back=1
#xdebug.remote_host = host.docker.internal
#xdebug.remote_port=9000

# Xdebug 3
#xdebug.mode=debug
#xdebug.start_with_request=yes
#xdebug.client_host=host.docker.internal
#xdebug.client_port=9003
#xdebug.idekey=VSCODE
```

### Xdebug VS Code

Install the Xdebug extension "PHP Debug" in VS Code. Create the launch file so that your IDE can listen and work properly.

Example:
```json
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "Listen for Xdebug",
            "type": "php",
            "request": "launch",
            // "port": 9000, // Xdebug 2
            "port": 9003, // Xdebug 3
            "pathMappings": {
                // "/var/www/html": "${workspaceFolder}/www" // if you have opened VSCODE in root folder
                "/var/www/html": "${workspaceFolder}" // if you have opened VSCODE in ./www folder
            }
        }
    ]
}
```

Make a breakpoint and run debug. After these configurations, you may need to restart the container.

## Redis

Redis runs on the default port `6379`.


## Contributing

We welcome contributions! If you want to create a pull request, please remember that this stack is not built for production 
usage, and changes should be good for general purposes and not overspecialized.

> Please note that we simplified the project structure from several branches for each PHP version to one centralized master 
branch. Please create your PR against the master branch.

## Why You Shouldn't Use This Stack Unmodified in Production

This stack is designed for local development to quickly create creative applications. In production, you should modify at a 
minimum the following subjects:
- PHP handler: mod_php => php-fpm
- Secure MySQL users with proper source IP limitations

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.