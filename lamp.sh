#!/bin/bash

# Get lamp script directory
lampFile=$(readlink -f "$0")
lampPath=$(dirname "$lampFile")
# echo $lampPath;

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

# Function to prompt for input with a default value
prompt_with_default() {
    local prompt_message=$1
    local default_value=$2
    local user_input

    read -p "$prompt_message [$default_value]: " user_input

    # If input is empty, use default value
    if [ -z "$user_input" ]; then
        user_input=$default_value
    fi

    echo $user_input
}

# Function to read array input from user and validate
read_array_value() {
    local arr_name="$1"
    local count=${2:-1}

    echo ""
    echo "Enter array values separated by spaces:"
    read -a temp_array

    # Validate each input
    for value in "${temp_array[@]}"; do
        if ! is_integer "$value"; then
            error_message "Invalid value: $value"
            ((count++))
            if [[ $count -le 3 ]]; then
                attempt_message $count
                read_array_value $arr_name $count
            else
                red_message "Exceeded maximum attempts. Exiting."
                exit 1
            fi

        fi
    done

    # Assign the temporary array to the named array if all values are valid
    eval "$arr_name=(\"\${temp_array[@]}\")"
}

is_integer() {
    local var="$1"
    if [[ "$var" =~ ^-?[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

is_array() {
    local var_name="$1"
    if declare -p "$var_name" 2>/dev/null | grep -q 'declare \-a'; then
        return 0
    else
        return 1
    fi
}

generate_ssl_certificates() {
    domain=$1
    vhost_file=$2

    # Generate SSL certificates for the domain
    mkcert -key-file "$lampPath/config/ssl/$domain-key.pem" -cert-file "$lampPath/config/ssl/$domain-cert.pem" $domain "*.$domain"

    # Update the vhost configuration file with the correct SSL certificate paths
    sed -i "" "s|SSLCertificateFile /etc/apache2/ssl/cert.pem|SSLCertificateFile /etc/apache2/ssl/$domain-cert.pem|" $vhost_file
    sed -i "" "s|SSLCertificateKeyFile /etc/apache2/ssl/cert-key.pem|SSLCertificateKeyFile /etc/apache2/ssl/$domain-key.pem|" $vhost_file

    info_message "SSL certificates generated for https://$domain"
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
    reqConfig=("DOCUMENT_ROOT" "COMPOSE_PROJECT_NAME" "PHPVERSION" "DATABASE")

    # Detect if Apple Silicon
    isAppleSilicon=false
    if [[ $(uname -m) == 'arm64' ]]; then
        isAppleSilicon=true
    fi

    # Function to dynamically fetch PHP versions and databases from ./bin
    fetch_dynamic_versions() {
        local bin_dir="$lampPath/bin"
        phpVersions=()
        databaseList=()

        for entry in "$bin_dir"/*; do
            entry_name=$(basename "$entry")
            if ([[ -d "$entry" ]] && [[ "$entry_name" == php* ]]); then
                phpVersions+=("$entry_name")
            elif [[ -d "$entry" ]]; then
                databaseList+=("$entry_name")
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
        if $isAppleSilicon; then
            yellow_message "Apple Silicon detected. Only MariaDB options are available."
            databaseOptions=("${databaseList[@]:2}") # Only MariaDB options
        else
            # For PHP versions <= 7.4, MySQL 8 is excluded
            if [[ "$PHPVERSION" =~ php5[4-6] || "$PHPVERSION" == "php71" || "$PHPVERSION" == "php72" || "$PHPVERSION" == "php73" || "$PHPVERSION" == "php74" ]]; then
                yellow_message "Available databases (MySQL 8 is not supported for PHP versions <= 7.4):"
                databaseOptions=("${databaseList[@]:0:5}") # MySQL 5.7 and MariaDB options
            else
                blue_message "Available databases:"
                databaseOptions=("${databaseList[@]}")
            fi
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
            else
                read -p "$key (Default: $default_value): " new_value
                if [[ ! -z $new_value ]]; then
                    eval "$key=$new_value"
                fi
            fi

            # Update the .env file
            sed -i "" "s|^$key=.*|$key=${!key}|" .env 2>/dev/null || echo "$key=${!key}" >>.env
        done

        green_message ".env file updated!"
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

        # Wait for Docker to start
        while ! docker info >/dev/null 2>&1; do
            yellow_message "Waiting for Docker to start..."
            sleep 2
        done
        info_message "Docker is running."

    fi

    # Start the containers in detached mode
    if ! docker-compose up -d; then
        error_message "Failed to start the LAMP stack."
        exit 1
    fi

    # for cutom .env file
    # docker-compose --env-file <env_file_path> up -d --build

    green_message "LAMP stack is running"
}

lamp() {

    # go to lamp path
    cd "$lampPath"

    # Load environment variables from .env file
    if [[ -f .env ]]; then
        # Load all variables while excluding comments
        export $(grep -v '^#' .env | xargs)
    elif [[ $1 != "config" ]]; then
        # error_message ".env file not found. RUN '$ lamp config'"
        # return 1
        info_message ".env file not found. running.'$ lamp config'"
        lamp_config
    fi

    # Check LAMP stack status
    if ! docker-compose ps | grep -q "webserver"; then
        yellow_message "LAMP stack is not running. Starting LAMP stack..."
        lamp_start
    fi

    # Start the LAMP stack using Docker
    if [[ $1 == "start" ]]; then
        # Open the domain in the default web browser
        open_browser "http://localhost"

    # Stop the LAMP stack
    elif [[ $1 == "stop" ]]; then
        docker-compose down
        green_message "LAMP stack is stopped"

        # Optional: Close Docker Desktop on stop (uncomment if needed)
        # case "$(uname -s)" in
        # Darwin)
        #     osascript -e 'quit app "Docker"'
        #     ;;
        # Linux)
        #     sudo systemctl stop docker
        #     ;;
        # CYGWIN* | MINGW32* | MSYS* | MINGW*)
        #     taskkill //IM "Docker Desktop.exe" //F
        #     ;;
        # *)
        #     yellow_message "Unsupported OS. Please close Docker manually."
        #     ;;
        # esac
        # green_message "Docker is stopped"

    # Open a bash shell inside the webserver container
    elif [[ $1 == "cmd" ]]; then
        docker-compose exec webserver bash

    # Restart the LAMP stack
    elif [[ $1 == "restart" ]]; then
        docker-compose down && docker-compose up -d
        green_message "LAMP stack restarted."

    # Add a new application and create a corresponding virtual host
    elif [[ $1 == "addapp" ]]; then
        # Validate if the application name is provided
        if [[ -z $2 ]]; then
            error_message "Application name is required."
            return 1
        fi

        app_name=$2
        domain=$3
        # Allowed TLDs stored in a variable
        allowed_tlds="\.localhost|\.com|\.org|\.net|\.info|\.biz|\.name|\.pro|\.aero|\.coop|\.museum|\.jobs|\.mobi|\.travel|\.asia|\.cat|\.tel|\.app|\.blog|\.shop|\.xyz|\.tech|\.online|\.site|\.web|\.store|\.club|\.media|\.news|\.agency|\.guru|\.in|\.co.in|\.ai.in|\.net.in|\.org.in|\.firm.in|\.gen.in|\.ind.in|\.com.au|\.co.uk|\.co.nz|\.co.za|\.com.br|\.co.jp|\.ca|\.de|\.fr|\.cn|\.ru|\.us"

        # Set default domain to <app_name>.localhost if not provided
        if [[ -z $domain ]]; then
            domain="${app_name}.localhost"
        else
            # Check if the domain matches the allowed TLDs
            if [[ ! $domain =~ ^[a-zA-Z0-9.-]+($allowed_tlds)$ ]]; then
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
        vhost_dir="$VHOSTS_DIR"
        vhost_file="${vhost_dir}/${domain}.conf"

        # Create the vhost directory if it doesn't exist
        if [[ ! -d $vhost_dir ]]; then
            mkdir -p $vhost_dir
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

        green_message "Vhost configuration file created at: $vhost_file"

        # Check if mkcert is installed
        if command -v mkcert &>/dev/null; then

            generate_ssl_certificates $domain $vhost_file
            domainUrl="https://$domain"
        else
            yellow_message "SSL certificates not generated. Using http://$domain"
            domainUrl="http://$domain"
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
        sed -e "s|exmple.com|$domain|g" \
            -e "s|index.html|index.php|g" \
            -e "s|/var/www/html|$app_root|g" \
            -e "s|lamp code|lamp code $app_name|g" \
            $indexHtml > $index_file
        info_message "index.php created at $index_file"

        # Enable the new virtual host and reload Apache
        yellow_message "Activating the virtual host..."
        if command -v docker >/dev/null; then
            # docker-compose exec webserver bash -c "cd /etc/apache2/sites-enabled && a2ensite $domain.conf && service apache2 reload"
            docker-compose exec webserver bash -c "service apache2 reload"

            green_message "Virtual host $domain activated and Apache reloaded."
        fi

        # Open the domain in the default web browser
        open_browser "$domainUrl"

        green_message "App setup complete: $app_name with domain $domain"

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
        backup_file="$backup_dir/lamp_backup_$timestamp.tar.gz"

        info_message "Backing up LAMP stack to $backup_file..."
        docker-compose exec webserver bash -c 'exec mysqldump --all-databases -uroot -p"$MYSQL_ROOT_PASSWORD" -h database' >"$backup_dir/db_backup.sql"
        tar -czvf "$backup_file" -C "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME" . -C "$backup_dir" db_backup.sql
        rm "$backup_dir/db_backup.sql"
        green_message "Backup completed: $backup_file"

    # Restore the LAMP stack
    elif [[ $1 == "restore" ]]; then
        backup_dir="$lampPath/data/backup"
        if [[ ! -d $backup_dir ]]; then
            error_message "Backup directory not found: $backup_dir"
            return 1
        fi

        backup_files=($(ls -t "$backup_dir"/*.tar.gz))
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
        tar -xzvf "$selected_backup" -C "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME"
        docker-compose exec webserver bash -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -h database' <"$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/db_backup.sql"
        rm "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/db_backup.sql"
        green_message "Restore completed from $selected_backup"

    # Generate SSL certificates for a domain
    elif [[ $1 == "ssl" ]]; then

        # Check if mkcert is installed
        if ! command -v mkcert &>/dev/null; then
            error_message "mkcert is not installed."
            info_message "For Install. Please follow the instructions at https://github.com/FiloSottile/mkcert#installation."
            return 1
        fi

        domain=$2
        if [[ -z $domain ]]; then
            error_message "Domain name is required."
            return 1
        fi

        vhost_file="${VHOSTS_DIR}/${domain}.conf"

        if [[ ! -f $vhost_file ]]; then
            error_message "Domain name invalid. Vhost configuration file not found for $domain."
            return 1
        fi

        generate_ssl_certificates $domain $vhost_file

    else
        error_message "Usage: lamp {start|stop|restart|cmd|addapp|code|config|backup|restore|ssl}"
    fi
}

# Check if required commands are available
required_commands=("docker" "docker-compose" "sed" "curl" "awk" "dd" "tee" "unzip")
for cmd in "${required_commands[@]}"; do
    if ! command_exists "$cmd"; then
        error_message "Required command '$cmd' is not installed."
        exit 1
    fi
done

# Check if 'lamp' function already exists in .zshrc
if [ -f "$HOME/.zshrc" ] && ! grep -q "lamp()" "$HOME/.zshrc"; then
    echo "
# docker compose lamp
lamp() {
  bash \"$lampFile\" \$1 \$2 \$3
}" >>"$HOME/.zshrc"
    info_message "Function 'lamp' added to .zshrc"
fi

lamp "$1" "$2" "$3"
