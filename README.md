# LAMP Stack Built with Docker Compose

A comprehensive LAMP stack environment built using Docker Compose, featuring:

- PHP
- Apache
- MySQL
- phpMyAdmin
- Redis

> **Note:** This Docker Stack is intended for local development and is not suitable for production use.

## Installation

1. **Clone the repository:**
    ```sh
    git clone https://github.com/kevinpareek/lamp-docker.git
    cd lamp-docker
    ```

2. **Configure environment variables:**
    ```sh
    ./lamp.sh config
    ```
    Follow the prompts to set up the necessary environment variables.

3. **Build and start the LAMP stack:**
    ```sh
    ./lamp.sh start
    ```

## Usage

### Starting and Stopping the LAMP Stack

- **Start:**
    ```sh
    ./lamp.sh start
    ```

- **Stop:**
    ```sh
    ./lamp.sh stop
    ```

- **Restart:**
    ```sh
    ./lamp.sh restart
    ```

### Accessing Services

- **Web Server:** Accessible at `http://localhost` or `https://localhost` (if SSL is configured).
- **phpMyAdmin:** Accessible at `http://localhost:8080` or `https://localhost:8443`.

### Creating & Managing Applications

- **Add a new application:**
    Ensure your custom domain (e.g., example.com) points to 127.0.0.1 if not using the default localhost.

    ```sh
    ./lamp.sh addapp <app_name> [domain]
    ```
    - `<app_name>`: Name of the application.
    - `[domain]`: (Optional) Custom domain, defaults to `<app_name>.localhost`.
    - Place your code in `[DOCUMENT_ROOT]/[APPLICATIONS_DIR_NAME]/<app_name>`.
    - Create a database in phpMyAdmin (`http://localhost:8080`) named `sql_<app_name>`.

- **Open application code in VS Code:**
    ```sh
    ./lamp.sh code <app_name>
    ```
    - `<app_name>`: Name of the application. If omitted, you'll be prompted to select an application.

### Backup and Restore

- **Backup:**
    ```sh
    ./lamp.sh backup
    ```

- **Restore:**
    ```sh
    ./lamp.sh restore
    ```

### Connect via SSH

following command to log in to the container via SSH:
```sh
./lamp.sh cmd
```

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