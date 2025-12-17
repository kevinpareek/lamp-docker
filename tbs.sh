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

# Allowed TLDs for application domains
ALLOWED_TLDS="\.localhost|\.com|\.org|\.net|\.info|\.biz|\.name|\.pro|\.aero|\.coop|\.museum|\.jobs|\.mobi|\.travel|\.asia|\.cat|\.tel|\.app|\.blog|\.shop|\.xyz|\.tech|\.online|\.site|\.web|\.store|\.club|\.media|\.news|\.agency|\.guru|\.in|\.co.in|\.ai.in|\.net.in|\.org.in|\.firm.in|\.gen.in|\.ind.in|\.com.au|\.co.uk|\.co.nz|\.co.za|\.com.br|\.co.jp|\.ca|\.de|\.fr|\.cn|\.ru|\.us"

# Colors and Styles
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
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

# Open file in available editor (respects EDITOR env var)
open_in_editor() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        error_message "File not found: $file"
        return 1
    fi
    
    if [[ -n "$EDITOR" ]] && command_exists "$EDITOR"; then
        "$EDITOR" "$file"
    elif command_exists code; then
        code "$file"
    elif command_exists nano; then
        nano "$file"
    elif command_exists vim; then
        vim "$file"
    elif command_exists vi; then
        vi "$file"
    else
        error_message "No editor found. Set EDITOR env var or install code/nano/vim."
        info_message "Edit manually: $file"
        return 1
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Load KEY=VALUE pairs from an env file.
# - Ignores blank lines and comments.
# - Supports optional surrounding single/double quotes.
# - Does NOT evaluate shell (no command substitution / expansions).
load_env_file() {
    local env_file="$1"
    local export_vars="${2:-false}"

    [[ -f "$env_file" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim leading whitespace
        line="${line#"${line%%[![:space:]]*}"}"

        # Skip blanks/comments
        [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

        # Allow optional 'export '
        [[ "$line" == export\ * ]] && line="${line#export }"

        # Only accept KEY=VALUE
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Trim trailing whitespace
            value="${value%"${value##*[![:space:]]}"}"

            # Strip surrounding quotes
            if [[ "$value" =~ ^\"(.*)\"$ ]]; then
                value="${BASH_REMATCH[1]}"
            elif [[ "$value" =~ ^'(.*)'$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            printf -v "$key" '%s' "$value"
            if [[ "$export_vars" == "true" ]]; then
                export "$key"
            fi
        fi
    done < "$env_file"
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

# Detect OS
get_os_type() {
    case "$(uname -s)" in
        Darwin) echo "mac" ;;
        Linux) echo "linux" ;;
        CYGWIN*|MINGW32*|MSYS*|MINGW*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

# Prevent Git Bash from rewriting docker paths on Windows
prepare_windows_path_handling() {
    if [[ "$(get_os_type)" == "windows" ]]; then
        export MSYS_NO_PATHCONV=1
        export MSYS2_ARG_CONV_EXCL="*"
    fi
}

install_tbs_command() {
    local bin_dir="${HOME}/.tbs/bin"
    local wrapper_path="${bin_dir}/tbs"
    local config_file="${HOME}/.tbs/config"
    local marker="# tbs-cli-path"
    local needs_shell_restart=false

    mkdir -p "$bin_dir" 2>/dev/null || true

    # Store current tbs.sh path in config file (updated on every run)
    echo "$tbsFile" > "$config_file"

    # Create smart wrapper that reads path from config (auto-updates when project moves)
    cat > "$wrapper_path" <<'WRAPPER'
#!/usr/bin/env bash
CONFIG_FILE="${HOME}/.tbs/config"
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ -f "$CONFIG_FILE" ]]; then
    TBS_SCRIPT="$(cat "$CONFIG_FILE")"
    if [[ -f "$TBS_SCRIPT" ]]; then
        exec "$TBS_SCRIPT" "$@"
    else
        echo ""
        echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║              ⚠️  TBS Project Not Found                      ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}Last known location:${NC}"
        echo -e "  $TBS_SCRIPT"
        echo ""
        echo -e "${CYAN}This usually happens when:${NC}"
        echo "  • The project folder was moved or renamed"
        echo "  • The project was deleted"
        echo "  • The drive/volume is not mounted"
        echo ""
        echo -e "${CYAN}To fix this, run tbs.sh from its new location:${NC}"
        echo -e "  ${YELLOW}cd /path/to/turbo-stack && ./tbs.sh${NC}"
        echo ""
        echo -e "${CYAN}Or uninstall tbs command:${NC}"
        echo -e "  ${YELLOW}rm -rf ~/.tbs${NC}"
        echo ""
        exit 1
    fi
else
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              ⚠️  TBS Not Configured                         ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}First time setup:${NC}"
    echo "  1. Navigate to your Turbo Stack project folder"
    echo "  2. Run: ${YELLOW}./tbs.sh${NC}"
    echo ""
    echo -e "${CYAN}This will:${NC}"
    echo "  • Configure the 'tbs' command globally"
    echo "  • Set up your development environment"
    echo ""
    exit 1
fi
WRAPPER
    chmod +x "$wrapper_path" 2>/dev/null || true

    # Add to current session PATH if not present
    case ":$PATH:" in
        *:"$bin_dir":*) ;;
        *) export PATH="$bin_dir:$PATH" ;;
    esac

    # Detect user's default shell config file
    local shell_rc=""
    local current_shell="${SHELL##*/}"
    
    case "$current_shell" in
        zsh)  shell_rc="$HOME/.zshrc" ;;
        bash) [[ -f "$HOME/.bashrc" ]] && shell_rc="$HOME/.bashrc" || shell_rc="$HOME/.bash_profile" ;;
        fish) shell_rc="$HOME/.config/fish/config.fish" ;;
        *)
            for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile"; do
                [[ -f "$rc" ]] && { shell_rc="$rc"; break; }
            done
            [[ -z "$shell_rc" ]] && shell_rc="$HOME/.profile"
            ;;
    esac

    # Ensure rc file directory and file exist
    mkdir -p "$(dirname "$shell_rc")" 2>/dev/null || true
    touch "$shell_rc" 2>/dev/null || true

    # Add PATH to shell config (only once, using marker)
    if [[ -f "$shell_rc" ]] && ! grep -qF "$marker" "$shell_rc" 2>/dev/null; then
        needs_shell_restart=true
        if [[ "$current_shell" == "fish" ]]; then
            cat >> "$shell_rc" <<FISH_RC

$marker
if not contains "$bin_dir" \$PATH
    set -gx PATH "$bin_dir" \$PATH
end
FISH_RC
        else
            cat >> "$shell_rc" <<POSIX_RC

$marker
export PATH="$bin_dir:\$PATH"
POSIX_RC
        fi
    fi

    # Fish: create function wrapper for better integration
    if command_exists fish || [[ -d "$HOME/.config/fish" ]]; then
        local fish_func_dir="$HOME/.config/fish/functions"
        mkdir -p "$fish_func_dir" 2>/dev/null || true
        cat > "$fish_func_dir/tbs.fish" <<'FISH_FN'
function tbs --description 'Turbo Stack CLI'
    bash "TBS_SCRIPT_PLACEHOLDER" $argv
end
FISH_FN
        sed_i "s|TBS_SCRIPT_PLACEHOLDER|$tbsFile|g" "$fish_func_dir/tbs.fish"
    fi

    # Windows: CMD and PowerShell shims
    if [[ "$(get_os_type)" == "windows" ]]; then
        local win_script="$tbsFile"
        command_exists cygpath && win_script="$(cygpath -w "$tbsFile")"

        cat > "${bin_dir}/tbs.cmd" <<'CMD_EOF'
@echo off
setlocal enabledelayedexpansion
set "BASH="
for %%p in ("%ProgramFiles%\Git\bin\bash.exe" "%ProgramFiles(x86)%\Git\bin\bash.exe" "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" "C:\msys64\usr\bin\bash.exe") do (
    if exist "%%~p" set "BASH=%%~p"
)
if defined BASH (
    "%BASH%" "TBS_WIN_PATH" %*
) else (
    where wsl >nul 2>&1 && (wsl bash "TBS_NIX_PATH" %*) || (echo Error: bash not found & exit /b 1)
)
CMD_EOF
        sed_i "s|TBS_WIN_PATH|$win_script|g" "${bin_dir}/tbs.cmd"
        sed_i "s|TBS_NIX_PATH|$tbsFile|g" "${bin_dir}/tbs.cmd"

        cat > "${bin_dir}/tbs.ps1" <<'PS_EOF'
$bash = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
    "C:\msys64\usr\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($bash) { & $bash "TBS_WIN_PATH" @args }
elseif (Get-Command wsl -EA 0) { wsl bash "TBS_NIX_PATH" @args }
else { Write-Error "bash not found. Install Git for Windows or WSL."; exit 1 }
PS_EOF
        sed_i "s|TBS_WIN_PATH|$win_script|g" "${bin_dir}/tbs.ps1"
        sed_i "s|TBS_NIX_PATH|$tbsFile|g" "${bin_dir}/tbs.ps1"

        # Add to Windows user PATH
        if command_exists powershell.exe; then
            local win_bin="$bin_dir"
            command_exists cygpath && win_bin="$(cygpath -w "$bin_dir")"
            powershell.exe -NoProfile -Command "
                \$p=[Environment]::GetEnvironmentVariable('PATH','User')
                if(\$p -notlike '*$win_bin*'){[Environment]::SetEnvironmentVariable('PATH',\"$win_bin;\$p\",'User')}" 2>/dev/null || true
        fi
    fi

    # Linux: symlink to ~/.local/bin
    if [[ "$(get_os_type)" == "linux" ]]; then
        local local_bin="$HOME/.local/bin"
        mkdir -p "$local_bin" 2>/dev/null || true
        ln -sf "$wrapper_path" "$local_bin/tbs" 2>/dev/null || true
    fi

    # macOS: symlink to /usr/local/bin if writable
    if [[ "$(get_os_type)" == "mac" && -w "/usr/local/bin" ]]; then
        ln -sf "$wrapper_path" "/usr/local/bin/tbs" 2>/dev/null || true
    fi

    # Show first-run hint if shell config was modified
    if [[ "$needs_shell_restart" == "true" ]]; then
        echo ""
        info_message "✓ 'tbs' command installed! Run 'source $shell_rc' or restart terminal to use it globally."
    fi
}

# Get webserver service name based on stack mode
get_webserver_service() {
    if [[ "${STACK_MODE:-hybrid}" == "thunder" ]]; then
        echo "webserver-fpm"
    else
        echo "webserver-apache"
    fi
}

# Build docker compose profiles string
build_profiles() {
    local profiles="--profile ${STACK_MODE:-hybrid}"
    if [[ "${APP_ENV:-development}" == "development" ]]; then
        profiles="$profiles --profile development"
    fi
    echo "$profiles"
}

# Get all profiles for complete stack operations
get_all_profiles() {
    echo "--profile hybrid --profile thunder --profile development --profile tools"
}

# Ensure required directories exist
ensure_directories() {
    local dirs=("${VHOSTS_DIR}" "${NGINX_CONF_DIR}" "${SSL_DIR}")
    for dir in "${dirs[@]}"; do
        if [[ -n "$dir" && ! -d "$dir" ]]; then
            mkdir -p "$dir" 2>/dev/null || true
        fi
    done
}

# Check if required containers are running
check_containers_running() {
    local check_webserver="${1:-true}"
    local check_database="${2:-true}"
    
    if [[ "$check_webserver" == "true" ]]; then
        if [[ -z "$(docker compose ps -q "$WEBSERVER_SERVICE")" ]]; then
            error_message "Webserver container is not running. Please start the stack first."
            return 1
        fi
    fi
    
    if [[ "$check_database" == "true" ]]; then
        if [[ -z "$(docker compose ps -q database)" ]]; then
            error_message "Database container is not running. Please start the stack first."
            return 1
        fi
    fi
    
    return 0
}

# Execute MySQL command through webserver container
execute_mysql_command() {
    local mysql_command="$1"
    
    docker compose exec -T "$WEBSERVER_SERVICE" bash -c "exec mysql -uroot -p\"$MYSQL_ROOT_PASSWORD\" -h database $mysql_command" 2>/dev/null
}

# Execute MySQL dump through webserver container
execute_mysqldump() {
    local database="$1"
    local output_file="$2"
    
    docker compose exec -T "$WEBSERVER_SERVICE" bash -c "exec mysqldump -uroot -p\"$MYSQL_ROOT_PASSWORD\" -h database --databases $database" >"$output_file" 2>/dev/null
}

# Reload Web Servers
reload_webservers() {
    # Ensure WEBSERVER_SERVICE is set if not already
    if [[ -z "$WEBSERVER_SERVICE" ]]; then
        WEBSERVER_SERVICE=$(get_webserver_service)
    fi

    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi

    # Only reload if containers are actually running (docker compose ps returns 0 even when empty)
    local ws_cid rp_cid
    ws_cid="$(docker compose ps -q "$WEBSERVER_SERVICE" 2>/dev/null || true)"
    rp_cid="$(docker compose ps -q reverse-proxy 2>/dev/null || true)"

    if [[ -z "$ws_cid" || -z "$rp_cid" ]]; then
        return 0
    fi

    yellow_message "Reloading web servers..."
    if [[ "$WEBSERVER_SERVICE" == "webserver-apache" ]]; then
        docker compose exec -T "$WEBSERVER_SERVICE" bash -c "service apache2 reload" 2>/dev/null || true
    fi
    docker compose exec -T reverse-proxy nginx -s reload 2>/dev/null || true
    green_message "Web servers reloaded."
}

# Ensure Docker is running
ensure_docker_running() {
    if ! docker info >/dev/null 2>&1; then
        yellow_message "Docker daemon is not running. Starting Docker daemon..."
        
        case "$(get_os_type)" in
            mac) open -a Docker ;;
            linux) sudo systemctl start docker ;;
            windows)
                # "start" is a CMD built-in; call it via cmd.exe so it works from Git Bash too.
                if command_exists cmd.exe; then
                    cmd.exe /c start "" "C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe" >/dev/null 2>&1 || true
                elif command_exists powershell.exe; then
                    powershell.exe -NoProfile -Command "Start-Process 'C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe'" >/dev/null 2>&1 || true
                else
                    error_message "Cannot auto-start Docker Desktop (cmd.exe/powershell.exe not found). Please start Docker manually."
                    exit 1
                fi
                ;;
            *) error_message "Unsupported OS. Please start Docker manually."; exit 1 ;;
        esac

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
}

cleanup_stack_networks() {
    # Remove leftover project networks that sometimes stay attached on Windows
    local frontend_net="${COMPOSE_PROJECT_NAME:-turbo-stack}-frontend"
    local backend_net="${COMPOSE_PROJECT_NAME:-turbo-stack}-backend"

    for net in "$frontend_net" "$backend_net"; do
        if docker network inspect "$net" >/dev/null 2>&1; then
            yellow_message "Cleaning up network $net..."
            local containers
            containers=$(docker network inspect "$net" --format '{{range $id,$c := .Containers}}{{$id}} {{end}}')
            if [[ -n "$containers" ]]; then
                for cid in $containers; do
                    docker network disconnect -f "$net" "$cid" >/dev/null 2>&1 || true
                done
            fi
            docker network rm "$net" >/dev/null 2>&1 || true
        fi
    done
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
    info_message "Installing mkcert for SSL certificate generation..."

    case "$(get_os_type)" in
        mac)
            # macOS installation
            if command_exists brew; then
                brew install mkcert nss
            else
                error_message "Homebrew not found. Please install Homebrew first: https://brew.sh"
                return 1
            fi
            ;;
        linux)
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
        windows)
            # Windows installation
            if command_exists choco; then
                choco install -y mkcert --no-progress
            else
                error_message "Chocolatey not found. Please install Chocolatey first: https://chocolatey.org/install"
                return 1
            fi
            ;;
        *)
            error_message "Unsupported operating system."
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
    if ! command_exists mkcert; then
         if yes_no_prompt "mkcert is not installed. Install now?"; then
             if ! install_mkcert; then
                 return 1
             fi
         else
             return 1
         fi
    fi

    local ssl_config_dir="${SSL_DIR:-$tbsPath/sites/ssl}"
    SSL_DIR="$ssl_config_dir"
    ensure_directories

    if mkcert -key-file "${SSL_DIR}/cert-key.pem" -cert-file "${SSL_DIR}/cert.pem" "localhost" "www.localhost" "127.0.0.1" "::1"; then
        green_message "Default SSL certificates (localhost) generated in sites/ssl/"
        
        # Reload if running
        reload_webservers
    else
        error_message "Failed to generate default SSL certificates."
    fi
}

generate_ssl_certificates() {
    local domain=$1
    local vhost_file=$2
    local nginx_file=$3

    local use_mkcert=false
    local ssl_generated=false

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
        # Ensure SSL_DIR exists before generating certificates
        ensure_directories
        
        # Ensure certbot service is running or run it as a one-off command
        # We use webroot mode because nginx is already running and serving /.well-known/acme-challenge/
        # We override the entrypoint because the default entrypoint in docker-compose.yml is a renewal loop that ignores arguments
        
        if docker compose run --rm --entrypoint certbot certbot certonly --webroot --webroot-path=/var/www/html -d "$domain" -d "www.$domain" --email "admin@$domain" --agree-tos --no-eff-email; then
            
            # Certbot saves certs in /etc/letsencrypt/live/$domain/
            # We need to copy them to our sites/ssl directory so Nginx can see them as expected
            # Note: In docker-compose, we mapped ./data/certbot/conf to /etc/letsencrypt
            
            # The path inside the host machine (relative to tbs.sh)
            local cert_path="$tbsPath/data/certbot/conf/live/$domain"
            
            # Ensure SSL_DIR exists
            ensure_directories
            
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
        if ! command_exists mkcert; then
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
        ensure_directories
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
        sed_i "s|SSLCertificateFile /etc/apache2/ssl-sites/cert.pem|SSLCertificateFile /etc/apache2/ssl-sites/$domain-cert.pem|; s|SSLCertificateKeyFile /etc/apache2/ssl-sites/cert-key.pem|SSLCertificateKeyFile /etc/apache2/ssl-sites/$domain-key.pem|" "$vhost_file"

        sed_i "s|ssl_certificate /etc/nginx/ssl-sites/cert.pem|ssl_certificate /etc/nginx/ssl-sites/$domain-cert.pem|; s|ssl_certificate_key /etc/nginx/ssl-sites/cert-key.pem|ssl_certificate_key /etc/nginx/ssl-sites/$domain-key.pem|" "$nginx_file"

        info_message "SSL certificates configured for https://$domain"
        return 0
    fi
}

open_browser() {
    local domain=$1

    # Open the domain in the default web browser
    info_message "Opening $domain in the default web browser..."

    case "$(get_os_type)" in
        mac)
            open "$domain"
            ;;
        linux)
            xdg-open "$domain"
            ;;
        windows)
            if command_exists cmd.exe; then
                cmd.exe /c start "" "$domain" >/dev/null 2>&1 || true
            elif command_exists powershell.exe; then
                powershell.exe -NoProfile -Command "Start-Process '$domain'" >/dev/null 2>&1 || true
            else
                error_message "Cannot auto-open browser (cmd.exe/powershell.exe not found). Please open $domain manually."
            fi
            ;;
        *)
            error_message "Unsupported OS. Please open $domain manually."
            ;;
    esac
}

tbs_config() {
    print_header
    # Set required configuration keys
    reqConfig=("INSTALLATION_TYPE" "APP_ENV" "STACK_MODE" "PHPVERSION" "DATABASE")

    # Track whether we already had a .env (only prompt INSTALLATION_TYPE on first run)
    local existing_env_file=true

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
        if [[ "$(get_os_type)" == "linux" ]]; then
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
        if [[ "$PHPVERSION" == "php7.4" ]]; then
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
                if [[ "$existing_env_file" == "false" ]]; then
                    choose_installation_type
                else
                    INSTALLATION_TYPE=${INSTALLATION_TYPE:-local}
                fi
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

    # Main logic
    if [ -f .env ]; then
        info_message "Reading config from .env..."
        load_env_file ".env" false
    elif [ -f sample.env ]; then
        yellow_message "No .env file found, using sample.env..."
        cp sample.env .env
        load_env_file "sample.env" false
        existing_env_file=false
    else
        error_message "No .env or sample.env file found."
        exit 1
    fi

    # Fetch dynamic PHP versions and database list from ./bin directory
    fetch_dynamic_versions

    # Display current configuration and prompt for updates
    update_env_file
}

tbs_start() {
    # Check if Docker daemon is running
    ensure_docker_running

    # Build and start containers
    info_message "Starting Turbo Stack (${APP_ENV:-development} mode, ${STACK_MODE:-hybrid} stack)..."
    
    PROFILES=$(build_profiles)

    if ! docker compose $PROFILES up -d; then
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
        echo "   10) App PHP Config"

        echo -e "\n${BLUE}⚙️ Configuration & Tools${NC}"
        echo "   11) Configure Environment"
        echo "   12) Backup Data"
        echo "   13) Restore Data"
        echo "   14) SSL Certificates"
        echo "   15) Open Mailpit"
        echo "   16) Open phpMyAdmin"
        echo "   17) Redis CLI"
        echo "   18) Shell Access (Bash)"

        echo -e "\n   ${RED}0) Exit${NC}"
        
        echo ""
        read -p "Enter your choice [0-18]: " choice

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
            10)
                echo ""
                tbs phpconfig
                echo ""
                read -p "Enter app name to configure (or press Enter to skip): " app_name
                if [[ -n "$app_name" ]]; then
                    read -p "Action [create/edit/show/delete] (Default: show): " action
                    action=${action:-show}
                    tbs phpconfig "$app_name" "$action"
                fi
                ;;
            11) tbs config ;;
            12) tbs backup ;;
            13) tbs restore ;;
            14) 
                echo ""
                read -p "Enter domain name: " domain
                tbs ssl "$domain"
                ;;
            15) tbs mail ;;
            16) tbs pma ;;
            17) tbs redis-cli ;;
            18) tbs cmd ;;
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

    # Ensure docker paths are not mangled on Windows terminals (e.g., Git Bash)
    prepare_windows_path_handling

    # Install a convenience shim so `tbs` works globally on this machine
    install_tbs_command

    # Load environment variables from .env file
    if [[ -f .env ]]; then
        load_env_file ".env" true
    elif [[ $1 != "config" ]]; then
        info_message ".env file not found. Running 'tbs config'..."
        tbs_config
    fi

    # Determine webserver service name based on stack mode
    WEBSERVER_SERVICE=$(get_webserver_service)

    # Check Turbo Stack status
    if [[ "$1" =~ ^(start|addapp|removeapp|cmd|backup|restore|ssl|mail|pma|redis-cli)$ && -z "$(docker compose ps -q "$WEBSERVER_SERVICE")" ]]; then
        yellow_message "Turbo Stack is not running. Starting Turbo Stack..."
        tbs_start
    fi

    # Start the Turbo Stack using Docker
    case "$1" in
    start)
        # Open the domain in the default web browser
        open_browser "http://localhost"
        ;;

    # Stop the Turbo Stack
    stop)
        # Include all profiles to ensure every service is stopped
        ALL_PROFILES=$(get_all_profiles)
        docker compose $ALL_PROFILES down --remove-orphans
        cleanup_stack_networks
        green_message "Turbo Stack is stopped"
        ;;

    # Open a bash shell inside the webserver container
    cmd)
        docker compose exec "$WEBSERVER_SERVICE" bash
        ;;

    # Restart the Turbo Stack
    restart)
        PROFILES=$(build_profiles)
        # Always tear down everything regardless of profile before restart
        ALL_PROFILES=$(get_all_profiles)
        docker compose $ALL_PROFILES down --remove-orphans
        cleanup_stack_networks
        docker compose $PROFILES up -d
        green_message "Turbo Stack restarted."
        ;;

    # Rebuild & Start
    build)
        PROFILES=$(build_profiles)
        # Always tear down everything regardless of profile before rebuild
        ALL_PROFILES=$(get_all_profiles)
        docker compose $ALL_PROFILES down --remove-orphans
        cleanup_stack_networks
        docker compose $PROFILES up -d --build
        green_message "Turbo Stack rebuilt and running."
        ;;

    # Add a new application and create a corresponding virtual host
    addapp)
        # Validate if the application name is provided
        if [[ -z $2 ]]; then
            error_message "Application name is required."
            return 1
        fi

        local app_name=$2
        local domain=$3

        # Validate application name (alphanumeric, hyphens, underscores only)
        if [[ ! $app_name =~ ^[a-zA-Z0-9_-]+$ ]]; then
            error_message "Application name must contain only alphanumeric characters, hyphens, and underscores."
            return 1
        fi

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
        local vhost_file="${VHOSTS_DIR}/${domain}.conf"
        local nginx_file="${NGINX_CONF_DIR}/${domain}.conf"

        # Ensure required directories exist
        ensure_directories

        # Create the vhost configuration file
        yellow_message "Creating vhost configuration for $domain..."
        cat >"$vhost_file" <<EOL
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
    SSLCertificateFile /etc/apache2/ssl-sites/cert.pem
    SSLCertificateKeyFile /etc/apache2/ssl-sites/cert-key.pem
</VirtualHost>
EOL

        # Generate Nginx Configuration
        # Common configuration for both modes (Frontend -> Varnish)
        local nginx_config="# HTTP server configuration (Frontend -> Varnish)
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
    ssl_certificate /etc/nginx/ssl-sites/cert.pem;
    ssl_certificate_key /etc/nginx/ssl-sites/cert-key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    include /etc/nginx/includes/common.conf;
    include /etc/nginx/partials/varnish-proxy.conf;
}"

        # Add PHP-FPM backend for Thunder mode
        if [[ "$(get_webserver_service)" == "webserver-fpm" ]]; then
            nginx_config="$nginx_config

# Internal Backend for Varnish (Port 8080)
server {
    listen 8080;
    server_name $domain www.$domain;
    root $APACHE_DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name;
    index index.php index.html index.htm;

    include /etc/nginx/partials/php-fpm.conf;
}"
        fi

        # Write Nginx configuration to file
        echo "$nginx_config" > "$nginx_file"

        green_message "Vhost configuration file created at: $vhost_file"

        # Reload Nginx to ensure it serves the new domain (required for Let's Encrypt validation)
        reload_webservers

        # Check if SSL generation is needed
        local domainUrl
        if ! generate_ssl_certificates $domain $vhost_file $nginx_file; then
            domainUrl="http://$domain"
        else
            domainUrl="https://$domain"
        fi

        # Create the application document root directory
        local app_root="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name"
        if [[ ! -d $app_root ]]; then
            mkdir -p $app_root
            info_message "Created document root at $app_root"
        else
            yellow_message "Document root already exists at $app_root"
        fi

        # Create an index.php file in the app's document root
        local index_file="${app_root}/index.php"
        local indexHtml="$tbsPath/data/pages/site-created.html"
        if [[ -f "$indexHtml" ]]; then
            sed -e "s|example.com|$domain|g" \
                -e "s|index.html|index.php|g" \
                -e "s|/var/www/html|$app_root|g" \
                -e "s|tbs code|tbs code $app_name|g" \
                "$indexHtml" > "$index_file" 2>/dev/null || {
                # Fallback if sed fails
                cat > "$index_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Site Created: $domain</title>
</head>
<body>
    <h1>Site Created Successfully!</h1>
    <p>Domain: <strong>$domain</strong> is ready to use</p>
    <p>Run <code>tbs code $app_name</code> to edit files.</p>
</body>
</html>
EOF
            }
            info_message "index.php created at $index_file"
        else
            yellow_message "Template file not found, creating basic index.php"
            cat > "$index_file" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>Site Created: $domain</title>
</head>
<body>
    <h1>Site Created Successfully!</h1>
    <p>Domain: <strong>$domain</strong> is ready to use</p>
    <p>Run <code>tbs code $app_name</code> to edit files.</p>
</body>
</html>
EOF
        fi

        # Enable the new virtual host and reload Apache
        yellow_message "Activating the virtual host..."
        reload_webservers

        # Open the domain in the default web browser
        open_browser "$domainUrl"

        green_message "App setup complete: $app_name with domain $domain"
        
        # Ask if user wants to create custom PHP config
        echo ""
        if yes_no_prompt "Create custom PHP config (.user.ini) for this app?"; then
            tbs phpconfig "$app_name" create
        else
            info_message "You can create it later with: tbs phpconfig $app_name create"
        fi
        ;;

    # Remove an application
    removeapp)
        if [[ -z $2 ]]; then
            error_message "Application name is required."
            return 1
        fi

        local app_name=$2
        
        # Validate application name format
        if [[ ! $app_name =~ ^[a-zA-Z0-9_-]+$ ]]; then
            error_message "Invalid application name format."
            return 1
        fi
        
        # Try to find the domain from the vhost file or assume default
        # This is tricky because we don't store the mapping. 
        # We can search for the app_name in the vhosts directory.
        
        # Simple approach: Ask for domain or assume default
        local domain=$3
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

        local vhost_file="${VHOSTS_DIR}/${domain}.conf"
        local nginx_file="${NGINX_CONF_DIR}/${domain}.conf"
        local app_root="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name"

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
            reload_webservers
        else
            info_message "Operation cancelled."
        fi
        ;;

    # Show logs
    logs)
        local service=$2
        if [[ -z $service ]]; then
            docker compose logs -f
        else
            docker compose logs -f "$service"
        fi
        ;;

    # Show status
    status)
        docker compose ps
        ;;

    # Handle 'code' command to open application directories
    code)
        if [[ $2 == "root" || $2 == "tbs" ]]; then
            code "$tbsPath"
        else
            # If no argument is provided, list application directories and prompt for selection
            local apps_dir="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME"
            local app_dir
            if [[ -z $2 ]]; then
                if [[ -d $apps_dir ]]; then
                    echo "Available applications:"
                    local app_list=($(ls "$apps_dir" | grep -v '^tbs$')) # Exclude 'tbs' from listing
                    if [[ ${#app_list[@]} -eq 0 ]]; then
                        error_message "No applications found."
                        return
                    fi
                    local i
                    for i in "${!app_list[@]}"; do
                        blue_message "$((i + 1)). ${app_list[$i]}"
                    done
                    local app_num
                    read -p "Choose an application number: " app_num
                    if [[ "$app_num" -gt 0 && "$app_num" -le "${#app_list[@]}" ]]; then
                        local selected_app="${app_list[$((app_num - 1))]}"
                        app_dir="$apps_dir/$selected_app"
                        code "$app_dir"
                    else
                        error_message "Invalid selection."
                    fi
                else
                    error_message "Applications directory not found: $apps_dir"
                fi
            else
                local app_dir="$apps_dir/$2"
                if [[ -d $app_dir ]]; then
                    code "$app_dir"
                else
                    error_message "Application directory does not exist: $app_dir"
                fi
            fi
        fi
        ;;
    config)
        tbs_config
        ;;

    # Backup the Turbo Stack
    backup)
        local backup_dir="$tbsPath/data/backup"
        mkdir -p "$backup_dir"
        local timestamp=$(date +"%Y%m%d%H%M%S")
        local backup_file="$backup_dir/tbs_backup_$timestamp.tgz"

        info_message "Backing up Turbo Stack to $backup_file..."
        
        # Check if required containers are running
        if ! check_containers_running true true; then
            return 1
        fi
        
        local databases=$(execute_mysql_command "-e 'SHOW DATABASES;'" | grep -Ev "(Database|information_schema|performance_schema|mysql|phpmyadmin|sys)" || true)

        if [[ -z "$databases" ]]; then
            yellow_message "No databases found to backup."
        fi

        # Create temporary directories for SQL and app data
        local temp_sql_dir="$backup_dir/sql"
        local temp_app_dir="$backup_dir/app"
        mkdir -p "$temp_sql_dir" "$temp_app_dir"

        for db in $databases; do
            if [[ -n "$db" ]]; then
                local backup_sql_file="$temp_sql_dir/db_backup_$db.sql"
                if ! execute_mysqldump "$db" "$backup_sql_file"; then
                    yellow_message "Failed to backup database: $db"
                    rm -f "$backup_sql_file"
                fi
            fi
        done

        # Copy application data to the temporary app directory
        if [[ -d "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME" ]]; then
            cp -r "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/." "$temp_app_dir/" 2>/dev/null || true
        else
            yellow_message "Applications directory not found, skipping app backup."
        fi

        # Create the compressed backup file containing both SQL and app data
        if ! tar -czf "$backup_file" -C "$backup_dir" sql app 2>/dev/null; then
            error_message "Failed to create backup archive."
            rm -rf "$temp_sql_dir" "$temp_app_dir"
            return 1
        fi

        # Clean up temporary directories
        rm -rf "$temp_sql_dir" "$temp_app_dir"

        green_message "Backup completed: ${backup_file}"
        ;;

    # Restore the Turbo Stack
    restore)
        local backup_dir="$tbsPath/data/backup"
        if [[ ! -d $backup_dir ]]; then
            error_message "Backup directory not found: $backup_dir"
            return 1
        fi

        local backup_files=($(ls -t "$backup_dir"/*.tgz 2>/dev/null))
        if [[ ${#backup_files[@]} -eq 0 ]]; then
            error_message "No backup files found in $backup_dir"
            return 1
        fi

        echo "Available backups:"
        for i in "${!backup_files[@]}"; do
            local backup_file="${backup_files[$i]}"
            local backup_time
            # Cross-platform date command
            if [[ "$(get_os_type)" == "mac" ]]; then
                backup_time=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$backup_file" 2>/dev/null || date -r "$backup_file" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
            elif [[ "$(get_os_type)" == "linux" ]]; then
                backup_time=$(stat -c "%y" "$backup_file" 2>/dev/null | cut -d'.' -f1 || echo "unknown")
            else
                # Windows/Git Bash fallback
                backup_time=$(stat -c "%y" "$backup_file" 2>/dev/null | cut -d'.' -f1 || ls -l --time-style=long-iso "$backup_file" 2>/dev/null | awk '{print $6, $7}' || echo "unknown")
            fi
            echo "$((i + 1)). $(basename "$backup_file") (created on $backup_time)"
        done

        local backup_num
        read -p "Choose a backup number to restore: " backup_num
        # Validate input is numeric and within range
        if [[ ! "$backup_num" =~ ^[0-9]+$ ]] || [[ "$backup_num" -lt 1 ]] || [[ "$backup_num" -gt "${#backup_files[@]}" ]]; then
            error_message "Invalid selection. Please enter a number between 1 and ${#backup_files[@]}."
            return 1
        fi
        
        local selected_backup="${backup_files[$((backup_num - 1))]}"

        info_message "Restoring Turbo Stack from $selected_backup..."
        
        # Check if required containers are running
        if ! check_containers_running true true; then
            return 1
        fi
        
        # Create temp directory for extraction
        local temp_restore_dir="$backup_dir/restore_temp"
        mkdir -p "$temp_restore_dir"
        
        # Extract backup with error handling
        if ! tar -xzf "$selected_backup" -C "$temp_restore_dir" 2>/dev/null; then
            error_message "Failed to extract backup archive. The file may be corrupted."
            rm -rf "$temp_restore_dir"
            return 1
        fi
        
        # Restore Databases
        if [[ -d "$temp_restore_dir/sql" ]]; then
            info_message "Restoring databases..."
            for sql_file in "$temp_restore_dir/sql"/*.sql; do
                if [[ -f "$sql_file" ]]; then
                    db_name=$(basename "$sql_file" | sed 's/db_backup_//;s/\.sql//')
                    info_message "Restoring database: $db_name"
                    # Pipe content directly to mysql client
                    # Note: mysqldump with --databases includes CREATE DATABASE statement
                    if ! cat "$sql_file" | docker compose exec -T "$WEBSERVER_SERVICE" bash -c "exec mysql -uroot -p\"$MYSQL_ROOT_PASSWORD\" -h database" 2>/dev/null; then
                        yellow_message "Failed to restore database: $db_name"
                    fi
                fi
            done
        fi
        
        # Restore Applications
        if [[ -d "$temp_restore_dir/app" ]]; then
            info_message "Restoring applications..."
            # Ensure applications directory exists
            mkdir -p "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME"
            # Copy with error handling
            if ! cp -R "$temp_restore_dir/app/." "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/" 2>/dev/null; then
                yellow_message "Some application files may not have been restored."
            fi
        fi
        
        # Clean up
        rm -rf "$temp_restore_dir"
        
        green_message "Restore completed from $selected_backup"
        ;;

    # Generate SSL certificates for a domain
    ssl)
        local domain=$2
        if [[ -z $domain ]]; then
            error_message "Domain name is required."
            return 1
        fi

        local vhost_file="${VHOSTS_DIR}/${domain}.conf"
        local nginx_file="${NGINX_CONF_DIR}/${domain}.conf"

        if [[ ! -f $vhost_file ]]; then
            error_message "Domain name invalid. Vhost configuration file not found for $domain."
            return 1
        fi

        if generate_ssl_certificates $domain $vhost_file $nginx_file; then
            # Reload web servers to apply changes
            reload_webservers
        fi
        ;;

    # Generate Default SSL (localhost)
    ssl-localhost)
        generate_default_ssl
        ;;

    # Open Mailpit
    mail)
        open_browser "http://localhost:8025"
        ;;

    # Open phpMyAdmin
    pma)
        open_browser "http://localhost:${HOST_MACHINE_PMA_PORT}"
        ;;

    # Open Redis CLI
    redis-cli)
        docker compose exec redis redis-cli
        ;;

    # PHP Config - Per Application
    phpconfig)
        local app_name=$2
        local action=$3
        
        # Template paths (templates in /config, per-app configs in /sites for gitignore)
        local user_ini_template="$tbsPath/config/php/templates/app.user.ini.template"
        local pool_template="$tbsPath/config/php/templates/app.fpm-pool.conf.template"
        local pools_dir="$tbsPath/sites/php/pools"
        local apps_dir="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME"
        
        # Helper: List all apps with config status
        _phpconfig_list() {
            blue_message "Applications PHP Config Status:"
            echo ""
            if [[ -d "$apps_dir" ]]; then
                local found=0
                for app_dir in "$apps_dir"/*/; do
                    if [[ -d "$app_dir" ]]; then
                        found=1
                        local app=$(basename "$app_dir")
                        local status=""
                        
                        # Check .user.ini
                        [[ -f "$app_dir/.user.ini" ]] && status="${status}📄.user.ini "
                        
                        # Check FPM pool
                        [[ -f "$pools_dir/$app.conf" ]] && status="${status}⚙️pool.conf "
                        
                        if [[ -n "$status" ]]; then
                            green_message "  ✅ $app - $status"
                        else
                            info_message "  ⚪ $app - Using default PHP config"
                        fi
                    fi
                done
                [[ $found -eq 0 ]] && info_message "  No applications found."
            else
                error_message "Applications directory not found: $apps_dir"
            fi
        }
        
        # Helper: Show usage
        _phpconfig_usage() {
            echo ""
            blue_message "Current Mode: ${STACK_MODE:-hybrid}"
            echo ""
            blue_message "📄 .user.ini Commands (Works in BOTH modes - Hybrid & Thunder):"
            info_message "  tbs phpconfig <app> create      - Create .user.ini"
            info_message "  tbs phpconfig <app> edit        - Edit .user.ini"
            info_message "  tbs phpconfig <app> show        - Show .user.ini"
            info_message "  tbs phpconfig <app> delete      - Delete .user.ini"
            echo ""
            blue_message "⚙️ FPM Pool Commands (Thunder mode ONLY - PHP-FPM + Nginx):"
            if [[ "${STACK_MODE:-hybrid}" == "thunder" ]]; then
                info_message "  tbs phpconfig <app> create-pool - Create FPM pool"
                info_message "  tbs phpconfig <app> edit-pool   - Edit FPM pool config"
                info_message "  tbs phpconfig <app> show-pool   - Show FPM pool config"
                info_message "  tbs phpconfig <app> delete-pool - Delete FPM pool config"
            else
                yellow_message "  ⚠️  Not available in Hybrid mode (Apache mod_php)"
                info_message "  Use .user.ini for per-app config in Hybrid mode"
                info_message "  Or switch to Thunder mode: STACK_MODE=thunder in .env"
            fi
        }
        
        # No app name or 'list' - show list and usage
        if [[ -z "$app_name" ]] || [[ "$app_name" == "list" ]]; then
            _phpconfig_list
            _phpconfig_usage
            return 0
        fi
        
        local app_root="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_name"
        local user_ini="$app_root/.user.ini"
        local pool_conf="$pools_dir/$app_name.conf"
        
        if [[ ! -d "$app_root" ]]; then
            error_message "Application '$app_name' not found."
            return 1
        fi
        
        case "${action:-show}" in
            # ========== .user.ini commands ==========
            create)
                if [[ -f "$user_ini" ]]; then
                    yellow_message ".user.ini already exists for $app_name"
                    if ! yes_no_prompt "Overwrite existing config?"; then
                        return 0
                    fi
                fi
                
                # Use template if exists, otherwise create inline
                if [[ -f "$user_ini_template" ]]; then
                    cp "$user_ini_template" "$user_ini"
                    green_message "Created .user.ini from template for $app_name"
                else
                    cat > "$user_ini" <<'USERINI'
; ============================================
; Application-Specific PHP Configuration
; ============================================
; Only PHP_INI_PERDIR and PHP_INI_USER settings can be set here.
; Changes take effect within user_ini.cache_ttl (default: 300 seconds)

memory_limit = 512M
max_execution_time = 300
max_input_time = 300
upload_max_filesize = 64M
post_max_size = 64M
max_file_uploads = 20

; Session
session.gc_maxlifetime = 1440

; Add your app-specific settings below

USERINI
                    green_message "Created basic .user.ini for $app_name"
                fi
                info_message "Edit with: tbs phpconfig $app_name edit"
                ;;
            
            edit)
                if [[ ! -f "$user_ini" ]]; then
                    yellow_message ".user.ini not found. Creating from template..."
                    tbs phpconfig "$app_name" create
                    # Verify creation succeeded
                    [[ ! -f "$user_ini" ]] && return 0
                fi
                open_in_editor "$user_ini"
                ;;
            
            show)
                if [[ -f "$user_ini" ]]; then
                    blue_message "📄 .user.ini for $app_name:"
                    echo ""
                    cat "$user_ini"
                else
                    info_message "No .user.ini for $app_name"
                    info_message "Create with: tbs phpconfig $app_name create"
                fi
                ;;
            
            delete)
                if [[ -f "$user_ini" ]]; then
                    if yes_no_prompt "Delete .user.ini for $app_name?"; then
                        rm "$user_ini"
                        green_message "Deleted .user.ini for $app_name"
                    fi
                else
                    info_message "No .user.ini exists for $app_name"
                fi
                ;;
            
            # ========== FPM Pool commands ==========
            create-pool)
                if [[ "${STACK_MODE:-hybrid}" != "thunder" ]]; then
                    echo ""
                    red_message "⚠️  FPM pools are NOT supported in Hybrid mode!"
                    echo ""
                    info_message "Hybrid mode uses Apache with mod_php, not PHP-FPM."
                    info_message "For per-app PHP config in Hybrid mode, use:"
                    green_message "  tbs phpconfig $app_name create"
                    echo ""
                    info_message "Or switch to Thunder mode in .env:"
                    green_message "  STACK_MODE=thunder"
                    echo ""
                    if ! yes_no_prompt "Create pool config anyway (for future Thunder mode use)?"; then
                        return 0
                    fi
                fi
                
                if [[ -f "$pool_conf" ]]; then
                    yellow_message "Pool config already exists for $app_name"
                    if ! yes_no_prompt "Overwrite existing config?"; then
                        return 0
                    fi
                fi
                
                mkdir -p "$pools_dir"
                
                if [[ -f "$pool_template" ]]; then
                    # Replace placeholders in template
                    sed "s/{{APP_NAME}}/$app_name/g" "$pool_template" > "$pool_conf"
                    green_message "Created FPM pool config from template for $app_name"
                else
                    cat > "$pool_conf" <<POOLCONF
; FPM Pool for: $app_name
; Location: sites/php/pools/$app_name.conf
[$app_name]
user = www-data
group = www-data
listen = /var/run/php-fpm-$app_name.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = 20
pm.start_servers = 5
pm.min_spare_servers = 2
pm.max_spare_servers = 10
pm.max_requests = 500

; Security
security.limit_extensions = .php

; PHP Settings (can be overridden by .user.ini)
php_value[memory_limit] = 512M
php_value[max_execution_time] = 300
php_value[upload_max_filesize] = 64M
php_value[post_max_size] = 64M

; Admin Settings (cannot be overridden)
php_admin_flag[log_errors] = on
php_admin_value[error_log] = /var/log/php-fpm/$app_name-error.log
POOLCONF
                    green_message "Created basic FPM pool config for $app_name"
                fi
                
                info_message "Edit with: tbs phpconfig $app_name edit-pool"
                yellow_message "Restart stack to apply: tbs restart"
                ;;
            
            edit-pool)
                if [[ ! -f "$pool_conf" ]]; then
                    yellow_message "Pool config not found. Creating..."
                    tbs phpconfig "$app_name" create-pool
                    # Check again after create attempt
                    if [[ ! -f "$pool_conf" ]]; then
                        info_message "Pool config creation was cancelled."
                        return 0
                    fi
                fi
                open_in_editor "$pool_conf"
                ;;
            
            show-pool)
                if [[ -f "$pool_conf" ]]; then
                    blue_message "⚙️ FPM Pool config for $app_name:"
                    echo ""
                    cat "$pool_conf"
                else
                    info_message "No FPM pool config for $app_name"
                    info_message "Create with: tbs phpconfig $app_name create-pool"
                fi
                ;;
            
            delete-pool)
                if [[ -f "$pool_conf" ]]; then
                    if yes_no_prompt "Delete FPM pool config for $app_name?"; then
                        rm "$pool_conf"
                        green_message "Deleted pool config for $app_name"
                        yellow_message "Restart stack to apply: tbs restart"
                    fi
                else
                    info_message "No pool config exists for $app_name"
                fi
                ;;
            
            *)
                error_message "Unknown action: $action"
                info_message "Run 'tbs phpconfig' for usage"
                ;;
        esac
        ;;

    "")
        interactive_menu
        ;;
    help|--help|-h)
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
            echo "  ssl-localhost Generate default localhost SSL certificates"
            echo "  phpconfig   Manage per-app PHP config:"
            echo "              tbs phpconfig                    - List all apps config status"
            echo "              tbs phpconfig <app> create       - Create .user.ini"
            echo "              tbs phpconfig <app> edit         - Edit .user.ini"
            echo "              tbs phpconfig <app> create-pool  - Create FPM pool (Thunder mode)"
            echo "              tbs phpconfig <app> edit-pool    - Edit FPM pool config"
            echo "  logs        Show logs (usage: tbs logs [service])"
            echo "  status      Show stack status"
            echo "  mail        Open Mailpit"
            echo "  pma         Open phpMyAdmin"
            echo "  redis-cli   Open Redis CLI"
            echo ""
            ;;
        *)
            print_header
            error_message "Unknown command: $1"
            echo "Run 'tbs help' for usage or 'tbs' for the interactive menu."
            ;;
    esac
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

# Run tbs with all arguments
tbs "$@"
