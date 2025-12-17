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

# Check if a container/service is running
is_service_running() {
    local service="$1"
    docker compose ps "$service" --format "{{.State}}" 2>/dev/null | grep -q "running"
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
            elif [[ "$value" =~ ^\047(.*)\047$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            printf -v "$key" '%s' "$value"
            if [[ "$export_vars" == "true" ]]; then
                export "$key"
            fi
        fi
    done < "$env_file"
}

# Detect OS
detect_os_type() {
    case "$(uname -s)" in
        Darwin) echo "mac" ;;
        Linux) echo "linux" ;;
        CYGWIN*|MINGW32*|MSYS*|MINGW*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

OS_TYPE=$(detect_os_type)

get_os_type() {
    echo "$OS_TYPE"
}

# Cross-platform sed in-place editing
sed_i() {
    local expression=$1
    local file=$2
    if [[ "$OS_TYPE" == "mac" ]]; then
        sed -i "" "$expression" "$file"
    else
        sed -i "$expression" "$file"
    fi
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
    if [[ "${ENABLE_SSH:-false}" == "true" ]]; then
        profiles="$profiles --profile ssh"
    fi
    echo "$profiles"
}

# Get all profiles for complete stack operations
get_all_profiles() {
    echo "--profile hybrid --profile thunder --profile development --profile tools --profile ssh"
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
        if ! is_service_running "$WEBSERVER_SERVICE"; then
            error_message "Webserver container is not running. Please start the stack first."
            return 1
        fi
    fi
    
    if [[ "$check_database" == "true" ]]; then
        if ! is_service_running "dbhost"; then
            error_message "Database container is not running. Please start the stack first."
            return 1
        fi
    fi
    
    return 0
}

# ============================================
# App Configuration Helpers
# ============================================

# Generate strong random password (22 chars with safe symbols)
# Excludes problematic characters: # ' " , . ` \ / that break configs
generate_strong_password() {
    local length="${1:-22}"
    local password=""
    
    # Try openssl first (most reliable cross-platform)
    if command_exists openssl; then
        password=$(openssl rand -base64 48 2>/dev/null | tr -dc 'A-Za-z0-9!@$%^&*_+' | head -c "$length")
    fi
    
    # Fallback to /dev/urandom
    if [[ -z "$password" || ${#password} -lt $length ]]; then
        password=$(LC_ALL=C tr -dc 'A-Za-z0-9!@$%^&*_+' < /dev/urandom 2>/dev/null | head -c "$length" || true)
    fi
    
    # Ultimate fallback using $RANDOM (bash built-in)
    if [[ -z "$password" || ${#password} -lt $length ]]; then
        local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@$%^&*_+'
        password=""
        for ((i=0; i<length; i++)); do
            password+="${chars:RANDOM%${#chars}:1}"
        done
    fi
    
    # Ensure password has: uppercase, lowercase, number, special
    local needs_fix=false
    [[ ! "$password" =~ [A-Z] ]] && needs_fix=true
    [[ ! "$password" =~ [a-z] ]] && needs_fix=true
    [[ ! "$password" =~ [0-9] ]] && needs_fix=true
    [[ ! "$password" =~ [!@$%^\&*_+] ]] && needs_fix=true
    
    if [[ "$needs_fix" == "true" ]]; then
        # Add missing character types
        local upper='A' lower='z' number='7' special='!'
        if command_exists openssl; then
            upper=$(openssl rand -base64 4 2>/dev/null | tr -dc 'A-Z' | head -c 1 || echo 'A')
            lower=$(openssl rand -base64 4 2>/dev/null | tr -dc 'a-z' | head -c 1 || echo 'z')
            number=$(openssl rand -base64 4 2>/dev/null | tr -dc '0-9' | head -c 1 || echo '7')
        fi
        special=$(echo '!@$%^&*_+' | fold -w1 2>/dev/null | shuf 2>/dev/null | head -c 1 || echo '!')
        password="${password:0:$((length-4))}${upper}${lower}${number}${special}"
    fi
    
    echo "$password"
}

# Generate unique app_user (primary identifier for app)
# Format: <random> - used as directory, SSH user, and config key
generate_app_user() {
    local sum_cmd="sha256sum"
    command -v sha256sum >/dev/null 2>&1 || sum_cmd="shasum -a 256"
    
    # Ensure variables are set
    local doc_root="${DOCUMENT_ROOT:-./www}"
    local apps_dir_name="${APPLICATIONS_DIR_NAME:-applications}"
    
    local user_id
    local max_attempts=100
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        # Generate random ID using multiple sources for better entropy
        local seed="$(date +%s%N 2>/dev/null || date +%s)${RANDOM}${RANDOM}"
        user_id=$(echo "$seed" | $sum_cmd 2>/dev/null | tr -dc 'a-z' | head -c 12)
        
        # Validate and check uniqueness
        if [[ -n "$user_id" && ${#user_id} -ge 8 && ! -d "$doc_root/$apps_dir_name/$user_id" ]]; then
            echo "$user_id"
            return 0
        fi
        ((attempts++))
    done
    
    # Final fallback with timestamp
    echo "app$(date +%s | tail -c 10)"
}

# Get app config file path (by app_user - primary identifier)
get_app_config_path() {
    local app_user="$1"
    echo "$tbsPath/sites/apps/${app_user}.json"
}

# Find app_user by app_name (searches all configs)
# Returns first matching app_user or empty if not found
find_app_user_by_name() {
    local search_name="$1"
    local apps_dir="$tbsPath/sites/apps"
    
    [[ ! -d "$apps_dir" ]] && return 1
    
    for config_file in "$apps_dir"/*.json; do
        [[ ! -f "$config_file" ]] && continue
        local name=""
        if command_exists jq; then
            name=$(jq -r '.name // empty' "$config_file" 2>/dev/null)
        else
            # Fallback: grep-based extraction
            name=$(grep '"name"' "$config_file" 2>/dev/null | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi
        if [[ "$name" == "$search_name" ]]; then
            basename "$config_file" .json
            return 0
        fi
    done
    return 1
}

# Resolve input to app_user (accepts app_user or app_name)
resolve_app_user() {
    local input="$1"
    local config_file="$tbsPath/sites/apps/${input}.json"
    
    # If config exists with this name, it's already app_user
    if [[ -f "$config_file" ]]; then
        echo "$input"
        return 0
    fi
    
    # Otherwise search by app_name
    local found=$(find_app_user_by_name "$input")
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi
    
    return 1
}

# Initialize app config with defaults
# $1 = app_user (primary identifier, used as filename)
# $2 = app_name (display label, optional - defaults to app_user)
init_app_config() {
    local app_user="$1"
    local app_name="${2:-$app_user}"
    local config_file=$(get_app_config_path "$app_user")
    
    if [[ ! -f "$config_file" ]]; then
        mkdir -p "$(dirname "$config_file")"
        cat > "$config_file" <<EOF
{
    "app_user": "$app_user",
    "name": "$app_name",
    "domains": ["${app_user}.localhost"],
    "primary_domain": "${app_user}.localhost",
    "webroot": "public_html",
    "structure": {
        "webroot": "public_html",
        "logs": "logs",
        "tmp": "tmp",
        "ssh": ".ssh",
        "backup": "backup",
        "data": "data"
    },
    "varnish": true,
    "database": {
        "name": "",
        "user": "",
        "created": false
    },
    "ssh": {
        "enabled": false,
        "username": "",
        "password": "",
        "port": 2244,
        "uid": 0,
        "gid": 0
    },
    "logs": {
        "enabled": false,
        "path": "logs"
    },
    "supervisor": {
        "enabled": false,
        "programs": []
    },
    "cron": {
        "enabled": false,
        "jobs": []
    },
    "permissions": {
        "owner": "www-data",
        "group": "www-data"
    },
    "created_at": "$(date -Iseconds)"
}
EOF
    fi
    echo "$config_file"
}

# Read app config value using jq or grep fallback
get_app_config() {
    local app_user="$1"
    local key="$2"
    local config_file=$(get_app_config_path "$app_user")
    
    if [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    if command_exists jq; then
        jq -r ".$key // empty" "$config_file" 2>/dev/null
    else
        # Fallback: simple grep for basic keys
        grep "\"$key\":" "$config_file" | head -1 | sed 's/.*: *"\?\([^",}]*\)"\?.*/\1/'
    fi
}

# Set app config value
set_app_config() {
    local app_user="$1"
    local key="$2"
    local value="$3"
    local config_file=$(get_app_config_path "$app_user")
    
    if [[ ! -f "$config_file" ]]; then
        init_app_config "$app_user"
    fi
    
    if command_exists jq; then
        local tmp_file=$(mktemp)
        if jq ".$key = $value" "$config_file" > "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" "$config_file"
        else
            rm -f "$tmp_file"
            error_message "Failed to update config key: $key"
            return 1
        fi
    else
        error_message "jq is required for modifying app config. Install with: brew install jq"
        return 1
    fi
}

# Execute MySQL command through webserver container
# Usage: execute_mysql_command [options] [query]
execute_mysql_command() {
    # Use -T to disable TTY allocation (required for pipes/scripts)
    # Pass arguments directly to mysql client to avoid shell quoting issues
    docker compose exec -T "$WEBSERVER_SERVICE" mysql -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" -h dbhost "$@" 2>/dev/null
}

# Execute MySQL dump through webserver container
execute_mysqldump() {
    local database="$1"
    local output_file="$2"
    
    docker compose exec -T "$WEBSERVER_SERVICE" mysqldump -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" -h dbhost --databases "$database" >"$output_file" 2>/dev/null
}

# ============================================
# Database Helpers
# ============================================

# Create a database
_db_create() {
    local db_name="$1"
    [[ -z "$db_name" ]] && { error_message "Database name required"; return 1; }
    
    if execute_mysql_command -e "CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
        green_message "Created database: $db_name"
        return 0
    else
        error_message "Failed to create database: $db_name"
        return 1
    fi
}

# Drop a database
_db_drop() {
    local db_name="$1"
    [[ -z "$db_name" ]] && { error_message "Database name required"; return 1; }
    
    if execute_mysql_command -e "DROP DATABASE IF EXISTS \`$db_name\`;"; then
        green_message "Dropped database: $db_name"
        return 0
    else
        error_message "Failed to drop database: $db_name"
        return 1
    fi
}

# Create a database user and grant permissions
_db_create_user() {
    local user="$1"
    local pass="$2"
    local db="$3"
    
    [[ -z "$user" || -z "$pass" || -z "$db" ]] && { error_message "User, password, and database required"; return 1; }
    
    if execute_mysql_command -e "CREATE USER IF NOT EXISTS '$user'@'%' IDENTIFIED BY '$pass'; GRANT ALL ON \`$db\`.* TO '$user'@'%'; FLUSH PRIVILEGES;"; then
        return 0
    else
        error_message "Failed to create user: $user"
        return 1
    fi
}

# Drop a database user
_db_drop_user() {
    local user="$1"
    [[ -z "$user" ]] && { error_message "User required"; return 1; }
    
    execute_mysql_command -e "DROP USER IF EXISTS '$user'@'%'; FLUSH PRIVILEGES;"
}

# Import SQL file
_db_import() {
    local db_name="$1"
    local sql_file="$2"
    
    [[ -z "$db_name" ]] && { error_message "Database name required"; return 1; }
    [[ ! -f "$sql_file" ]] && { error_message "File not found: $sql_file"; return 1; }
    
    info_message "Importing $sql_file into $db_name..."
    
    if [[ "$sql_file" == *.gz ]]; then
        if gunzip -c "$sql_file" | execute_mysql_command "$db_name"; then
            green_message "Imported successfully!"
            return 0
        fi
    else
        if execute_mysql_command "$db_name" < "$sql_file"; then
            green_message "Imported successfully!"
            return 0
        fi
    fi
    
    error_message "Import failed"
    return 1
}

# Export database
_db_export() {
    local db_name="$1"
    local output_file="$2"
    
    [[ -z "$db_name" ]] && { error_message "Database name required"; return 1; }
    [[ -z "$output_file" ]] && { error_message "Output file required"; return 1; }
    
    if execute_mysqldump "$db_name" "$output_file"; then
        if [[ -s "$output_file" ]]; then
            green_message "Exported to: $output_file"
            return 0
        else
            rm -f "$output_file"
            error_message "Export failed (empty file)"
            return 1
        fi
    else
        rm -f "$output_file"
        error_message "Export failed"
        return 1
    fi
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
    reqConfig=("INSTALLATION_TYPE" "APP_ENV" "STACK_MODE" "PHPVERSION" "DATABASE" "ENABLE_SSH")

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

    # Function to prompt user to enable SSH
    choose_enable_ssh() {
        blue_message "Enable SSH Service?"
        echo "   1. No (Default)"
        echo "   2. Yes"
        
        local default_index=1
        if [[ "$ENABLE_SSH" == "true" ]]; then
            default_index=2
        fi

        while true; do
            echo -ne "Select [1-2] (${YELLOW}Default: $default_index${NC}): "
            read ssh_index
            ssh_index=${ssh_index:-$default_index}

            if [[ "$ssh_index" == "1" ]]; then
                ENABLE_SSH="false"
                break
            elif [[ "$ssh_index" == "2" ]]; then
                ENABLE_SSH="true"
                break
            else
                error_message "Invalid selection. Please enter 1 or 2."
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
            elif [[ "$key" == "ENABLE_SSH" ]]; then
                choose_enable_ssh
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
    info_message "  • Database: localhost:${HOST_MACHINE_MYSQL_PORT:-3306} (Host: dbhost)"
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
        echo "   7) App Manager - Create, Delete, Database, SSH, Domains"
        echo "   8) Create Project (Laravel/WordPress/Symfony)"
        echo "   9) Open App Code"
        echo "   10) App Configuration (varnish, webroot, perms)"

        echo -e "\n${BLUE}💾 Database${NC}"
        echo "   11) Database Manager (list/create/import/export)"

        echo -e "\n${BLUE}⚙️ Configuration & Tools${NC}"
        echo "   12) Configure Environment"
        echo "   13) System Info"
        echo "   14) Backup/Restore"
        echo "   15) SSL Certificates"
        
        echo -e "\n${BLUE}🔧 Shell & Tools${NC}"
        echo "   16) Container Shell"
        echo "   17) Mailpit | 18) phpMyAdmin | 19) Redis CLI"

        echo -e "\n   ${RED}0) Exit${NC}"
        
        echo ""
        read -p "Choice [0-19]: " choice

        local wait_needed=true
        case $choice in
            1) tbs start ;; 2) tbs stop ;; 3) tbs restart ;; 4) tbs build ;; 5) tbs status ;; 6) tbs logs ;;
            7) tbs app ;;
            8) echo ""; read -p "Type [laravel/wordpress/symfony/blank]: " t; read -p "App name: " n; tbs create "$t" "$n" ;;
            9) tbs app code ;;
            10) tbs app config ;;
            11) echo ""; echo "1) List  2) Create  3) Import  4) Export"; read -p "Action: " a
                case "$a" in 1) tbs db list ;; 2) read -p "Name: " n; tbs db create "$n" ;;
                    3) read -p "DB: " n; read -p "File: " f; tbs db import "$n" "$f" ;;
                    4) read -p "DB: " n; tbs db export "$n" ;; esac ;;
            12) tbs config ;; 13) tbs info ;;
            14) echo ""; echo "1) Backup  2) Restore"; read -p "Action: " a; [[ "$a" == "1" ]] && tbs backup || tbs restore ;;
            15) tbs app ssl ;;
            16) tbs shell ;; 17) tbs mail ;; 18) tbs pma ;; 19) tbs redis-cli ;;
            0) echo "Bye!"; exit 0 ;;
            *) red_message "Invalid"; sleep 1; wait_needed=false ;;
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

    # Auto-start stack if needed
    if [[ "$1" =~ ^(start|app|backup|restore|ssl|mail|pma|redis-cli|db|create|shell)$ ]] && ! is_service_running "$WEBSERVER_SERVICE"; then
        yellow_message "Stack not running. Starting..."
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

    # ============================================
    # Unified App Command - tbs app <action> [args]
    # All app-related operations in one place
    # ============================================
    app)
        local app_action="${2:-}"
        local app_arg1="${3:-}"
        local app_arg2="${4:-}"
        local app_arg3="${5:-}"
        
        # ==========================================
        # Helper Functions
        # ==========================================
        
        # List all apps
        _app_list() {
            local apps_dir="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME"
            APP_LIST=()
            
            [[ ! -d "$apps_dir" ]] && { yellow_message "No apps found."; return 1; }
            
            echo ""
            blue_message "╔══════════════════════════════════════════════════════════════╗"
            blue_message "║                      📦 Applications                         ║"
            blue_message "╠══════════════════════════════════════════════════════════════╣"
            
            local i=1
            for app_dir in "$apps_dir"/*/; do
                [[ ! -d "$app_dir" ]] && continue
                local u=$(basename "$app_dir")
                local n=$(get_app_config "$u" "name"); [[ -z "$n" || "$n" == "null" ]] && n="$u"
                local d=$(get_app_config "$u" "primary_domain")
                local icons=""
                [[ "$(get_app_config "$u" "database.created")" == "true" ]] && icons+="💾"
                [[ "$(get_app_config "$u" "ssh.enabled")" == "true" ]] && icons+="🔑"
                [[ "$(get_app_config "$u" "varnish")" == "false" ]] && icons+="⚡"
                
                printf "║  ${CYAN}%2d${NC}) %-18s ${GREEN}%-22s${NC} %s\n" "$i" "$u" "${d:-N/A}" "$icons"
                APP_LIST+=("$u")
                ((i++))
            done
            
            [[ ${#APP_LIST[@]} -eq 0 ]] && echo "║  ${YELLOW}No apps. Create: tbs app add <name>${NC}"
            blue_message "╚══════════════════════════════════════════════════════════════╝"
            echo ""
        }
        
        # Select app interactively
        _app_select() {
            _app_list || return 1
            [[ ${#APP_LIST[@]} -eq 0 ]] && return 1
            
            local sel
            read -p "Select [1-${#APP_LIST[@]}] (0=cancel): " sel
            [[ "$sel" == "0" ]] && return 1
            [[ "$sel" =~ ^[0-9]+$ && "$sel" -ge 1 && "$sel" -le "${#APP_LIST[@]}" ]] || { error_message "Invalid"; return 1; }
            SELECTED_APP="${APP_LIST[$((sel-1))]}"
        }
        
        # Get or select app
        _app_get() {
            local input="$1"
            if [[ -n "$input" ]]; then
                SELECTED_APP=$(resolve_app_user "$input")
                [[ -z "$SELECTED_APP" ]] && { error_message "App '$input' not found."; return 1; }
                return 0
            else
                _app_select || return 1
            fi
        }
        
        # App info header
        _app_header() {
            local u="$1" title="$2"
            local n=$(get_app_config "$u" "name"); [[ -z "$n" || "$n" == "null" ]] && n="$u"
            local d=$(get_app_config "$u" "primary_domain")
            echo ""
            blue_message "═══════════════════════════════════════════════════════════════"
            printf "  $title: ${CYAN}$n${NC} (${GREEN}$u${NC})\n"
            [[ -n "$d" && "$d" != "null" ]] && printf "  Domain: ${GREEN}$d${NC}\n"
            blue_message "═══════════════════════════════════════════════════════════════"
        }
        
        # Create database for app
        _app_db_create() {
            local app_user="$1"
            
            is_service_running "dbhost" || { error_message "MySQL not running. Run: tbs start"; return 1; }
            
            local db_name="${app_user//-/_}"
            read -p "Database name (default: $db_name): " input_db
            db_name="${input_db:-$db_name}"
            
            local db_user="$db_name"
            local suggested_pass=$(generate_strong_password 16)
            echo -e "  Auto password: ${CYAN}$suggested_pass${NC}"
            read -p "Password (Enter=auto): " db_pass
            db_pass="${db_pass:-$suggested_pass}"
            
            _db_create "$db_name" && _db_create_user "$db_user" "$db_pass" "$db_name"
            
            command_exists jq && {
                local cfg=$(get_app_config_path "$app_user")
                local tmp=$(mktemp)
                if jq '.database={"name":"'"$db_name"'","user":"'"$db_user"'","password":"'"$db_pass"'","host":"dbhost","created":true}' "$cfg" > "$tmp" 2>/dev/null; then
                    mv "$tmp" "$cfg"
                else
                    rm -f "$tmp"
                fi
            }
            
            echo ""
            green_message "✅ Database Created!"
            echo "  Database: $db_name"
            echo "  Username: $db_user"  
            echo "  Password: $db_pass"
            echo "  Host: dbhost (container) / localhost:${HOST_MACHINE_MYSQL_PORT:-3306} (host)"
            echo ""
        }
        
        # ==========================================
        # Main Command Router  
        # ==========================================
        case "$app_action" in
        
        # tbs app / tbs app list - List & Select
        ""|list|ls)
            _app_select || return 0
            # Show actions menu
            while true; do
                _app_header "$SELECTED_APP" "📦 App"
                echo "  1) 📂 Open in VS Code      6) 🐘 PHP Config"
                echo "  2) 🌐 Open in Browser      7) 🔒 SSL Certificates"
                echo "  3) 💾 Database             8) ⚙️  Settings"
                echo "  4) 🌍 Domains              9) 🗑️  Delete"
                echo "  5) 🔑 SSH/SFTP             0) ↩️  Back"
                echo ""
                read -p "Select [0-9]: " choice
                case "$choice" in
                    1) code "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$SELECTED_APP" ;;
                    2) local dom=$(get_app_config "$SELECTED_APP" "primary_domain")
                       open_browser "https://${dom:-$SELECTED_APP.localhost}" ;;
                    3) tbs app db "$SELECTED_APP" ;;
                    4) tbs app domain "$SELECTED_APP" ;;
                    5) tbs app ssh "$SELECTED_APP" ;;
                    6) tbs app php "$SELECTED_APP" ;;
                    7) tbs app ssl "$SELECTED_APP" ;;
                    8) tbs app config "$SELECTED_APP" ;;
                    9) tbs app rm "$SELECTED_APP"; return 0 ;;
                    0|"") return 0 ;;
                esac
            done
            ;;
        
        # tbs app add <name> [domain] - Create new app
        add|create|new)
            local name="$app_arg1" domain="$app_arg2"
            
            [[ -z "$name" ]] && { read -p "App name: " name; [[ -z "$name" ]] && { error_message "Name required"; return 1; }; }
            [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]] && { error_message "Invalid name (use a-z, 0-9, -, _)"; return 1; }
            
            # Generate app_user
            local app_user=$(generate_app_user)
            local ssh_pass=$(generate_strong_password 22)
            local uid_hash=$(echo "$app_user$(date +%s)" | md5sum | tr -dc '0-9' | head -c 4)
            local ssh_uid=$((2000 + ${uid_hash:-1}))
            
            [[ -z "$domain" ]] && domain="${app_user}.localhost"
            
            info_message "Creating: $name → $app_user"
            
            # Create vhost
            local vhost_file="${VHOSTS_DIR}/${domain}.conf"
            cat >"$vhost_file" <<EOF
<VirtualHost *:80>
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot $APACHE_DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_user/public_html
    Define APP_NAME $app_user
    Include /etc/apache2/sites-enabled/partials/app-common.inc
</VirtualHost>
<VirtualHost *:443>
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot $APACHE_DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_user/public_html
    Define APP_NAME $app_user
    Include /etc/apache2/sites-enabled/partials/app-common.inc
    SSLEngine on
    SSLCertificateFile /etc/apache2/ssl-sites/cert.pem
    SSLCertificateKeyFile /etc/apache2/ssl-sites/cert-key.pem
</VirtualHost>
EOF

            # Nginx config
            local nginx_file="${NGINX_CONF_DIR}/${domain}.conf"
            cat >"$nginx_file" <<EOF
server {
    listen 80;
    server_name $domain www.$domain;
    include /etc/nginx/includes/common.conf;
    include /etc/nginx/partials/varnish-proxy.conf;
}
server {
    listen 443 ssl;
    server_name $domain www.$domain;
    ssl_certificate /etc/nginx/ssl-sites/cert.pem;
    ssl_certificate_key /etc/nginx/ssl-sites/cert-key.pem;
    include /etc/nginx/includes/common.conf;
    include /etc/nginx/partials/varnish-proxy.conf;
}
EOF
            [[ "$(get_webserver_service)" == "webserver-fpm" ]] && cat >>"$nginx_file" <<EOF
server {
    listen 8080;
    server_name $domain www.$domain;
    root $APACHE_DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_user/public_html;
    index index.php index.html;
    include /etc/nginx/partials/php-fpm.conf;
}
EOF

            # Create directory structure
            local app_root="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_user"
            mkdir -p "$app_root"/{public_html,logs,tmp,.ssh,backup,data}
            chmod 700 "$app_root/.ssh"
            
            # Create index.php
            cat > "$app_root/public_html/index.php" <<EOF
<!DOCTYPE html><html><head><title>$domain</title></head>
<body><h1>✅ $domain is ready!</h1><p>App: $app_user</p></body></html>
EOF

            # Generate SSL
            generate_ssl_certificates "$domain" "$vhost_file" "$nginx_file" 2>/dev/null || true
            
            # Init config
            local config_file=$(init_app_config "$app_user" "$name")
            
            # SSH user config
            mkdir -p "$tbsPath/sites/ssh"
            cat > "$tbsPath/sites/ssh/${app_user}.json" <<EOF
{"app_user":"$app_user","username":"$app_user","password":"$ssh_pass","enabled":true,"uid":$ssh_uid,"gid":$ssh_uid}
EOF
            
            # Update app config
            command_exists jq && {
                local tmp=$(mktemp)
                jq ".ssh={\"enabled\":true,\"username\":\"$app_user\",\"password\":\"$ssh_pass\",\"port\":${HOST_MACHINE_SSH_PORT:-2244},\"uid\":$ssh_uid,\"gid\":$ssh_uid}" "$config_file" > "$tmp" && mv "$tmp" "$config_file"
            }
            
            # Set permissions in container
            is_service_running "$WEBSERVER_SERVICE" && docker compose exec -T "$WEBSERVER_SERVICE" bash -c "
                groupadd -g $ssh_uid $app_user 2>/dev/null || true
                useradd -u $ssh_uid -g $ssh_uid -M -d /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user $app_user 2>/dev/null || true
                chown -R $ssh_uid:$ssh_uid /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user
                find /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user -type d -exec chmod 750 {} \;
                find /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user -type f -exec chmod 640 {} \;
            " 2>/dev/null
            
            reload_webservers
            
            echo ""
            green_message "✅ App Created!"
            blue_message "═══════════════════════════════════════════════════════════════"
            echo "  App User:  $app_user"
            echo "  Domain:    https://$domain"
            echo "  SSH User:  $app_user"
            echo "  SSH Pass:  $ssh_pass"
            echo "  SSH Port:  ${HOST_MACHINE_SSH_PORT:-2244}"
            blue_message "═══════════════════════════════════════════════════════════════"
            echo ""
            
            # Ask for database
            read -p "Create database? (Y/n): " create_db
            [[ ! "$create_db" =~ ^[Nn]$ ]] && _app_db_create "$app_user"
            
            open_browser "https://$domain"
            ;;
        
        # tbs app rm [app] - Delete app
        rm|delete|remove)
            _app_get "$app_arg1" || return 1
            local app_user="$SELECTED_APP"
            local app_name=$(get_app_config "$app_user" "name"); [[ -z "$app_name" || "$app_name" == "null" ]] && app_name="$app_user"
            local domain=$(get_app_config "$app_user" "primary_domain")
            
            _app_header "$app_user" "🗑️  Delete App"
            red_message "⚠️  This cannot be undone!"
            echo ""
            echo -e "Type ${CYAN}$app_user${NC} to confirm:"
            read -p "Confirm: " confirm
            [[ "$confirm" != "$app_user" ]] && { error_message "Cancelled."; return 1; }
            
            # Ask about database & files
            local del_db="n" del_files="n"
            local db_name=$(get_app_config "$app_user" "database.name")
            [[ -n "$db_name" && "$db_name" != "null" ]] && read -p "Delete database '$db_name'? (y/N): " del_db
            [[ -d "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_user" ]] && read -p "Delete files? (y/N): " del_files
            
            info_message "Deleting..."
            
            # Delete database
            [[ "$del_db" =~ ^[Yy]$ ]] && is_service_running "dbhost" && {
                local db_user=$(get_app_config "$app_user" "database.user")
                _db_drop "$db_name"
                [[ -n "$db_user" && "$db_user" != "null" ]] && _db_drop_user "$db_user"
                green_message "Database deleted"
            }
            
            # Delete configs
            rm -f "${VHOSTS_DIR}/${domain}.conf" "${NGINX_CONF_DIR}/${domain}.conf"
            rm -f "${SSL_DIR}/${domain}-key.pem" "${SSL_DIR}/${domain}-cert.pem"
            rm -f "$tbsPath/sites/ssh/${app_user}.json"
            rm -f "$tbsPath/sites/apps/${app_user}.json"
            rm -f "$tbsPath/sites/cron/${app_user}_cron"
            rm -f "$tbsPath/sites/supervisor/${app_user}_"*.conf 2>/dev/null
            rm -f "$tbsPath/sites/php/pools/${app_user}.conf"
            
            # Delete files
            [[ "$del_files" =~ ^[Yy]$ ]] && rm -rf "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_user"
            
            reload_webservers
            green_message "✅ App '$app_name' deleted!"
            ;;
        
        # tbs app db [app] - Database management
        db|database)
            _app_get "$app_arg1" || return 1
            local app_user="$SELECTED_APP"
            
            is_service_running "dbhost" || { error_message "MySQL not running"; return 1; }
            
            while true; do
                local db=$(get_app_config "$app_user" "database.name")
                local db_user=$(get_app_config "$app_user" "database.user")
                local db_created=$(get_app_config "$app_user" "database.created")
                
                _app_header "$app_user" "💾 Database"
                [[ "$db_created" == "true" ]] && echo "  Current: $db (user: $db_user)"
                echo ""
                echo "  1) 📋 Show Credentials    4) 📥 Import"
                echo "  2) ➕ Create Database     5) 📤 Export"
                echo "  3) 🔄 Reset Password      6) 🗑️  Delete"
                echo "  0) ↩️  Back"
                echo ""
                read -p "Select [0-6]: " choice
                
                case "$choice" in
                    1) [[ "$db_created" != "true" ]] && { yellow_message "No database"; } || {
                       local cfg=$(get_app_config_path "$app_user")
                       echo ""
                       echo "  Database: $(jq -r '.database.name' "$cfg")"
                       echo "  Username: $(jq -r '.database.user' "$cfg")"
                       echo "  Password: $(jq -r '.database.password' "$cfg")"
                       echo "  Host: dbhost / localhost:${HOST_MACHINE_MYSQL_PORT:-3306}"
                       }
                       ;;
                    2) _app_db_create "$app_user" ;;
                    3) [[ "$db_created" != "true" ]] && { error_message "No database"; } || {
                       local new_pass=$(generate_strong_password 16)
                       echo -e "  Auto: ${CYAN}$new_pass${NC}"
                       read -p "New password (Enter=auto): " input_pass
                       new_pass="${input_pass:-$new_pass}"
                       execute_mysql_command -e "ALTER USER '$db_user'@'%' IDENTIFIED BY '$new_pass'; FLUSH PRIVILEGES;"
                       command_exists jq && { local cfg=$(get_app_config_path "$app_user"); local tmp=$(mktemp); jq ".database.password=\"$new_pass\"" "$cfg" > "$tmp" && mv "$tmp" "$cfg"; }
                       green_message "✅ Password: $new_pass"
                       }
                       ;;
                    4) [[ "$db_created" != "true" ]] && { error_message "No database"; } || {
                       read -p "SQL file: " sql_file
                       if [[ ! -f "$sql_file" ]]; then error_message "File not found"; else
                           [[ "$sql_file" == *.gz ]] && gunzip -c "$sql_file" | execute_mysql_command "$db" || execute_mysql_command "$db" < "$sql_file"
                           green_message "✅ Imported!"
                       fi
                       }
                       ;;
                    5) [[ "$db_created" != "true" ]] && { error_message "No database"; } || {
                       local out="$tbsPath/data/backup/${db}_$(date +%Y%m%d_%H%M%S).sql"
                       _db_export "$db" "$out"
                       }
                       ;;
                    6) [[ "$db_created" != "true" ]] && { error_message "No database"; } || {
                       read -p "Type '$db' to delete: " confirm
                       if [[ "$confirm" != "$db" ]]; then info_message "Cancelled"; else
                           _db_drop "$db"
                           [[ -n "$db_user" ]] && _db_drop_user "$db_user"
                           command_exists jq && { local cfg=$(get_app_config_path "$app_user"); local tmp=$(mktemp); jq ".database={\"name\":\"\",\"user\":\"\",\"password\":\"\",\"created\":false}" "$cfg" > "$tmp" && mv "$tmp" "$cfg"; }
                           green_message "✅ Deleted!"
                       fi
                       }
                       ;;
                    0) return 0 ;;
                    *) error_message "Invalid option" ;;
                esac
                echo ""
                read -p "Press Enter to continue..."
            done
            ;;
        
        # tbs app ssh [app] - SSH management
        ssh|sftp)
            _app_get "$app_arg1" || return 1
            local app_user="$SELECTED_APP"
            local ssh_file="$tbsPath/sites/ssh/${app_user}.json"
            
            while true; do
                local ssh_enabled=$(get_app_config "$app_user" "ssh.enabled")
                _app_header "$app_user" "🔑 SSH/SFTP"
                [[ "$ssh_enabled" == "true" ]] && echo "  Status: ${GREEN}Enabled${NC}" || echo "  Status: ${RED}Disabled${NC}"
                echo ""
                echo "  1) 📋 Show Credentials    3) 🔄 Reset Password"
                echo "  2) ✅ Enable SSH          4) ❌ Disable SSH"
                echo "  0) ↩️  Back"
                echo ""
                read -p "Select [0-4]: " choice
                
                case "$choice" in
                    1) [[ "$ssh_enabled" != "true" ]] && { yellow_message "SSH not enabled"; } || {
                       command_exists jq && {
                           local cfg=$(get_app_config_path "$app_user")
                           echo ""
                           echo "  Host: localhost"
                           echo "  Port: $(jq -r '.ssh.port' "$cfg")"
                           echo "  User: $(jq -r '.ssh.username' "$cfg")"
                           echo "  Pass: $(jq -r '.ssh.password' "$cfg")"
                       }
                       }
                       ;;
                    2) local pass=$(generate_strong_password 22)
                       local uid=$(get_app_config "$app_user" "ssh.uid")
                       [[ -z "$uid" || "$uid" == "null" ]] && { local h=$(echo "$app_user$(date +%s)" | md5sum | tr -dc '0-9' | head -c 4); uid=$((2000 + ${h:-1})); }
                       mkdir -p "$tbsPath/sites/ssh"
                       echo "{\"app_user\":\"$app_user\",\"username\":\"$app_user\",\"password\":\"$pass\",\"enabled\":true,\"uid\":$uid,\"gid\":$uid}" > "$ssh_file"
                       command_exists jq && { local cfg=$(get_app_config_path "$app_user"); local tmp=$(mktemp); jq ".ssh={\"enabled\":true,\"username\":\"$app_user\",\"password\":\"$pass\",\"port\":${HOST_MACHINE_SSH_PORT:-2244},\"uid\":$uid,\"gid\":$uid}" "$cfg" > "$tmp" && mv "$tmp" "$cfg"; }
                       green_message "✅ SSH Enabled! Pass: $pass"
                       ;;
                    3) local pass=$(generate_strong_password 22)
                       command_exists jq && [[ -f "$ssh_file" ]] && { local tmp=$(mktemp); jq ".password=\"$pass\"|.enabled=true" "$ssh_file" > "$tmp" && mv "$tmp" "$ssh_file"; }
                       command_exists jq && { local cfg=$(get_app_config_path "$app_user"); local tmp=$(mktemp); jq ".ssh.password=\"$pass\"|.ssh.enabled=true" "$cfg" > "$tmp" && mv "$tmp" "$cfg"; }
                       green_message "✅ New password: $pass"
                       ;;
                    4) command_exists jq && [[ -f "$ssh_file" ]] && { local tmp=$(mktemp); jq ".enabled=false" "$ssh_file" > "$tmp" && mv "$tmp" "$ssh_file"; }
                       set_app_config "$app_user" "ssh.enabled" "false"
                       yellow_message "SSH Disabled"
                       ;;
                    0) return 0 ;;
                    *) error_message "Invalid option" ;;
                esac
                echo ""
                read -p "Press Enter to continue..."
            done
            ;;
        
        # tbs app domain [app] - Domain management
        domain|domains)
            _app_get "$app_arg1" || return 1
            local app_user="$SELECTED_APP"
            
            while true; do
                _app_header "$app_user" "🌍 Domains"
                echo "  Current domains:"
                command_exists jq && jq -r '.domains[]? // empty' "$(get_app_config_path "$app_user")" 2>/dev/null | while read d; do
                    local p=$(get_app_config "$app_user" "primary_domain")
                    [[ "$d" == "$p" ]] && echo "    • $d (primary)" || echo "    • $d"
                done
                echo ""
                echo "  1) ➕ Add Domain"
                echo "  2) ➖ Remove Domain"
                echo "  0) ↩️  Back"
                echo ""
                read -p "Select [0-2]: " choice
                
                case "$choice" in
                    1) read -p "New domain: " new_dom
                       if [[ -n "$new_dom" ]]; then
                           local primary=$(get_app_config "$app_user" "primary_domain")
                           local src_vhost="${VHOSTS_DIR}/${primary}.conf"
                           [[ -f "$src_vhost" ]] && sed "s/$primary/$new_dom/g" "$src_vhost" > "${VHOSTS_DIR}/${new_dom}.conf"
                           local src_nginx="${NGINX_CONF_DIR}/${primary}.conf"
                           [[ -f "$src_nginx" ]] && sed "s/$primary/$new_dom/g" "$src_nginx" > "${NGINX_CONF_DIR}/${new_dom}.conf"
                           command_exists jq && { local cfg=$(get_app_config_path "$app_user"); local tmp=$(mktemp); jq ".domains+=[\"$new_dom\"]" "$cfg" > "$tmp" && mv "$tmp" "$cfg"; }
                           generate_ssl_certificates "$new_dom" "${VHOSTS_DIR}/${new_dom}.conf" "${NGINX_CONF_DIR}/${new_dom}.conf" 2>/dev/null || true
                           reload_webservers
                           green_message "✅ Domain added: $new_dom"
                       fi
                       ;;
                    2) read -p "Domain to remove: " rem_dom
                       local primary=$(get_app_config "$app_user" "primary_domain")
                       if [[ "$rem_dom" == "$primary" ]]; then error_message "Cannot remove primary domain"; else
                           rm -f "${VHOSTS_DIR}/${rem_dom}.conf" "${NGINX_CONF_DIR}/${rem_dom}.conf"
                           command_exists jq && { local cfg=$(get_app_config_path "$app_user"); local tmp=$(mktemp); jq ".domains-=[\"$rem_dom\"]" "$cfg" > "$tmp" && mv "$tmp" "$cfg"; }
                           reload_webservers
                           green_message "✅ Domain removed"
                       fi
                       ;;
                    0) return 0 ;;
                    *) error_message "Invalid option" ;;
                esac
                echo ""
                read -p "Press Enter to continue..."
            done
            ;;
        
        # tbs app ssl [app] - SSL certificate management
        ssl|certificate|certs)
            _app_get "$app_arg1" || return 1
            local app_user="$SELECTED_APP"
            local ssl_dir="$tbsPath/sites/ssl"
            
            while true; do
                _app_header "$app_user" "🔒 SSL Certificates"
                
                # Get all domains
                local domains=()
                if command_exists jq; then
                    mapfile -t domains < <(jq -r '.domains[]? // empty' "$(get_app_config_path "$app_user")" 2>/dev/null)
                fi
                [[ ${#domains[@]} -eq 0 ]] && domains=("$(get_app_config "$app_user" "primary_domain")")
                
                echo "  App Domains:"
                local i=1
                for d in "${domains[@]}"; do
                    [[ -z "$d" || "$d" == "null" ]] && continue
                    local cert="$ssl_dir/${d}-cert.pem"
                    [[ -f "$cert" ]] && echo "    $i) $d ${GREEN}✓${NC}" || echo "    $i) $d ${YELLOW}✗${NC}"
                    ((i++))
                done
                echo ""
                echo "  1) 🔐 Generate SSL for ALL domains"
                echo "  2) 🔐 Generate SSL for specific domain"
                echo "  3) 🔍 Check SSL status"
                echo "  0) ↩️  Back"
                echo ""
                read -p "Select [0-3]: " choice
                
                case "$choice" in
                    1) # Generate for all domains
                       echo ""
                       for d in "${domains[@]}"; do
                           [[ -z "$d" || "$d" == "null" ]] && continue
                           info_message "Generating SSL for: $d"
                           local vf="${VHOSTS_DIR}/${d}.conf"
                           local nf="${NGINX_CONF_DIR}/${d}.conf"
                           generate_ssl_certificates "$d" "$vf" "$nf" 2>/dev/null && green_message "  ✅ $d" || yellow_message "  ⚠️  $d (may already exist)"
                       done
                       reload_webservers
                       green_message "✅ SSL generation complete!"
                       ;;
                    2) # Generate for specific domain
                       echo "  Enter domain number or name:"
                       read -p "  Domain: " sel_dom
                       # Check if its a number
                       if [[ "$sel_dom" =~ ^[0-9]+$ ]] && [[ $sel_dom -le ${#domains[@]} ]] && [[ $sel_dom -gt 0 ]]; then
                           sel_dom="${domains[$((sel_dom-1))]}"
                       fi
                       if [[ -n "$sel_dom" ]]; then
                           # Verify domain belongs to this app
                           local found=false
                           for d in "${domains[@]}"; do [[ "$d" == "$sel_dom" ]] && found=true && break; done
                           if [[ "$found" != "true" ]]; then error_message "Domain not found in this app"; else
                               local vf="${VHOSTS_DIR}/${sel_dom}.conf"
                               local nf="${NGINX_CONF_DIR}/${sel_dom}.conf"
                               generate_ssl_certificates "$sel_dom" "$vf" "$nf" && reload_webservers && green_message "✅ SSL generated for: $sel_dom" || error_message "Failed to generate SSL"
                           fi
                       fi
                       ;;
                    3) # Check SSL status
                       echo ""
                       for d in "${domains[@]}"; do
                           [[ -z "$d" || "$d" == "null" ]] && continue
                           local cert="$ssl_dir/${d}-cert.pem"
                           if [[ -f "$cert" ]]; then
                               local expiry=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
                               echo "  $d: ${GREEN}Valid${NC} (expires: $expiry)"
                           else
                               echo "  $d: ${RED}No certificate${NC}"
                           fi
                       done
                       ;;
                    0) return 0 ;;
                    *) error_message "Invalid option" ;;
                esac
                echo ""
                read -p "Press Enter to continue..."
            done
            ;;
        
        # tbs app php [app] - PHP config
        php|phpconfig)
            _app_get "$app_arg1" || return 1
            local app_user="$SELECTED_APP"
            local app_root="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_user"
            local user_ini="$app_root/public_html/.user.ini"
            local pool_conf="$tbsPath/sites/php/pools/${app_user}.conf"
            
            while true; do
                _app_header "$app_user" "🐘 PHP Config"
                [[ -f "$user_ini" ]] && echo "  .user.ini: ${GREEN}exists${NC}" || echo "  .user.ini: ${YELLOW}not set${NC}"
                [[ -f "$pool_conf" ]] && echo "  FPM pool: ${GREEN}exists${NC}" || echo "  FPM pool: ${YELLOW}not set${NC}"
                echo ""
                echo "  1) 📄 Create .user.ini     4) 📝 Edit .user.ini"
                echo "  2) ⚙️  Create FPM pool      5) 📝 Edit FPM pool"
                echo "  3) 🗑️  Delete configs       6) 📋 Show FPM pool"
                echo "  0) ↩️  Back"
                echo ""
                read -p "Select [0-6]: " choice
                
                case "$choice" in
                    1) cat > "$user_ini" <<'INI'
memory_limit = 512M
max_execution_time = 300
upload_max_filesize = 64M
post_max_size = 64M
INI
                       green_message "✅ .user.ini created"
                       ;;
                    2) mkdir -p "$tbsPath/sites/php/pools"
                       cat > "$pool_conf" <<POOL
[$app_user]
user = www-data
group = www-data
listen = /var/run/php-fpm-$app_user.sock
pm = dynamic
pm.max_children = 20
pm.start_servers = 5
POOL
                       green_message "✅ FPM pool created"
                       ;;
                    3) rm -f "$user_ini" "$pool_conf"; green_message "✅ Deleted" ;;
                    4) [[ -f "$user_ini" ]] && open_in_editor "$user_ini" || info_message "File not found" ;;
                    5) [[ -f "$pool_conf" ]] && open_in_editor "$pool_conf" || info_message "File not found" ;;
                    6) [[ -f "$pool_conf" ]] && cat "$pool_conf" || info_message "No pool config" ;;
                    0) return 0 ;;
                    *) error_message "Invalid option" ;;
                esac
                echo ""
                read -p "Press Enter to continue..."
            done
            ;;
        
        # tbs app supervisor [app] [add|rm|list]
        supervisor)
            _app_get "$app_arg1" || return 1
            local app_user="$SELECTED_APP"
            local action="${app_arg2:-list}"
            local name="${app_arg3:-worker}"
            local sc="$tbsPath/sites/supervisor/${app_user}_${name}.conf"
            
            case "$action" in
                add) read -p "Command: " cmd
                     echo -e "[program:${app_user}_${name}]\ncommand=$cmd\ndirectory=/var/www/html/${APPLICATIONS_DIR_NAME}/$app_user\nautostart=true\nautorestart=true" > "$sc"
                     green_message "✅ Added: $sc" ;;
                rm|remove) rm -f "$sc"; green_message "✅ Removed" ;;
                list|ls|*) ls "$tbsPath/sites/supervisor/${app_user}_"*.conf 2>/dev/null || echo "None" ;;
            esac
            ;;

        # tbs app cron [app] [add|rm|list]
        cron)
            _app_get "$app_arg1" || return 1
            local app_user="$SELECTED_APP"
            local action="${app_arg2:-list}"
            local cf="$tbsPath/sites/cron/${app_user}_cron"
            
            case "$action" in
                add) read -p "Schedule (e.g. * * * * *): " sched; read -p "Command: " cmd
                     echo "$sched root cd /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user && $cmd" >> "$cf"
                     green_message "✅ Cron added" ;;
                rm|remove) [[ -f "$cf" ]] && sed_i "${app_arg3}d" "$cf" && green_message "✅ Removed line ${app_arg3}" ;;
                list|ls|*) [[ -f "$cf" ]] && cat -n "$cf" || echo "None" ;;
            esac
            ;;

        # tbs app logs [app] [enable|disable]
        logs)
            _app_get "$app_arg1" || return 1
            local app_user="$SELECTED_APP"
            local action="${app_arg2:-status}"
            local app_root="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_user"
            
            case "$action" in
                enable) mkdir -p "$app_root/logs"; set_app_config "$app_user" "logs.enabled" "true"; green_message "✅ Logs enabled" ;;
                disable) set_app_config "$app_user" "logs.enabled" "false"; yellow_message "Logs disabled" ;;
                status|*) info_message "Logs: $(get_app_config "$app_user" "logs.enabled")" ;;
            esac
            ;;

        # tbs app config [app] [action] [value] - App settings
        config|settings)
            _app_get "$app_arg1" || return 1
            local app_user="$SELECTED_APP"
            local sub_action="$app_arg2"
            local sub_val="$app_arg3"

            # Non-interactive mode
            if [[ -n "$sub_action" ]]; then
                case "$sub_action" in
                    varnish)
                        [[ "$sub_val" =~ ^(on|1|true)$ ]] && { set_app_config "$app_user" "varnish" "true"; green_message "Varnish ON"; } || \
                        [[ "$sub_val" =~ ^(off|0|false)$ ]] && { set_app_config "$app_user" "varnish" "false"; yellow_message "Varnish OFF"; } || \
                        info_message "Varnish: $(get_app_config "$app_user" "varnish")" ;;
                    webroot)
                        [[ -z "$sub_val" ]] && { info_message "Webroot: $(get_app_config "$app_user" "webroot")"; return; }
                        set_app_config "$app_user" "webroot" "\"$sub_val\""; green_message "Webroot: $sub_val"
                        local d=$(get_app_config "$app_user" "primary_domain") dr="/var/www/html/${APPLICATIONS_DIR_NAME}/$app_user/$sub_val"
                        [[ -f "${VHOSTS_DIR}/${d}.conf" ]] && sed_i "s|DocumentRoot.*|DocumentRoot $dr|g" "${VHOSTS_DIR}/${d}.conf"
                        [[ -f "${NGINX_CONF_DIR}/${d}.conf" ]] && sed_i "s|root.*/var/www/html/${APPLICATIONS_DIR_NAME}/$app_user[^;]*|root $dr|g" "${NGINX_CONF_DIR}/${d}.conf"
                        info_message "Restart to apply: tbs restart" ;;
                    perms|permissions)
                        is_service_running "$WEBSERVER_SERVICE" && docker compose exec -T "$WEBSERVER_SERVICE" bash -c "
                            find /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user -type d -exec chmod 755 {} \;
                            find /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user -type f -exec chmod 644 {} \;
                        " 2>/dev/null && green_message "✅ Permissions reset" ;;
                    show) command_exists jq && jq '.' "$(get_app_config_path "$app_user")" || cat "$(get_app_config_path "$app_user")" ;;
                    *) error_message "Unknown config action: $sub_action" ;;
                esac
                return 0
            fi
            
            while true; do
                _app_header "$app_user" "⚙️  Settings"
                local varnish=$(get_app_config "$app_user" "varnish")
                local webroot=$(get_app_config "$app_user" "webroot")
                echo "  Varnish: ${varnish:-true}"
                echo "  Webroot: ${webroot:-public_html}"
                echo ""
                echo "  1) 🔄 Toggle Varnish"
                echo "  2) 📁 Change Webroot"
                echo "  3) 🔐 Reset Permissions"
                echo "  4) 📋 Show Full Config"
                echo "  0) ↩️  Back"
                echo ""
                read -p "Select [0-4]: " choice
                
                case "$choice" in
                    1) [[ "$varnish" == "false" ]] && set_app_config "$app_user" "varnish" "true" && green_message "Varnish ON" || { set_app_config "$app_user" "varnish" "false"; yellow_message "Varnish OFF"; } ;;
                    2) read -p "Webroot (e.g., public, web): " new_wr
                       [[ -n "$new_wr" ]] && { set_app_config "$app_user" "webroot" "\"$new_wr\""; green_message "Webroot: $new_wr"; } ;;
                    3) is_service_running "$WEBSERVER_SERVICE" && docker compose exec -T "$WEBSERVER_SERVICE" bash -c "
                           find /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user -type d -exec chmod 755 {} \;
                           find /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user -type f -exec chmod 644 {} \;
                       " 2>/dev/null && green_message "✅ Permissions reset" ;;
                    4) command_exists jq && jq '.' "$(get_app_config_path "$app_user")" || cat "$(get_app_config_path "$app_user")" ;;
                    0) return 0 ;;
                    *) error_message "Invalid option" ;;
                esac
                echo ""
                read -p "Press Enter to continue..."
            done
            ;;
        
        # tbs app code [app] - Open in VS Code
        code|edit)
            _app_get "$app_arg1" || return 1
            code "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$SELECTED_APP"
            green_message "Opening in VS Code..."
            ;;
        
        # tbs app open [app] - Open in browser  
        open|browse)
            _app_get "$app_arg1" || return 1
            local dom=$(get_app_config "$SELECTED_APP" "primary_domain")
            open_browser "https://${dom:-$SELECTED_APP.localhost}"
            ;;
        
        # tbs app info [app] - Show app info
        info|show)
            _app_get "$app_arg1" || return 1
            _app_header "$SELECTED_APP" "ℹ️  Info"
            command_exists jq && jq '.' "$(get_app_config_path "$SELECTED_APP")"
            ;;
        
        # Help
        help|--help|-h)
            echo ""
            blue_message "╔══════════════════════════════════════════════════════════════╗"
            blue_message "║                    📦 tbs app - Help                         ║"
            blue_message "╚══════════════════════════════════════════════════════════════╝"
            echo ""
            echo "  ${CYAN}tbs app${NC}                    Interactive app manager"
            echo "  ${CYAN}tbs app add <name>${NC}         Create new app"
            echo "  ${CYAN}tbs app rm [app]${NC}           Delete app"
            echo "  ${CYAN}tbs app db [app]${NC}           Database management"
            echo "  ${CYAN}tbs app ssh [app]${NC}          SSH/SFTP settings"
            echo "  ${CYAN}tbs app domain [app]${NC}       Manage domains"
            echo "  ${CYAN}tbs app ssl [app]${NC}          SSL certificates"
            echo "  ${CYAN}tbs app php [app]${NC}          PHP configuration"
            echo "  ${CYAN}tbs app config [app]${NC}       App settings"
            echo "  ${CYAN}tbs app code [app]${NC}         Open in VS Code"
            echo "  ${CYAN}tbs app open [app]${NC}         Open in browser"
            echo "  ${CYAN}tbs app info [app]${NC}         Show app config"
            echo ""
            ;;
        
        # Direct app access: tbs app <app_user>
        *)
            local maybe_app=$(resolve_app_user "$app_action")
            if [[ -n "$maybe_app" ]]; then
                SELECTED_APP="$maybe_app"
                tbs app
            else
                error_message "Unknown: $app_action"
                info_message "Run: tbs app help"
            fi
            ;;
        esac
        ;;

    # Show logs
    logs)
        [[ -n "$2" ]] && docker compose logs -f "$2" || docker compose logs -f
        ;;

    status) docker compose ps ;;

    # Handle 'code' command - Open in VS Code
    code)
        [[ "$2" == "root" || "$2" == "tbs" ]] && { code "$tbsPath"; return; }
        [[ -n "$2" ]] && { local d="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$2"; [[ -d "$d" ]] && code "$d" || error_message "App not found: $2"; return; }
        tbs app code
        ;;
    info)
        print_header
        blue_message "System Information"
        echo "  OS: $(uname -s) $(uname -r)"
        echo "  Docker: $(docker --version)"
        echo "  Compose: $(docker compose version)"
        echo ""
        blue_message "Stack Configuration"
        if [[ -f .env ]]; then
            echo "  PHP Version: ${PHPVERSION:-Unknown}"
            echo "  Database: ${DATABASE:-Unknown}"
            echo "  Webserver: ${WEBSERVER_SERVICE:-Unknown}"
            echo "  Install Type: ${INSTALLATION_TYPE:-Unknown}"
        else
            yellow_message "  .env file not found"
        fi
        echo ""
        blue_message "Service Status"
        docker compose ps
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
                    if ! cat "$sql_file" | execute_mysql_command; then
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

    # SSL commands - redirect to app ssl
    ssl) tbs app ssl "$2" ;;
    ssl-localhost) generate_default_ssl ;;
    mail)
        if is_service_running "mailpit"; then
            open_browser "http://localhost:8025"
        else
            yellow_message "Mailpit is not running (requires APP_ENV=development)"
        fi
        ;;
    pma)
        if is_service_running "phpmyadmin"; then
            open_browser "http://localhost:${HOST_MACHINE_PMA_PORT}"
        else
            yellow_message "phpMyAdmin is not running (requires APP_ENV=development)"
        fi
        ;;
    redis-cli)
        if is_service_running "redis"; then
            docker compose exec redis redis-cli
        else
            yellow_message "Redis is not running"
        fi
        ;;

    # Shell access
    shell)
        local s="${2:-php}"
        case "$s" in
            php|web*) docker compose exec "$WEBSERVER_SERVICE" bash ;;
            mysql|maria*|db) docker compose exec dbhost bash ;;
            redis) docker compose exec redis sh ;;
            nginx|varnish|memcached|mailpit) docker compose exec "$s" sh ;;
            *) error_message "Unknown: $s (php/mysql/redis/nginx/varnish/memcached/mailpit)" ;;
        esac
        ;;

    # Database management
    db)
        local action="${2:-}" name="${3:-}" file="${4:-}"
        is_service_running "dbhost" || { error_message "MySQL not running"; return 1; }
        case "$action" in
            list|ls) execute_mysql_command -e "SHOW DATABASES;" | grep -vE "^(Database|information_schema|performance_schema|mysql|sys)$" ;;
            create) [[ -z "$name" ]] && read -p "Database name: " name; _db_create "$name" ;;
            drop) [[ -z "$name" ]] && read -p "Database to drop: " name
                  read -p "Drop '$name'? (y/N): " confirm; [[ "$confirm" =~ ^[Yy]$ ]] && _db_drop "$name" || info_message "Cancelled" ;;
            import) [[ -z "$name" ]] && read -p "Database: " name; [[ -z "$file" ]] && read -p "SQL file: " file
                    _db_import "$name" "$file" ;;
            export) [[ -z "$name" ]] && read -p "Database: " name; [[ -z "$name" ]] && { error_message "Name required"; return 1; }
                    local outfile="$tbsPath/data/backup/${name}_$(date +%Y%m%d_%H%M%S).sql"
                    _db_export "$name" "$outfile" ;;
            user) local user="${3:-}" pass="${4:-}" db="${5:-}"
                  [[ -z "$user" ]] && read -p "Username: " user; [[ -z "$user" ]] && { error_message "Required"; return 1; }
                  [[ -z "$pass" ]] && pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 16)
                  [[ -z "$db" ]] && db="$user"
                  _db_create_user "$user" "$pass" "$db" && echo "User: $user | Pass: $pass | DB: $db" ;;
            *) info_message "tbs db [list|create|drop|import|export|user] <name>" ;;
        esac
        ;;

    # Quick project creators
    create)
        local t="${2:-}" n="${3:-}"
        is_service_running "$WEBSERVER_SERVICE" || { yellow_message "Starting stack..."; tbs_start; }
        [[ -z "$t" ]] && { info_message "Types: laravel, wordpress, symfony, blank"; read -p "Type: " t; }
        [[ -z "$n" ]] && read -p "App name: " n; [[ -z "$n" ]] && { error_message "Name required"; return 1; }
        
        tbs app add "$n"
        local u=$(find_app_user_by_name "$n"); [[ -z "$u" ]] && { error_message "App not found"; return 1; }
        local apps_dir="${APPLICATIONS_DIR_NAME:-applications}"
        
        case "$t" in
            laravel) docker compose exec "$WEBSERVER_SERVICE" bash -c "cd /var/www/html/$apps_dir/$u && rm -rf public_html/* && composer create-project --no-interaction laravel/laravel public_html"
                     tbs app config "$u" webroot "public_html/public"; green_message "Laravel: https://${u}.localhost" ;;
            wordpress)
                # Get DB config or create if missing
                local db_name=$(get_app_config "$u" "database.name")
                if [[ -z "$db_name" || "$db_name" == "null" ]]; then
                    # Create database for this app
                    db_name="${u//-/_}"
                    local db_user="$db_name"
                    local db_pass=$(generate_strong_password 16)
                    
                    _db_create "$db_name" && _db_create_user "$db_user" "$db_pass" "$db_name"
                    
                    # Update app config
                    command_exists jq && {
                        local cfg=$(get_app_config_path "$u")
                        local tmp=$(mktemp)
                        if jq '.database={"name":"'"$db_name"'","user":"'"$db_user"'","password":"'"$db_pass"'","host":"dbhost","created":true}' "$cfg" > "$tmp" 2>/dev/null; then
                            mv "$tmp" "$cfg"
                        else
                            rm -f "$tmp"
                        fi
                    }
                    
                    green_message "Database created: $db_name"
                else
                    db_user=$(get_app_config "$u" "database.user")
                    db_pass=$(get_app_config "$u" "database.password")
                fi
                local db_host=$(get_app_config "$u" "database.host")
                [[ -z "$db_host" || "$db_host" == "null" || "$db_host" == "mysql" || "$db_host" == "database" ]] && db_host="dbhost"

                # Install WordPress
                green_message "Installing WordPress..."
                docker compose exec "$WEBSERVER_SERVICE" bash -c "cd /var/www/html/$apps_dir/$u/public_html && rm -f index.php index.html && wp core download --allow-root --force"
                
                # Configure WordPress
                docker compose exec "$WEBSERVER_SERVICE" bash -c "cd /var/www/html/$apps_dir/$u/public_html && wp config create --dbname='$db_name' --dbuser='$db_user' --dbpass='$db_pass' --dbhost='$db_host' --allow-root --force"
                
                green_message "WordPress: https://${u}.localhost" ;;
            symfony) docker compose exec "$WEBSERVER_SERVICE" bash -c "cd /var/www/html/$apps_dir/$u && rm -rf public_html/* && composer create-project --no-interaction symfony/skeleton public_html"
                     tbs app config "$u" webroot "public_html/public"; green_message "Symfony: https://${u}.localhost" ;;
            blank|empty) green_message "Blank: https://${u}.localhost" ;;
            *) error_message "Unknown: $t. Available: laravel, wordpress, symfony, blank" ;;
        esac
        ;;

    # SSH Admin Management - uses TBS_ADMIN_* from .env
    sshadmin)
        local action="${2:-show}"
        local admin_user="${TBS_ADMIN_USER:-tbsadmin}"
        local admin_pass="${TBS_ADMIN_PASSWORD:-tbsadmin123}"
        local admin_email="${TBS_ADMIN_EMAIL:-admin@localhost}"
        
        case "$action" in
            show|status)
                echo ""; blue_message "TBS Admin (Master User)"
                echo "  User:  $admin_user"
                echo "  Email: $admin_email"
                echo "  Port:  ${HOST_MACHINE_SSH_PORT:-2244}"
                echo ""; info_message "SSH: ssh -p ${HOST_MACHINE_SSH_PORT:-2244} $admin_user@localhost"
                echo ""; yellow_message "Password is in .env (TBS_ADMIN_PASSWORD)" ;;
            password|reset)
                local new_pass=$(generate_strong_password 22)
                sed_i "s|^TBS_ADMIN_PASSWORD=.*|TBS_ADMIN_PASSWORD=$new_pass|" "$tbsPath/.env"
                green_message "New password: $new_pass"
                yellow_message "Restart SSH to apply: docker compose --profile ssh restart ssh" ;;
            *) info_message "tbs sshadmin [show|password]" ;;
        esac
        ;;

    "")
        interactive_menu
        ;;
    help|--help|-h)
            print_header
            echo "Usage: tbs [command] [args]"
            echo ""
            echo "Stack:    start, stop, restart, build, status, config, info"
            echo "Apps:     tbs app [add|rm|db|ssh|domain|ssl|php|config|code|open] <app>"
            echo "Projects: tbs create [laravel|wordpress|symfony|blank] <name>"
            echo "Database: tbs db [list|create|drop|import|export|user] <name>"
            echo "Tools:    shell [php|mysql|redis], pma, mail, code, logs [service]"
            echo "SSH:      sshadmin [show|password]"
            echo "Other:    backup, restore, ssl-localhost"
            ;;
        *)
            error_message "Unknown: $1 | Run: tbs help"
            ;;
    esac
}

# Check requirements
for c in docker sed curl; do command_exists "$c" || { error_message "$c not found"; exit 1; }; done
docker compose version >/dev/null 2>&1 || { error_message "Docker Compose missing"; exit 1; }

tbs "$@"
