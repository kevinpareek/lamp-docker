#!/bin/bash

# Get tbs script directory
# Cross-platform readlink -f implementation
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [ -h "$source" ]; do # resolve $source until the file is no longer a symlink
        local dir="$( cd -P "$( dirname "$source" )" >/dev/null 2>&1 && pwd )"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source" # if $source was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    done
    echo "$( cd -P "$( dirname "$source" )" >/dev/null 2>&1 && pwd )"
}

tbsPath=$(get_script_dir)
tbsFile="$tbsPath/$(basename "${BASH_SOURCE[0]}")"
# echo $tbsPath;

# Allowed TLDs for application domains
ALLOWED_TLDS="\.localhost|\.com|\.org|\.net|\.info|\.biz|\.name|\.pro|\.aero|\.coop|\.museum|\.jobs|\.mobi|\.travel|\.asia|\.cat|\.tel|\.app|\.blog|\.shop|\.xyz|\.tech|\.online|\.site|\.web|\.store|\.club|\.media|\.news|\.agency|\.guru|\.in|\.co.in|\.ai.in|\.net.in|\.org.in|\.firm.in|\.gen.in|\.ind.in|\.com.au|\.co.uk|\.co.nz|\.co.za|\.com.br|\.co.jp|\.ca|\.de|\.fr|\.cn|\.ru|\.us"

# Colors and Styles
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BOLD}${CYAN}   🚀  TURBO STACK MANAGER  ${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""
}

red_message() {
    echo -e "${RED}$1${NC}"
}

error_message() {
    echo -e "  ${RED}Error: $1${NC}"
}

value_message() {
    echo -e "${BLUE}${1}${NC} ${GREEN}${2}${NC}"
}

blue_message() {
    echo -e "${BLUE}$1${NC}"
}

green_message() {
    echo -e "${GREEN}$1${NC}"
}

info_message() {
    echo -e "  ${CYAN}$1${NC}"
}

yellow_message() {
    echo -e "  ${YELLOW}$1${NC}"
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
    echo -e "${BLUE}$(printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' -)${NC}"
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

generate_default_ssl() {
    info_message "Generating default SSL certificates for localhost..."
    
    # Check mkcert
    if ! command -v mkcert &>/dev/null; then
         if yes_no_prompt "mkcert is not installed. Install now?"; then
             if ! install_mkcert; then
                 return 1
             fi
         else
             return 1
         fi
    fi

    local ssl_config_dir="$tbsPath/config/ssl"
    mkdir -p "$ssl_config_dir"

    if mkcert -key-file "$ssl_config_dir/cert-key.pem" -cert-file "$ssl_config_dir/cert.pem" "localhost" "www.localhost" "127.0.0.1" "::1"; then
        green_message "Default SSL certificates (localhost) generated in config/ssl/"
        
        # Reload if running
        if command -v docker >/dev/null && docker compose ps -q "$WEBSERVER_SERVICE" >/dev/null 2>&1; then
             yellow_message "Reloading web servers to apply new default certs..."
             if [[ "${STACK_MODE:-hybrid}" == "hybrid" ]]; then
                docker compose exec "$WEBSERVER_SERVICE" bash -c "service apache2 reload"
             fi
             docker compose exec reverse-proxy nginx -s reload
             green_message "Web servers reloaded."
        fi
    else
        error_message "Failed to generate default SSL certificates."
    fi
}

generate_ssl_certificates() {
    domain=$1
    vhost_file=$2
    nginx_file=$3

    local use_mkcert=false

    # Determine SSL method based on INSTALLATION_TYPE
    if [[ "${INSTALLATION_TYPE:-local}" == "local" ]]; then
        # Local Mode: Always use mkcert
        use_mkcert=true
        info_message "Local Environment detected. Using mkcert for $domain..."
    else
        # Live Mode: Always use Let's Encrypt (unless it's a .localhost domain)
        if [[ "$domain" == "localhost" || "$domain" == *".localhost" ]]; then
             yellow_message "Warning: Local domain '$domain' detected in LIVE mode. SSL generation skipped."
             return 1
        fi
        use_mkcert=false
        info_message "Live Environment detected. Using Let's Encrypt for $domain..."
    fi

    if [[ "$use_mkcert" == "false" ]]; then
        
        # Ensure certbot service is running or run it as a one-off command
        # We use webroot mode because nginx is already running and serving /.well-known/acme-challenge/
        # We override the entrypoint because the default entrypoint in docker-compose.yml is a renewal loop that ignores arguments
        
        if docker compose run --rm --entrypoint certbot certbot certonly --webroot --webroot-path=/var/www/html -d "$domain" -d "www.$domain" --email "admin@$domain" --agree-tos --no-eff-email; then
            
            # Certbot saves certs in /etc/letsencrypt/live/$domain/
            # We need to copy them to our sites/ssl directory so Nginx can see them as expected
            # Note: In docker-compose, we mapped ./data/certbot/conf to /etc/letsencrypt
            
            # The path inside the host machine (relative to tbs.sh)
            cert_path="./data/certbot/conf/live/$domain"
            
            if [[ -f "$cert_path/fullchain.pem" ]]; then
                cp "$cert_path/fullchain.pem" "${SSL_DIR}/$domain-cert.pem"
                cp "$cert_path/privkey.pem" "${SSL_DIR}/$domain-key.pem"
                
                green_message "Let's Encrypt certificates generated successfully."
                
                # Set flag for successful generation
                ssl_generated=true
            else
                error_message "Certificates were generated but could not be found at $cert_path"
                return 1
            fi
        else
            error_message "Failed to generate Let's Encrypt certificates."
            return 1
        fi

    else
        # Local Domain (mkcert)

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
        mkdir -p "${SSL_DIR}"
        if mkcert -key-file "${SSL_DIR}/$domain-key.pem" -cert-file "${SSL_DIR}/$domain-cert.pem" $domain "www.$domain"; then
            green_message "mkcert certificates generated successfully."
            ssl_generated=true
        else
            error_message "Failed to generate mkcert certificates."
            return 1
        fi
    fi

    # Common configuration update logic
    if [[ "$ssl_generated" == "true" ]]; then
        # Update the vhost configuration file with the correct SSL certificate paths
        sed_i "s|SSLCertificateFile /etc/apache2/ssl-default/cert.pem|SSLCertificateFile /etc/apache2/ssl-sites/$domain-cert.pem|" $vhost_file
        sed_i "s|SSLCertificateKeyFile /etc/apache2/ssl-default/cert-key.pem|SSLCertificateKeyFile /etc/apache2/ssl-sites/$domain-key.pem|" $vhost_file

        sed_i "s|ssl_certificate /etc/nginx/ssl-default/cert.pem|ssl_certificate /etc/nginx/ssl-sites/$domain-cert.pem|" $nginx_file
        sed_i "s|ssl_certificate_key /etc/nginx/ssl-default/cert-key.pem|ssl_certificate_key /etc/nginx/ssl-sites/$domain-key.pem|" $nginx_file

        info_message "SSL certificates configured for https://$domain"
        return 0
    fi
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

tbs_config() {
    print_header
    # Set required configuration keys
    reqConfig=("INSTALLATION_TYPE" "APP_ENV" "STACK_MODE" "PHPVERSION" "DATABASE")

    # Detect if Apple Silicon
    isAppleSilicon=false
    if [[ $(uname -m) == 'arm64' ]]; then
        isAppleSilicon=true
    fi

    # Function to dynamically fetch PHP versions and databases from ./bin
    fetch_dynamic_versions() {
        local bin_dir="$tbsPath/bin"
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

        # Sort arrays using version sort
        IFS=$'\n' phpVersions=($(sort -V <<<"${phpVersions[*]}"))
        IFS=$'\n' mysqlOptions=($(sort -V <<<"${mysqlOptions[*]}"))
        IFS=$'\n' mariadbOptions=($(sort -V <<<"${mariadbOptions[*]}"))
        unset IFS
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

    # Function to prompt user to input a valid installation type
    choose_installation_type() {
        local valid_options=("local" "live")
        blue_message "Installation Type:"
        info_message "   1. local (Select for Local PC/System)"
        info_message "      • Best for local development. Enables .localhost domains with trusted SSL (mkcert)."
        
        info_message "   2. live  (Select for Live/Production Server)"
        info_message "      • Best for public servers. Uses Let's Encrypt for valid SSL on custom domains."
        yellow_message "      • NOTE: For custom domains, you MUST point the domain's DNS to this server's IP first."

        # Auto-detect default
        local default_index=1
        if [[ "$(uname -s)" != "Darwin" && "$(uname -s)" != *"MINGW"* && "$(uname -s)" != *"CYGWIN"* ]]; then
             # Likely Linux, could be live
             # But let's check if INSTALLATION_TYPE is already set
             if [[ "$INSTALLATION_TYPE" == "live" ]]; then
                 default_index=2
             fi
        else
             # Mac/Windows -> Local
             if [[ "$INSTALLATION_TYPE" == "live" ]]; then
                 default_index=2
             fi
        fi

        while true; do
            echo -ne "Select Installation Type [1-2] (${YELLOW}Default: $default_index${NC}): "
            read type_index
            type_index=${type_index:-$default_index}

            if [[ "$type_index" -ge 1 && "$type_index" -le 2 ]]; then
                INSTALLATION_TYPE="${valid_options[$((type_index-1))]}"
                break
            else
                error_message "Invalid selection. Please enter 1 or 2."
            fi
        done
    }

    # Function to prompt user to input a valid stack mode
    choose_stack_mode() {
        local valid_options=("hybrid" "thunder")
        blue_message "Available Stack Modes:"
        for i in "${!valid_options[@]}"; do
            echo "   $((i+1)). ${valid_options[$i]}"
        done

        # Find current index for default
        local default_index=1
        for i in "${!valid_options[@]}"; do
            if [[ "${valid_options[$i]}" == "$STACK_MODE" ]]; then
                default_index=$((i+1))
                break
            fi
        done

        while true; do
            echo -ne "Select Stack Mode [1-${#valid_options[@]}] (${YELLOW}Default: $default_index${NC}): "
            read mode_index
            mode_index=${mode_index:-$default_index}

            if [[ "$mode_index" -ge 1 && "$mode_index" -le "${#valid_options[@]}" ]]; then
                STACK_MODE="${valid_options[$((mode_index-1))]}"
                break
            else
                error_message "Invalid selection. Please enter a number between 1 and ${#valid_options[@]}."
            fi
        done
    }

    # Function to prompt user to input a valid PHP version
    choose_php_version() {
        blue_message "Available PHP versions:" 
        green_message "➤  ${phpVersions[*]}"

        while true; do
            echo -ne "Enter PHP version (${YELLOW}Default: $PHPVERSION${NC}): "
            read php_choice
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
            blue_message "Available Databases versions:"
            yellow_message "Apple Silicon detected. Using MariaDB images for best compatibility."
            databaseOptions=("${mariadbOptions[@]}")
        else
            if $legacy_php; then
                blue_message "Available Databases versions (MySQL 8+ excluded for PHP <= 7.4):"
                databaseOptions=()
                for db in "${mysqlOptions[@]}"; do
                    if [[ "$db" == "mysql5.7" ]]; then
                        databaseOptions+=("$db")
                    fi
                done
                databaseOptions+=("${mariadbOptions[@]}")
            else
                blue_message "Available Databases versions:"
                databaseOptions=("${mysqlOptions[@]}" "${mariadbOptions[@]}")
            fi
        fi

        if [[ ${#databaseOptions[@]} -eq 0 ]]; then
            error_message "No database options found in ./bin. Please add mysql*/mariadb* folders."
            exit 1
        fi

        green_message "➤  ${databaseOptions[*]}"

        while true; do
            echo -ne "Enter Database (${YELLOW}Default: $DATABASE${NC}): "
            read db_choice
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
        blue_message "Available Environments:"
        for i in "${!valid_options[@]}"; do
            echo "   $((i+1)). ${valid_options[$i]}"
        done

        # Find current index for default
        local default_index=1
        for i in "${!valid_options[@]}"; do
            if [[ "${valid_options[$i]}" == "$APP_ENV" ]]; then
                default_index=$((i+1))
                break
            fi
        done

        while true; do
            echo -ne "Select Environment [1-${#valid_options[@]}] (${YELLOW}Default: $default_index${NC}): "
            read env_index
            env_index=${env_index:-$default_index}

            if [[ "$env_index" -ge 1 && "$env_index" -le "${#valid_options[@]}" ]]; then
                export APP_ENV="${valid_options[$((env_index-1))]}"
                
                # Auto-configure based on environment
                if [[ "$APP_ENV" == "development" ]]; then
                    export INSTALL_XDEBUG="true"
                    export APP_DEBUG="true"
                else
                    export INSTALL_XDEBUG="false"
                    export APP_DEBUG="false"
                fi
                
                # Update these in .env file
                if grep -q "^INSTALL_XDEBUG=" .env; then
                    sed_i "s|^INSTALL_XDEBUG=.*|INSTALL_XDEBUG=${INSTALL_XDEBUG}|" .env
                else
                    echo "INSTALL_XDEBUG=${INSTALL_XDEBUG}" >> .env
                fi

                if grep -q "^APP_DEBUG=" .env; then
                    sed_i "s|^APP_DEBUG=.*|APP_DEBUG=${APP_DEBUG}|" .env
                else
                    echo "APP_DEBUG=${APP_DEBUG}" >> .env
                fi
                
                break
            else
                error_message "Invalid selection. Please enter a number between 1 and ${#valid_options[@]}."
            fi
        done
    }

    # Function to update or create the .env file
    update_env_file() {
        info_message "Updating the .env file..."

        for key in "${reqConfig[@]}"; do
            default_value=$(eval echo \$$key)

            echo -e ""

            # Handle PHPVERSION and DATABASE separately for prompts
            if [[ "$key" == "PHPVERSION" ]]; then
                choose_php_version
            elif [[ "$key" == "DATABASE" ]]; then
                choose_database
            elif [[ "$key" == "APP_ENV" ]]; then
                set_app_env
            elif [[ "$key" == "STACK_MODE" ]]; then
                choose_stack_mode
            elif [[ "$key" == "INSTALLATION_TYPE" ]]; then
                choose_installation_type
            else
                echo -ne "$key (${YELLOW}Default: $default_value${NC}): "
                read new_value
                if [[ ! -z $new_value ]]; then
                    eval "$key=$new_value"
                fi
            fi

            # Update the .env file
            if grep -q "^$key=" .env; then
                sed_i "s|^$key=.*|$key=${!key}|" .env
            else
                echo "$key=${!key}" >> .env
            fi
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
        local indexFilePath="$tbsPath/$DOCUMENT_ROOT/config.php"
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

tbs_start() {
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
    info_message "Starting Turbo Stack (${APP_ENV} mode, ${STACK_MODE:-hybrid} stack)..."
    
    PROFILES="--profile ${STACK_MODE:-hybrid}"
    if [[ "$APP_ENV" == "development" ]]; then
        PROFILES="$PROFILES --profile development"
    fi

    if ! docker compose $PROFILES up -d --build; then
        error_message "Failed to start the Turbo Stack."
        exit 1
    fi

    green_message "Turbo Stack is running"
    
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

interactive_menu() {
    while true; do
        clear
        print_header
        echo -e "${BOLD}Select an action:${NC}"
        
        echo -e "\n${BLUE}🚀 Stack Control${NC}"
        echo "   1) Start Stack"
        echo "   2) Stop Stack"
        echo "   3) Restart Stack"
        echo "   4) Rebuild Stack"
        echo "   5) View Status"
        echo "   6) View Logs"

        echo -e "\n${BLUE}📦 Application${NC}"
        echo "   7) Add New App"
        echo "   8) Remove App"
        echo "   9) Open App Code"

        echo -e "\n${BLUE}⚙️ Configuration & Tools${NC}"
        echo "   10) Configure Environment"
        echo "   11) Backup Data"
        echo "   12) Restore Data"
        echo "   13) SSL Certificates"
        echo "   14) Open Mailpit"
        echo "   15) Open phpMyAdmin"
        echo "   16) Redis CLI"
        echo "   17) Shell Access (Bash)"

        echo -e "\n   ${RED}0) Exit${NC}"
        
        echo ""
        read -p "Enter your choice [0-17]: " choice

        local wait_needed=true
        case $choice in
            1) tbs start ;;
            2) tbs stop ;;
            3) tbs restart ;;
            4) tbs build ;;
            5) tbs status ;;
            6) tbs logs ;;
            7) 
                echo ""
                read -p "Enter application name: " app_name
                read -p "Enter domain name (Default: ${app_name}.localhost): " domain
                domain=${domain:-"${app_name}.localhost"}
                tbs addapp "$app_name" "$domain"
                ;;
            8) 
                echo ""
                read -p "Enter application name: " app_name
                tbs removeapp "$app_name"
                ;;
            9) 
                echo ""
                read -p "Enter application name (optional): " app_name
                tbs code "$app_name"
                ;;
            10) tbs config ;;
            11) tbs backup ;;
            12) tbs restore ;;
            13) 
                echo ""
                read -p "Enter domain name: " domain
                tbs ssl "$domain"
                ;;
            14) tbs mail ;;
            15) tbs pma ;;
            16) tbs redis-cli ;;
            17) tbs cmd ;;
            0) echo "Bye!"; exit 0 ;;
            *) red_message "Invalid choice. Please try again."; sleep 1; wait_needed=false ;;
        esac

        if $wait_needed; then
            echo ""
            read -p "Press Enter to return to menu..."
        fi
    done
}

tbs() {

    # go to tbs path
    cd "$tbsPath"

    # Load environment variables from .env file
    if [[ -f .env ]]; then
        # Load all variables while excluding comments
        export $(grep -v '^#' .env | xargs)
    elif [[ $1 != "config" ]]; then
        info_message ".env file not found. running.'$ tbs config'"
        tbs_config
    fi

    # Determine webserver service name based on stack mode
    WEBSERVER_SERVICE="webserver-apache"
    if [[ "${STACK_MODE:-hybrid}" == "thunder" ]]; then
        WEBSERVER_SERVICE="webserver-fpm"
    fi

    # Check Turbo Stack status
    if [[ "$1" =~ ^(start|addapp|removeapp|cmd|backup|restore|ssl|mail|pma|redis-cli)$ && ! $(docker compose ps -q $WEBSERVER_SERVICE) ]]; then
        yellow_message "Turbo Stack is not running. Starting Turbo Stack..."
        tbs_start
    fi

    # Start the Turbo Stack using Docker
    if [[ $1 == "start" ]]; then
        # Open the domain in the default web browser
        open_browser "http://localhost"

    # Stop the Turbo Stack
    elif [[ $1 == "stop" ]]; then
        docker compose --profile "*" down
        green_message "Turbo Stack is stopped"

    # Open a bash shell inside the webserver container
    elif [[ $1 == "cmd" ]]; then
        docker compose exec $WEBSERVER_SERVICE bash

    # Restart the Turbo Stack
    elif [[ $1 == "restart" ]]; then
        PROFILES="--profile ${STACK_MODE:-hybrid}"
        if [[ "$APP_ENV" == "development" ]]; then
            PROFILES="$PROFILES --profile development"
        fi
        docker compose --profile "*" down && docker compose $PROFILES up -d
        green_message "Turbo Stack restarted."

    # Rebuild & Start
    elif [[ $1 == "build" ]]; then
        PROFILES="--profile ${STACK_MODE:-hybrid}"
        if [[ "$APP_ENV" == "development" ]]; then
            PROFILES="$PROFILES --profile development"
        fi
        docker compose --profile "*" down
        # docker compose build
        docker compose $PROFILES up -d --build
        green_message "Turbo Stack rebuilt and running."

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

    Define APP_NAME $app_name
    Include /etc/apache2/sites-enabled/partials/app-common.inc
</VirtualHost>

<VirtualHost *:443>
    ServerName $domain
    ServerAlias www.$domain
    ServerAdmin webmaster@$domain

    DocumentRoot $APACHE_DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name

    Define APP_NAME $app_name
    Include /etc/apache2/sites-enabled/partials/app-common.inc

    SSLEngine on
    SSLCertificateFile /etc/apache2/ssl-default/cert.pem
    SSLCertificateKeyFile /etc/apache2/ssl-default/cert-key.pem
</VirtualHost>
EOL

        if [[ "${STACK_MODE:-hybrid}" == "thunder" ]]; then
            # Thunder Mode (FPM)
            cat >$nginx_file <<EOL
# HTTP server configuration (Frontend -> Varnish)
server {
    listen 80;
    server_name $domain www.$domain;

    include /etc/nginx/includes/common.conf;
    include /etc/nginx/partials/varnish-proxy.conf;
}

# HTTPS server configuration (Frontend -> Varnish)
server {
    listen 443 ssl;
    server_name $domain www.$domain;

    # SSL/TLS certificate configuration
    ssl_certificate /etc/nginx/ssl-default/cert.pem;
    ssl_certificate_key /etc/nginx/ssl-default/cert-key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    include /etc/nginx/includes/common.conf;
    include /etc/nginx/partials/varnish-proxy.conf;
}

# Internal Backend for Varnish (Port 8080)
server {
    listen 8080;
    server_name $domain www.$domain;
    root $APACHE_DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name;
    index index.php index.html index.htm;

    include /etc/nginx/partials/php-fpm.conf;
}
EOL
        else
            # Hybrid Mode (Apache)
            cat >$nginx_file <<EOL
# HTTP server configuration (Frontend -> Varnish)
server {
    listen 80;
    server_name $domain www.$domain;

    include /etc/nginx/includes/common.conf;
    include /etc/nginx/partials/varnish-proxy.conf;
}

# HTTPS server configuration (Frontend -> Varnish)
server {
    listen 443 ssl;
    server_name $domain www.$domain;

    # SSL/TLS certificate configuration
    ssl_certificate /etc/nginx/ssl-default/cert.pem;
    ssl_certificate_key /etc/nginx/ssl-default/cert-key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    include /etc/nginx/includes/common.conf;
    include /etc/nginx/partials/varnish-proxy.conf;
}
EOL
        fi

        green_message "Vhost configuration file created at: $vhost_file"

        # Reload Nginx to ensure it serves the new domain (required for Let's Encrypt validation)
        if command -v docker >/dev/null && docker compose ps -q reverse-proxy >/dev/null 2>&1; then
             info_message "Reloading Nginx to apply new configuration..."
             docker compose exec reverse-proxy nginx -s reload
        fi

        # Check if SSL generation is needed
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
        indexHtml="$tbsPath/data/pages/site-created.html"
        sed -e "s|example.com|$domain|g" \
            -e "s|index.html|index.php|g" \
            -e "s|/var/www/html|$app_root|g" \
            -e "s|tbs code|tbs code $app_name|g" \
            $indexHtml > $index_file
        info_message "index.php created at $index_file"

        # Enable the new virtual host and reload Apache
        yellow_message "Activating the virtual host..."
        if command -v docker >/dev/null; then
            if [[ "${STACK_MODE:-hybrid}" == "hybrid" ]]; then
                docker compose exec "$WEBSERVER_SERVICE" bash -c "service apache2 reload"
            fi
            # Nginx was already reloaded by generate_ssl_certificates if successful, 
            # but we reload again here to be sure if SSL generation was skipped or failed but we still want HTTP.
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
            if [[ -f "${SSL_DIR}/$domain-key.pem" ]]; then
                rm "${SSL_DIR}/$domain-key.pem"
                rm "${SSL_DIR}/$domain-cert.pem"
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
        if [[ $2 == "root" || $2 == "tbs" ]]; then
            code "$tbsPath"
        else
            # If no argument is provided, list application directories and prompt for selection
            apps_dir="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME"
            if [[ -z $2 ]]; then
                if [[ -d $apps_dir ]]; then
                    echo "Available applications:"
                    app_list=($(ls "$apps_dir" | grep -v '^tbs$')) # Exclude 'tbs' from listing
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

        tbs_config

    # Backup the Turbo Stack
    elif [[ $1 == "backup" ]]; then
        backup_dir="$tbsPath/data/backup"
        mkdir -p "$backup_dir"
        timestamp=$(date +"%Y%m%d%H%M%S")
        backup_file="$backup_dir/tbs_backup_$timestamp.tgz"

        info_message "Backing up Turbo Stack to $backup_file..."
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

    # Restore the Turbo Stack
    elif [[ $1 == "restore" ]]; then
        backup_dir="$tbsPath/data/backup"
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

        info_message "Restoring Turbo Stack from $selected_backup..."
        
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
                    
                    # Pipe content directly to mysql client
                    # We use -T to disable pseudo-tty allocation which allows piping
                    cat "$sql_file" | docker compose exec -T "$WEBSERVER_SERVICE" bash -c "exec mysql -uroot -p\"$MYSQL_ROOT_PASSWORD\" -h database"
                    
                    # Old method (copying file) - kept for reference but commented out
                    # docker compose cp "$sql_file" "$WEBSERVER_SERVICE:/tmp/restore.sql"
                    # docker compose exec "$WEBSERVER_SERVICE" bash -c "exec mysql -uroot -p\"$MYSQL_ROOT_PASSWORD\" -h database < /tmp/restore.sql"
                    # docker compose exec "$WEBSERVER_SERVICE" bash -c "rm /tmp/restore.sql"
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

        if generate_ssl_certificates $domain $vhost_file $nginx_file; then
            # Reload web servers to apply changes
            if command -v docker >/dev/null; then
                yellow_message "Reloading web servers..."
                if [[ "${STACK_MODE:-hybrid}" == "hybrid" ]]; then
                    docker compose exec "$WEBSERVER_SERVICE" bash -c "service apache2 reload"
                fi
                docker compose exec reverse-proxy nginx -s reload
                green_message "Web servers reloaded."
            fi
        fi

    # Generate Default SSL (localhost)
    elif [[ $1 == "ssl-default" ]]; then
        generate_default_ssl

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
        if [[ -z "$1" ]]; then
            interactive_menu
        elif [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" ]]; then
            print_header
            echo "Usage: tbs [command] [args]"
            echo ""
            echo "Commands:"
            echo "  start       Start the Turbo Stack"
            echo "  stop        Stop the Turbo Stack"
            echo "  restart     Restart the Turbo Stack"
            echo "  build       Rebuild and start the Turbo Stack"
            echo "  cmd         Open a bash shell in the webserver container"
            echo "  addapp      Add a new application (usage: tbs addapp <name> [domain])"
            echo "  removeapp   Remove an application (usage: tbs removeapp <name> [domain])"
            echo "  code        Open VS Code for an app (usage: tbs code [name])"
            echo "  config      Configure the environment"
            echo "  backup      Backup databases and applications"
            echo "  restore     Restore from a backup"
            echo "  ssl         Generate SSL certificates (usage: tbs ssl <domain>)"
            echo "  ssl-default Generate default localhost SSL certificates"
            echo "  logs        Show logs (usage: tbs logs [service])"
            echo "  status      Show stack status"
            echo "  mail        Open Mailpit"
            echo "  pma         Open phpMyAdmin"
            echo "  redis-cli   Open Redis CLI"
            echo ""
        else
            print_header
            error_message "Unknown command: $1"
            echo "Run 'tbs help' for usage or 'tbs' for the interactive menu."
        fi
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

# Add tbs function to shell config (zsh/bash)
add_tbs_to_shell() {
    local shell_rc=""
    if [ -f "$HOME/.zshrc" ]; then
        shell_rc="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        shell_rc="$HOME/.bashrc"
    fi
    
    if [ -n "$shell_rc" ] && ! grep -q "tbs()" "$shell_rc"; then
        cat >> "$shell_rc" << EOF

# Turbo Stack helper function
tbs() {
    bash "$tbsFile" "\$@"
}
EOF
        info_message "Function 'tbs' added to $(basename $shell_rc)"
    fi
}

add_tbs_to_shell

# Run tbs with all arguments
tbs "$@"
