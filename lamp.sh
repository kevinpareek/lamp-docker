#!/bin/bash

# Get lamp script directory
lampFile=$(readlink -f "$0")
lampPath=$(dirname "$lampFile")
# echo $lampPath;

# Allowed TLDs for application domains
ALLOWED_TLDS="\.localhost|\.com|\.org|\.net|\.info|\.biz|\.name|\.pro|\.aero|\.coop|\.museum|\.jobs|\.mobi|\.travel|\.asia|\.cat|\.tel|\.app|\.blog|\.shop|\.xyz|\.tech|\.online|\.site|\.web|\.store|\.club|\.media|\.news|\.agency|\.guru|\.in|\.co.in|\.ai.in|\.net.in|\.org.in|\.firm.in|\.gen.in|\.ind.in|\.com.au|\.co.uk|\.co.nz|\.co.za|\.com.br|\.co.jp|\.ca|\.de|\.fr|\.cn|\.ru|\.us"

red_message() {
    local RED='\033[0;31m'
    local NC='\033[0m' # No Color
    echo -e "${RED}$1${NC}"
}

error_message() {
    local RED='\033[0;31m'
    local NC='\033[0m' # No Color
    echo -e "${RED}Error: $1${NC}"
}

value_message() {
    local BLUE='\033[0;34m'
    local GREEN='\033[0;32m'
    local NC='\033[0m' # No Color

    echo -e "${BLUE}${1}${NC} ${GREEN}${2}${NC}"
}

blue_message() {
    local BLUE='\033[0;34m'
    local NC='\033[0m' # No Color
    echo -e "${BLUE}$1${NC}"
}

green_message() {
    local GREEN='\033[0;32m'
    local NC='\033[0m' # No Color
    echo -e "${GREEN}$1${NC}"
}

info_message() {
    local CYAN='\033[0;36m'
    local NC='\033[0m' # No Color
    echo -e "${CYAN}$1${NC}"
}

yellow_message() {
    local YELLOW='\033[0;33m'
    local NC='\033[0m' # No Color
    echo -e "${YELLOW}$1${NC}"
}

attempt_message() {
    local count=$1
    local last_attempt=3

    if ((count >= last_attempt)); then
        yellow_message "Attempt ${count} and last. Please try again."
    else
        yellow_message "Attempt ${count}. Please try again."
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Cross-platform sed in-place editing
sed_i() {
    local expression=$1
    local file=$2
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i "" "$expression" "$file"
    else
        sed -i "$expression" "$file"
    fi
}

print_line() {
    echo ""
    printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -
    echo ""
}

yes_no_prompt() {
    while true; do
        read -p "$1 (yes/no): " yn
        case $yn in
        [Yy]*) return 0 ;; # Return 0 for YES
        [Nn]*) return 1 ;; # Return 1 for NO
        *) yellow_message "Please answer yes or no." ;;
        esac
    done
}

install_mkcert() {
    local os_name=$(uname -s)
    
    info_message "Installing mkcert for SSL certificate generation..."
    
    case "$os_name" in
        Darwin)
            # macOS installation
            if command_exists brew; then
                brew install mkcert nss
            else
                error_message "Homebrew not found. Please install Homebrew first: https://brew.sh"
                return 1
            fi
            ;;
        Linux)
            # Linux installation
            if command_exists apt; then
                sudo apt update
                sudo apt install -y libnss3-tools
                curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
                chmod +x mkcert-v*-linux-amd64
                sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert
            elif command_exists yum; then
                sudo yum install -y nss-tools
                curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
                chmod +x mkcert-v*-linux-amd64
                sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert
            elif command_exists pacman; then
                sudo pacman -S --noconfirm nss
                curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
                chmod +x mkcert-v*-linux-amd64
                sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert
            else
                error_message "Unsupported Linux package manager. Please install mkcert manually."
                return 1
            fi
            ;;
        CYGWIN*|MINGW32*|MSYS*|MINGW*)
            # Windows installation
            if command_exists choco; then
                choco install mkcert
            else
                error_message "Chocolatey not found. Please install Chocolatey first: https://chocolatey.org/install"
                return 1
            fi
            ;;
        *)
            error_message "Unsupported operating system: $os_name"
            return 1
            ;;
    esac
    
    # Initialize mkcert and create local CA
    mkcert -install
    return $?
}

generate_ssl_certificates() {
    domain=$1
    vhost_file=$2
    nginx_file=$3

    # Check if mkcert is installed
    if ! command -v mkcert &>/dev/null; then
        if yes_no_prompt "mkcert is not installed. Would you like to install it now?"; then
            if ! install_mkcert; then
                error_message "Failed to install mkcert. SSL certificates cannot be generated."
                return 1
            fi
        else
            yellow_message "SSL certificates not generated. Using http://$domain"
            return 1
        fi
    fi

    # Generate SSL certificates for the domain
    mkdir -p "$lampPath/config/ssl"
    mkcert -key-file "$lampPath/config/ssl/$domain-key.pem" -cert-file "$lampPath/config/ssl/$domain-cert.pem" $domain "*.$domain"

    # Update the vhost configuration file with the correct SSL certificate paths
    sed_i "s|SSLCertificateFile /etc/apache2/ssl/cert.pem|SSLCertificateFile /etc/apache2/ssl/$domain-cert.pem|" $vhost_file
    sed_i "s|SSLCertificateKeyFile /etc/apache2/ssl/cert-key.pem|SSLCertificateKeyFile /etc/apache2/ssl/$domain-key.pem|" $vhost_file

    sed_i "s|ssl_certificate /etc/nginx/ssl/cert.pem|ssl_certificate /etc/nginx/ssl/$domain-cert.pem|" $nginx_file
    sed_i "s|ssl_certificate_key /etc/nginx/ssl/cert-key.pem|ssl_certificate_key /etc/nginx/ssl/$domain-key.pem|" $nginx_file

    info_message "SSL certificates generated for https://$domain"
    return 0
}

open_browser() {
    local domain=$1
    local os_name=$(uname -s)

    # Open the domain in the default web browser
    info_message "Opening $domain in the default web browser..."

    case "$os_name" in
        Darwin)
            open "$domain"
            ;;
        Linux)
            xdg-open "$domain"
            ;;
        CYGWIN* | MINGW32* | MSYS* | MINGW*)
            start "$domain"
            ;;
        *)
            error_message "Unsupported OS: $os_name. Please open $domain manually."
            ;;
    esac
}

lamp_config() {
    # Set required configuration keys
    reqConfig=("APP_ENV" "STACK_MODE" "DOCUMENT_ROOT" "APPLICATIONS_DIR_NAME" "COMPOSE_PROJECT_NAME" "PHPVERSION" "DATABASE")

    # Detect if Apple Silicon
    isAppleSilicon=false
    if [[ $(uname -m) == 'arm64' ]]; then
        isAppleSilicon=true
    fi

    # Function to dynamically fetch PHP versions and databases from ./bin
    fetch_dynamic_versions() {
        local bin_dir="$lampPath/bin"
        phpVersions=()
        mysqlOptions=()
        mariadbOptions=()

        for entry in "$bin_dir"/*; do
            entry_name=$(basename "$entry")
            if [[ -d "$entry" ]]; then
                case "$entry_name" in
                php*)
                    phpVersions+=("$entry_name")
                    ;;
                mysql*)
                    mysqlOptions+=("$entry_name")
                    ;;
                mariadb*)
                    mariadbOptions+=("$entry_name")
                    ;;
                esac
            fi
        done
    }

    # Function to read environment variables from a file (either .env or sample.env)
    read_env_file() {
        local env_file=$1
        while IFS='=' read -r key value; do
            if [[ ! -z $key && ! $key =~ ^# ]]; then
                eval "$key='$value'"
            fi
        done <"$env_file"
    }

    # Function to prompt user to input a valid stack mode
    choose_stack_mode() {
        local valid_options=("hybrid" "thunder")
        echo "Select the STACK_MODE value:"
        select option in "${valid_options[@]}"; do
            if [[ " ${valid_options[*]} " == *" $option "* ]]; then
                STACK_MODE="$option"
                echo "STACK_MODE is set to '$STACK_MODE'."
                break
            else
                echo "Invalid selection. Please choose a valid option."
            fi
        done
    }

    # Function to prompt user to input a valid PHP version
    choose_php_version() {
        value_message "Available PHP versions:" "${phpVersions[*]}"

        while true; do
            read -p "Enter PHP version (Default: $PHPVERSION): " php_choice
            php_choice=${php_choice:-$PHPVERSION}

            if [[ " ${phpVersions[*]} " == *" $php_choice "* ]]; then
                PHPVERSION=$php_choice
                break
            else
                error_message "Invalid PHP version. Please enter a valid PHP version from the list."
            fi
        done
    }

    # Function to prompt user to input a valid database
    choose_database() {
        local legacy_php=false
        if [[ "$PHPVERSION" =~ php5\.[4-6] || "$PHPVERSION" == "php7.1" || "$PHPVERSION" == "php7.2" || "$PHPVERSION" == "php7.3" || "$PHPVERSION" == "php7.4" ]]; then
            legacy_php=true
        fi

        if $isAppleSilicon; then
            yellow_message "Apple Silicon detected. Using MariaDB images for best compatibility."
            databaseOptions=("${mariadbOptions[@]}")
        else
            if $legacy_php; then
                yellow_message "Available databases (MySQL 8+ excluded for PHP <= 7.4):"
                databaseOptions=()
                for db in "${mysqlOptions[@]}"; do
                    if [[ "$db" == "mysql5.7" ]]; then
                        databaseOptions+=("$db")
                    fi
                done
                databaseOptions+=("${mariadbOptions[@]}")
            else
                blue_message "Available databases:"
                databaseOptions=("${mysqlOptions[@]}" "${mariadbOptions[@]}")
            fi
        fi

        if [[ ${#databaseOptions[@]} -eq 0 ]]; then
            error_message "No database options found in ./bin. Please add mysql*/mariadb* folders."
            exit 1
        fi

        green_message "${databaseOptions[*]}"

        while true; do
            read -p "Enter Database (Default: $DATABASE): " db_choice
            db_choice=${db_choice:-$DATABASE}

            if [[ " ${databaseOptions[*]} " == *" $db_choice "* ]]; then
                DATABASE=$db_choice
                break
            else
                error_message "Invalid Database. Please enter a valid database from the list."
            fi
        done
    }

    set_app_env() {
        local valid_options=("development" "production")
        echo "Select the APP_ENV value:"
        select option in "${valid_options[@]}"; do
            if [[ " ${valid_options[*]} " == *" $option "* ]]; then
                export APP_ENV="$option"
                echo "APP_ENV is set to '$APP_ENV'."
                
                # Auto-configure based on environment
                if [[ "$APP_ENV" == "development" ]]; then
                    export INSTALL_XDEBUG="true"
                    export APP_DEBUG="true"
                else
                    export INSTALL_XDEBUG="false"
                    export APP_DEBUG="false"
                fi
                
                # Update these in .env file
                sed_i "s|^INSTALL_XDEBUG=.*|INSTALL_XDEBUG=${INSTALL_XDEBUG}|" .env 2>/dev/null || echo "INSTALL_XDEBUG=${INSTALL_XDEBUG}" >>.env
                sed_i "s|^APP_DEBUG=.*|APP_DEBUG=${APP_DEBUG}|" .env 2>/dev/null || echo "APP_DEBUG=${APP_DEBUG}" >>.env
                
                break
            else
                echo "Invalid selection. Please choose a valid option."
            fi
        done
    }

    # Function to update or create the .env file
    update_env_file() {
        info_message "Updating the .env file..."

        for key in "${reqConfig[@]}"; do
            default_value=$(eval echo \$$key)

            # Handle PHPVERSION and DATABASE separately for prompts
            if [[ "$key" == "PHPVERSION" ]]; then
                choose_php_version
            elif [[ "$key" == "DATABASE" ]]; then
                choose_database
            elif [[ "$key" == "APP_ENV" ]]; then
                set_app_env
            elif [[ "$key" == "STACK_MODE" ]]; then
                choose_stack_mode
            else
                read -p "$key (Default: $default_value): " new_value
                if [[ ! -z $new_value ]]; then
                    eval "$key=$new_value"
                fi
            fi

            # Update the .env file
            sed_i "s|^$key=.*|$key=${!key}|" .env 2>/dev/null || echo "$key=${!key}" >>.env
        done

        # Show environment summary
        print_line
        if [[ "$APP_ENV" == "development" ]]; then
            green_message "✅ Development Environment Configured:"
            info_message "   • Xdebug: Enabled"
            info_message "   • OPcache: Disabled"
            info_message "   • Error Display: On"
            info_message "   • phpMyAdmin: Available on port $HOST_MACHINE_PMA_PORT"
            info_message "   • Mailpit: Available on port 8025"
            info_message "   • PHP Config: php.development.ini"
        else
            green_message "✅ Production Environment Configured:"
            info_message "   • Xdebug: Disabled"
            info_message "   • OPcache: Enabled with JIT"
            info_message "   • Error Display: Off (logged)"
            info_message "   • phpMyAdmin: Disabled"
            info_message "   • Mailpit: Disabled"
            info_message "   • PHP Config: php.production.ini"
            yellow_message "   ⚠️  Remember to change default database passwords!"
        fi
        print_line

        green_message ".env file updated!"
    }

    update_local_document_indexFile() {
        local indexFilePath=$(readlink -f "$lampPath/$DOCUMENT_ROOT/config.php")
        local newLocalDocumentRoot=$(dirname "$indexFilePath")

        if [ -f "$indexFilePath" ]; then
            sed_i "s|\$LOCAL_DOCUMENT_ROOT = '.*';|\$LOCAL_DOCUMENT_ROOT = '$newLocalDocumentRoot';|" "$indexFilePath"
            sed_i "s|\$APACHE_DOCUMENT_ROOT = '.*';|\$APACHE_DOCUMENT_ROOT = '$APACHE_DOCUMENT_ROOT';|" "$indexFilePath"
            sed_i "s|\$APPLICATIONS_DIR_NAME = '.*';|\$APPLICATIONS_DIR_NAME = '$APPLICATIONS_DIR_NAME';|" "$indexFilePath"

            sed_i "s|\$MYSQL_HOST = '.*';|\$MYSQL_HOST = 'database';|" "$indexFilePath"
            sed_i "s|\$MYSQL_DATABASE = '.*';|\$MYSQL_DATABASE = '$MYSQL_DATABASE';|" "$indexFilePath"
            sed_i "s|\$MYSQL_USER = '.*';|\$MYSQL_USER = '$MYSQL_USER';|" "$indexFilePath"
            sed_i "s|\$MYSQL_PASSWORD = '.*';|\$MYSQL_PASSWORD = '$MYSQL_PASSWORD';|" "$indexFilePath"

            sed_i "s|\$PMA_PORT = '.*';|\$PMA_PORT = '$HOST_MACHINE_PMA_PORT';|" "$indexFilePath"

            green_message "Config DATA updated in $indexFilePath"
        else
            error_message "config.php file not found at $indexFilePath"
        fi
    }

    # Main logic
    if [ -f .env ]; then
        info_message "Reading config from .env..."
        read_env_file ".env"
    elif [ -f sample.env ]; then
        yellow_message "No .env file found, using sample.env..."
        cp sample.env .env
        read_env_file "sample.env"
    else
        error_message "No .env or sample.env file found."
        exit 1
    fi

    # Fetch dynamic PHP versions and database list from ./bin directory
    fetch_dynamic_versions

    # Display current configuration and prompt for updates
    update_env_file

    update_local_document_indexFile
}

lamp_start() {
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        yellow_message "Docker daemon is not running. Starting Docker daemon..."

        # Check the OS and start Docker accordingly
        case "$(uname -s)" in
        Darwin)
            open -a Docker
            ;;
        Linux)
            sudo systemctl start docker
            ;;
        CYGWIN* | MINGW32* | MSYS* | MINGW*)
            start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
            ;;
        *)
            error_message "Unsupported OS. Please start Docker manually."
            exit 1
            ;;
        esac

        # Wait for Docker to start (max 60 seconds)
        local timeout=60
        local elapsed=0
        while ! docker info >/dev/null 2>&1; do
            if [ $elapsed -ge $timeout ]; then
                error_message "Docker failed to start within ${timeout} seconds."
                exit 1
            fi
            yellow_message "Waiting for Docker to start... (${elapsed}s)"
            sleep 2
            elapsed=$((elapsed + 2))
        done
        info_message "Docker is running."
    fi

    # Build and start containers
    info_message "Starting LAMP stack (${APP_ENV} mode, ${STACK_MODE:-hybrid} stack)..."
    
    PROFILES="--profile ${STACK_MODE:-hybrid}"
    if [[ "$APP_ENV" == "development" ]]; then
        PROFILES="$PROFILES --profile development"
    fi

    if ! docker compose $PROFILES up -d --build; then
        error_message "Failed to start the LAMP stack."
        exit 1
    fi

    green_message "LAMP stack is running"
    
    # Show status
    print_line
    info_message "Services:"
    info_message "  • Web: http://localhost"
    if [[ "$APP_ENV" == "development" ]]; then
        info_message "  • phpMyAdmin: http://localhost:${HOST_MACHINE_PMA_PORT:-8080}"
        info_message "  • Mailpit: http://localhost:8025"
    fi
    info_message "  • Database: localhost:${HOST_MACHINE_MYSQL_PORT:-3306}"
    info_message "  • Redis: localhost:${HOST_MACHINE_REDIS_PORT:-6379}"
    info_message "  • Memcached: localhost:11211"
    print_line
}

lamp() {

    # go to lamp path
    cd "$lampPath"

    # Load environment variables from .env file
    if [[ -f .env ]]; then
        # Load all variables while excluding comments
        export $(grep -v '^#' .env | xargs)
    elif [[ $1 != "config" ]]; then
        info_message ".env file not found. running.'$ lamp config'"
        lamp_config
    fi

    # Determine webserver service name based on stack mode
    WEBSERVER_SERVICE="webserver-apache"
    if [[ "${STACK_MODE:-hybrid}" == "thunder" ]]; then
        WEBSERVER_SERVICE="webserver-fpm"
    fi

    # Check LAMP stack status
    if [[ $1 != "stop" && $1 != "config" && ! $(docker compose ps -q $WEBSERVER_SERVICE) ]]; then
        yellow_message "LAMP stack is not running. Starting LAMP stack..."
        lamp_start
    fi

    # Start the LAMP stack using Docker
    if [[ $1 == "start" ]]; then
        # Open the domain in the default web browser
        open_browser "http://localhost"

    # Stop the LAMP stack
    elif [[ $1 == "stop" ]]; then
        docker compose --profile "*" down
        green_message "LAMP stack is stopped"

    # Open a bash shell inside the webserver container
    elif [[ $1 == "cmd" ]]; then
        docker compose exec $WEBSERVER_SERVICE bash

    # Restart the LAMP stack
    elif [[ $1 == "restart" ]]; then
        PROFILES="--profile ${STACK_MODE:-hybrid}"
        if [[ "$APP_ENV" == "development" ]]; then
            PROFILES="$PROFILES --profile development"
        fi
        docker compose --profile "*" down && docker compose $PROFILES up -d
        green_message "LAMP stack restarted."

    # Rebuild & Start
    elif [[ $1 == "build" ]]; then
        PROFILES="--profile ${STACK_MODE:-hybrid}"
        if [[ "$APP_ENV" == "development" ]]; then
            PROFILES="$PROFILES --profile development"
        fi
        docker compose --profile "*" down
        # docker compose build
        docker compose $PROFILES up -d --build
        green_message "LAMP stack rebuilt and running."

    # Add a new application and create a corresponding virtual host
    elif [[ $1 == "addapp" ]]; then
        # Validate if the application name is provided
        if [[ -z $2 ]]; then
            error_message "Application name is required."
            return 1
        fi

        app_name=$2
        domain=$3

        # Set default domain to <app_name>.localhost if not provided
        if [[ -z $domain ]]; then
            domain="${app_name}.localhost"
        else
            # Check if the domain matches the allowed TLDs
            if [[ ! $domain =~ ^[a-zA-Z0-9.-]+($ALLOWED_TLDS)$ ]]; then
                error_message "Domain must end with a valid TLD."
                return 1
            fi
        fi

        # Validate domain format (allow alphanumeric and dots)
        if [[ ! $domain =~ ^[a-zA-Z0-9.-]+$ ]]; then
            error_message "Invalid domain format."
            return 1
        fi

        # Define vhost directory and file using .env variables
        vhost_file="${VHOSTS_DIR}/${domain}.conf"
        nginx_file="${NGINX_CONF_DIR}/${domain}.conf"

        # Create the vhost directory if it doesn't exist
        if [[ ! -d $VHOSTS_DIR ]]; then
            mkdir -p $VHOSTS_DIR
        fi

        if [[ ! -d $NGINX_CONF_DIR ]]; then
            mkdir -p $NGINX_CONF_DIR
        fi

        # Create the vhost configuration file
        yellow_message "Creating vhost configuration for $domain..."
        cat >$vhost_file <<EOL
<VirtualHost *:80>
    ServerName $domain
    ServerAlias www.$domain
    ServerAdmin webmaster@$domain

    DocumentRoot $APACHE_DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name

    <Directory $APACHE_DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:443>
    ServerName $domain
    ServerAlias www.$domain
    ServerAdmin webmaster@$domain

    DocumentRoot $APACHE_DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name

    <Directory $APACHE_DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile /etc/apache2/ssl/cert.pem
    SSLCertificateKeyFile /etc/apache2/ssl/cert-key.pem
</VirtualHost>
EOL

        if [[ "${STACK_MODE:-hybrid}" == "thunder" ]]; then
            # Thunder Mode (FPM)
            cat >$nginx_file <<EOL
# HTTP server configuration
server {
    listen 80;
    server_name $domain www.$domain;
    root $APACHE_DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass webserver:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }
}

# HTTPS server configuration
server {
    listen 443 ssl;
    server_name $domain www.$domain;
    root $APACHE_DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name;
    index index.php index.html index.htm;

    # SSL/TLS certificate configuration
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/cert-key.pem;

    # Enforce secure protocols and ciphers
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass webserver:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }
}
EOL
        else
            # Hybrid Mode (Apache)
            cat >$nginx_file <<EOL
# HTTP server configuration
server {
    listen 80;
    server_name $domain www.$domain;

    # Proxy all requests to the backend web server
    location / {
        proxy_pass http://webserver:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# HTTPS server configuration
server {
    listen 443 ssl;
    server_name $domain www.$domain;

    # SSL/TLS certificate configuration
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/cert-key.pem;

    # Enforce secure protocols and ciphers
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # Proxy all requests to the backend web server
    location / {
        proxy_pass http://webserver:80;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL
        fi

        green_message "Vhost configuration file created at: $vhost_file"

        # Check if mkcert is installed
        if ! generate_ssl_certificates $domain $vhost_file $nginx_file; then
            domainUrl="http://$domain"
        else
            domainUrl="https://$domain"
        fi

        # Create the application document root directory
        app_root="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name"
        if [[ ! -d $app_root ]]; then
            mkdir -p $app_root
            info_message "Created document root at $app_root"
        else
            yellow_message "Document root already exists at $app_root"
        fi

        # Create an index.php file in the app's document root
        index_file="${app_root}/index.php"
        indexHtml="$lampPath/data/pages/site-created.html"
        sed -e "s|example.com|$domain|g" \
            -e "s|index.html|index.php|g" \
            -e "s|/var/www/html|$app_root|g" \
            -e "s|lamp code|lamp code $app_name|g" \
            $indexHtml > $index_file
        info_message "index.php created at $index_file"

        # Enable the new virtual host and reload Apache
        yellow_message "Activating the virtual host..."
        if command -v docker >/dev/null; then
            if [[ "${STACK_MODE:-hybrid}" == "hybrid" ]]; then
                docker compose exec "$WEBSERVER_SERVICE" bash -c "service apache2 reload"
            fi
            docker compose exec reverse-proxy nginx -s reload

            green_message "Virtual host $domain activated and web servers reloaded."
        fi

        # Open the domain in the default web browser
        open_browser "$domainUrl"

        green_message "App setup complete: $app_name with domain $domain"

    # Remove an application
    elif [[ $1 == "removeapp" ]]; then
        if [[ -z $2 ]]; then
            error_message "Application name is required."
            return 1
        fi

        app_name=$2
        
        # Try to find the domain from the vhost file or assume default
        # This is tricky because we don't store the mapping. 
        # We can search for the app_name in the vhosts directory.
        
        # Simple approach: Ask for domain or assume default
        domain=$3
        if [[ -z $domain ]]; then
             # Try to find a vhost file containing the app path
             found_vhost=$(grep -l "$APPLICATIONS_DIR_NAME/$app_name" "$VHOSTS_DIR"/*.conf 2>/dev/null | head -n 1)
             if [[ -n "$found_vhost" ]]; then
                 domain=$(basename "$found_vhost" .conf)
                 info_message "Found domain $domain for app $app_name"
             else
                 domain="${app_name}.localhost"
                 yellow_message "Domain not provided and not found. Assuming $domain"
             fi
        fi

        vhost_file="${VHOSTS_DIR}/${domain}.conf"
        nginx_file="${NGINX_CONF_DIR}/${domain}.conf"
        app_root="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name"

        if [[ ! -f $vhost_file && ! -d $app_root ]]; then
            error_message "Application $app_name not found."
            return 1
        fi

        if yes_no_prompt "Are you sure you want to remove app '$app_name' and domain '$domain'? This will delete configuration files."; then
            # Remove config files
            if [[ -f $vhost_file ]]; then
                rm "$vhost_file"
                green_message "Removed $vhost_file"
            fi
            if [[ -f $nginx_file ]]; then
                rm "$nginx_file"
                green_message "Removed $nginx_file"
            fi
            
            # Remove SSL certs if they exist
            if [[ -f "$lampPath/config/ssl/$domain-key.pem" ]]; then
                rm "$lampPath/config/ssl/$domain-key.pem"
                rm "$lampPath/config/ssl/$domain-cert.pem"
                green_message "Removed SSL certificates for $domain"
            fi

            # Remove app directory
            if [[ -d $app_root ]]; then
                if yes_no_prompt "Do you also want to delete the application files at $app_root?"; then
                    rm -rf "$app_root"
                    green_message "Removed application files."
                else
                    info_message "Application files kept at $app_root"
                fi
            fi

            # Reload servers
            yellow_message "Reloading web servers..."
            if command -v docker >/dev/null; then
                if [[ "${STACK_MODE:-hybrid}" == "hybrid" ]]; then
                    docker compose exec "$WEBSERVER_SERVICE" bash -c "service apache2 reload"
                fi
                docker compose exec reverse-proxy nginx -s reload
                green_message "Web servers reloaded."
            fi
        else
            info_message "Operation cancelled."
        fi

    # Show logs
    elif [[ $1 == "logs" ]]; then
        service=$2
        if [[ -z $service ]]; then
            docker compose logs -f
        else
            docker compose logs -f "$service"
        fi

    # Show status
    elif [[ $1 == "status" ]]; then
        docker compose ps

    # Handle 'code' command to open application directories
    elif [[ $1 == "code" ]]; then
        if [[ $2 == "lamp" ]]; then
            code "$lampPath"
        else
            # If no argument is provided, list application directories and prompt for selection
            apps_dir="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME"
            if [[ -z $2 ]]; then
                if [[ -d $apps_dir ]]; then
                    echo "Available applications:"
                    app_list=($(ls "$apps_dir" | grep -v '^lamp$')) # Exclude 'lamp' from listing
                    if [[ ${#app_list[@]} -eq 0 ]]; then
                        error_message "No applications found."
                        return
                    fi
                    for i in "${!app_list[@]}"; do
                        blue_message "$((i + 1)). ${app_list[$i]}"
                    done
                    read -p "Choose an application number: " app_num
                    if [[ "$app_num" -gt 0 && "$app_num" -le "${#app_list[@]}" ]]; then
                        selected_app="${app_list[$((app_num - 1))]}"
                        app_dir="$apps_dir/$selected_app"
                        code "$app_dir"
                    else
                        error_message "Invalid selection."
                    fi
                else
                    error_message "Applications directory not found: $apps_dir"
                fi
            else
                app_dir="$apps_dir/$2"
                if [[ -d $app_dir ]]; then
                    code "$app_dir"
                else
                    error_message "Application directory does not exist: $app_dir"
                fi
            fi
        fi
    elif [[ $1 == "config" ]]; then

        lamp_config

    # Backup the LAMP stack
    elif [[ $1 == "backup" ]]; then
        backup_dir="$lampPath/data/backup"
        mkdir -p "$backup_dir"
        timestamp=$(date +"%Y%m%d%H%M%S")
        backup_file="$backup_dir/lamp_backup_$timestamp.tgz"

        info_message "Backing up LAMP stack to $backup_file..."
        databases=$(docker compose exec "$WEBSERVER_SERVICE" bash -c "exec mysql -uroot -p\"$MYSQL_ROOT_PASSWORD\" -h database -e 'SHOW DATABASES;'" | grep -Ev "(Database|information_schema|performance_schema|mysql|phpmyadmin|sys)")

        # Create temporary directories for SQL and app data
        temp_sql_dir="$backup_dir/sql"
        temp_app_dir="$backup_dir/app"
        mkdir -p "$temp_sql_dir" "$temp_app_dir"

        for db in $databases; do
            backup_sql_file="$temp_sql_dir/db_backup_$db.sql"
            docker compose exec "$WEBSERVER_SERVICE" bash -c "exec mysqldump -uroot -p\"$MYSQL_ROOT_PASSWORD\" -h database --databases $db" >"$backup_sql_file"
        done

        # Copy application data to the temporary app directory
        cp -r "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/." "$temp_app_dir/"

        # Create the compressed backup file containing both SQL and app data
        tar -czf "$backup_file" -C "$backup_dir" sql app

        # Clean up temporary directories
        rm -rf "$temp_sql_dir" "$temp_app_dir"

        green_message "Backup completed: ${backup_file}"

    # Restore the LAMP stack
    elif [[ $1 == "restore" ]]; then
        backup_dir="$lampPath/data/backup"
        if [[ ! -d $backup_dir ]]; then
            error_message "Backup directory not found: $backup_dir"
            return 1
        fi

        backup_files=($(ls -t "$backup_dir"/*.tgz))
        if [[ ${#backup_files[@]} -eq 0 ]]; then
            error_message "No backup files found in $backup_dir"
            return 1
        fi

        echo "Available backups:"
        for i in "${!backup_files[@]}"; do
            backup_file="${backup_files[$i]}"
            backup_time=$(date -r "$backup_file" +"%Y-%m-%d %H:%M:%S")
            echo "$((i + 1)). $(basename "$backup_file") (created on $backup_time)"
        done

        read -p "Choose a backup number to restore: " backup_num
        if [[ "$backup_num" -gt 0 && "$backup_num" -le "${#backup_files[@]}" ]]; then
            selected_backup="${backup_files[$((backup_num - 1))]}"
        else
            error_message "Invalid selection."
            return 1
        fi

        info_message "Restoring LAMP stack from $selected_backup..."
        
        # Create temp directory for extraction
        temp_restore_dir="$backup_dir/restore_temp"
        mkdir -p "$temp_restore_dir"
        
        # Extract backup
        tar -xzf "$selected_backup" -C "$temp_restore_dir"
        
        # Restore Databases
        if [[ -d "$temp_restore_dir/sql" ]]; then
            info_message "Restoring databases..."
            for sql_file in "$temp_restore_dir/sql"/*.sql; do
                if [[ -f "$sql_file" ]]; then
                    db_name=$(basename "$sql_file" | sed 's/db_backup_//;s/\.sql//')
                    info_message "Restoring database: $db_name"
                    # Create DB if not exists (optional, mysqldump usually includes it if --databases used)
                    # But here we pipe content, so we rely on dump content.
                    # The backup command used: mysqldump ... --databases $db
                    # So it should contain CREATE DATABASE statement.
                    
                    # Copy sql file to container to avoid pipe issues with large files or special chars
                    docker compose cp "$sql_file" "$WEBSERVER_SERVICE:/tmp/restore.sql"
                    docker compose exec "$WEBSERVER_SERVICE" bash -c "exec mysql -uroot -p\"$MYSQL_ROOT_PASSWORD\" -h database < /tmp/restore.sql"
                    docker compose exec "$WEBSERVER_SERVICE" bash -c "rm /tmp/restore.sql"
                fi
            done
        fi
        
        # Restore Applications
        if [[ -d "$temp_restore_dir/app" ]]; then
            info_message "Restoring applications..."
            # We need to be careful not to overwrite existing files blindly, or maybe we should?
            # Usually restore implies overwriting.
            cp -R "$temp_restore_dir/app/." "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/"
        fi
        
        # Clean up
        rm -rf "$temp_restore_dir"
        
        green_message "Restore completed from $selected_backup"

    # Generate SSL certificates for a domain
    elif [[ $1 == "ssl" ]]; then
        domain=$2
        if [[ -z $domain ]]; then
            error_message "Domain name is required."
            return 1
        fi

        vhost_file="${VHOSTS_DIR}/${domain}.conf"
        nginx_file="${NGINX_CONF_DIR}/${domain}.conf"

        if [[ ! -f $vhost_file ]]; then
            error_message "Domain name invalid. Vhost configuration file not found for $domain."
            return 1
        fi

        generate_ssl_certificates $domain $vhost_file $nginx_file

    # Open Mailpit
    elif [[ $1 == "mail" ]]; then
        open_browser "http://localhost:8025"

    # Open phpMyAdmin
    elif [[ $1 == "pma" ]]; then
        open_browser "http://localhost:${HOST_MACHINE_PMA_PORT}"

    # Open Redis CLI
    elif [[ $1 == "redis-cli" ]]; then
        docker compose exec redis redis-cli

    else
        echo "Usage: lamp [command] [args]"
        echo ""
        echo "Commands:"
        echo "  start       Start the LAMP stack"
        echo "  stop        Stop the LAMP stack"
        echo "  restart     Restart the LAMP stack"
        echo "  build       Rebuild and start the LAMP stack"
        echo "  cmd         Open a bash shell in the webserver container"
        echo "  addapp      Add a new application (usage: lamp addapp <name> [domain])"
        echo "  removeapp   Remove an application (usage: lamp removeapp <name> [domain])"
        echo "  code        Open VS Code for an app (usage: lamp code [name])"
        echo "  config      Configure the environment"
        echo "  backup      Backup databases and applications"
        echo "  restore     Restore from a backup"
        echo "  ssl         Generate SSL certificates (usage: lamp ssl <domain>)"
        echo "  logs        Show logs (usage: lamp logs [service])"
        echo "  status      Show stack status"
        echo "  mail        Open Mailpit"
        echo "  pma         Open phpMyAdmin"
        echo "  redis-cli   Open Redis CLI"
        echo ""
    fi
}

# Check if required commands are available
required_commands=("docker" "sed" "curl")
for cmd in "${required_commands[@]}"; do
    if ! command_exists "$cmd"; then
        error_message "Required command '$cmd' is not installed."
        exit 1
    fi
done

# Ensure Docker Compose v2 plugin is available
if ! docker compose version >/dev/null 2>&1; then
    error_message "Docker Compose plugin is missing. Please install Docker Desktop or the compose plugin."
    exit 1
fi

# Add lamp function to shell config (zsh/bash)
add_lamp_to_shell() {
    local shell_rc=""
    if [ -f "$HOME/.zshrc" ]; then
        shell_rc="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        shell_rc="$HOME/.bashrc"
    fi
    
    if [ -n "$shell_rc" ] && ! grep -q "lamp()" "$shell_rc"; then
        cat >> "$shell_rc" << EOF

# LAMP Docker helper function
lamp() {
    bash "$lampFile" "\$@"
}
EOF
        info_message "Function 'lamp' added to $(basename $shell_rc)"
    fi
}

add_lamp_to_shell

# Run lamp with all arguments
lamp "$@"
