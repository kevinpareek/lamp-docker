#!/bin/bash

# Get tbs script directory
# Cross-platform readlink -f implementation
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    
    # Detect if we're on Windows (Git Bash/MSYS)
    local is_windows=false
    case "$(uname -s)" in
        CYGWIN*|MINGW32*|MSYS*|MINGW*) is_windows=true ;;
    esac
    
    # On Windows (Git Bash/MSYS), handle path conversion
    if [[ "$is_windows" == true ]]; then
        # If source is a relative path, make it absolute first
        if [[ "$source" != /* ]] && [[ "$source" != [a-zA-Z]:* ]]; then
            source="$(pwd)/$source"
        fi
        
        # Convert Windows path to Unix path if needed (D:\path -> /d/path)
        if [[ "$source" =~ ^[a-zA-Z]: ]]; then
            local drive="${source:0:1}"
            local path_part="${source:3}"
            source="/$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')$path_part"
            source="${source//\\//}"
        fi
    fi
    
    while [ -h "$source" ]; do # resolve $source until the file is no longer a symlink
        local dir="$( cd -P "$( dirname "$source" )" >/dev/null 2>&1 && pwd )"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source" # if $source was a relative symlink, we need to resolve it relative to the path where the symlink file was located
    done
    
    local result="$( cd -P "$( dirname "$source" )" >/dev/null 2>&1 && pwd )"
    
    # On Windows, normalize the path
    if [[ "$is_windows" == true ]]; then
        # Ensure path uses forward slashes and is properly formatted
        result="${result//\\//}"
        # Remove any double slashes
        result="${result//\/\///}"
    fi
    
    echo "$result"
}

tbsPath=$(get_script_dir)
tbsFile="$tbsPath/$(basename "${BASH_SOURCE[0]}")"

# Validate that the script file actually exists
if [[ ! -f "$tbsFile" ]]; then
    echo "Error: Cannot locate tbs.sh script at: $tbsFile" >&2
    exit 1
fi

# ============================================
# Global Constants (Set Once at Startup)
# ============================================
# Colors and Styles
BOLD='\033[1m'
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Detect OS type once at startup
detect_os_type() {
    case "$(uname -s)" in
        Darwin) echo "mac" ;;
        Linux) echo "linux" ;;
        CYGWIN*|MINGW32*|MSYS*|MINGW*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}
OS_TYPE=$(detect_os_type)

# Check jq availability once at startup
HAS_JQ=false
command -v jq >/dev/null 2>&1 && HAS_JQ=true

# ============================================
# State File Path (config tracker)
# ============================================
TBS_STATE_DIR="$tbsPath/data/config"
TBS_STATE_FILE="$TBS_STATE_DIR/.tbs_state"

# ============================================
# State Management Functions
# ============================================

# Simple encode/decode for state file (base64 + ROT13)
# Prevents casual reading of sensitive data
_state_encode() {
    echo "$1" | base64 2>/dev/null | tr 'A-Za-z' 'N-ZA-Mn-za-m'
}

_state_decode() {
    echo "$1" | tr 'N-ZA-Mn-za-m' 'A-Za-z' | base64 -d 2>/dev/null
}

# Global variable to cache state content
_STATE_CACHE=""

# Get raw decoded state content (cached for performance)
_get_state_content() {
    if [[ -z "$_STATE_CACHE" ]]; then
        [[ ! -f "$TBS_STATE_FILE" ]] && return 1
        _STATE_CACHE=$(_state_decode "$(cat "$TBS_STATE_FILE")")
    fi
    echo "$_STATE_CACHE"
}

# Initialize state file with current .env values
init_state_file() {
    mkdir -p "$TBS_STATE_DIR" 2>/dev/null || true
    _STATE_CACHE="" # Clear cache
    
    local ts=$(date +%s)
    local state_content="MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-root}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-docker}
MYSQL_USER=${MYSQL_USER:-docker}
MYSQL_DATABASE=${MYSQL_DATABASE:-docker}
DATABASE=${DATABASE:-mariadb11.4}
PHPVERSION=${PHPVERSION:-php8.5}
STACK_MODE=${STACK_MODE:-hybrid}
INSTALLATION_TYPE=${INSTALLATION_TYPE:-local}
APP_ENV=${APP_ENV:-development}
REDIS_PASSWORD=${REDIS_PASSWORD:-}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-turbo-stack}
STATE_INITIALIZED=$ts
LAST_UPDATED=$ts"
    
    _state_encode "$state_content" > "$TBS_STATE_FILE"
    chmod 600 "$TBS_STATE_FILE" 2>/dev/null || true
}

# Read a value from state file
get_state_value() {
    local key="$1"
    local content
    content=$(_get_state_content) || return 1
    echo "$content" | grep "^${key}=" | head -1 | cut -d'=' -f2-
}

# Update state file with current env values
update_state_file() {
    mkdir -p "$TBS_STATE_DIR" 2>/dev/null || true
    _STATE_CACHE="" # Clear cache
    
    # Preserve init timestamp if exists
    local init_ts=$(get_state_value "STATE_INITIALIZED" 2>/dev/null)
    [[ -z "$init_ts" ]] && init_ts=$(date +%s)
    
    local state_content="MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-}
MYSQL_PASSWORD=${MYSQL_PASSWORD:-}
MYSQL_USER=${MYSQL_USER:-}
MYSQL_DATABASE=${MYSQL_DATABASE:-}
DATABASE=${DATABASE:-}
PHPVERSION=${PHPVERSION:-}
STACK_MODE=${STACK_MODE:-}
INSTALLATION_TYPE=${INSTALLATION_TYPE:-}
APP_ENV=${APP_ENV:-}
REDIS_PASSWORD=${REDIS_PASSWORD:-}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME:-}
STATE_INITIALIZED=$init_ts
LAST_UPDATED=$(date +%s)"
    
    _state_encode "$state_content" > "$TBS_STATE_FILE"
}

# Check if state file exists and is valid
has_valid_state() {
    [[ -f "$TBS_STATE_FILE" ]] || return 1
    _get_state_content 2>/dev/null | grep -q "STATE_INITIALIZED=" || return 1
}

# ============================================
# Critical Change Detection
# ============================================

# Variables that require rebuild when changed
REBUILD_REQUIRED_VARS="PHPVERSION DATABASE STACK_MODE INSTALL_XDEBUG REDIS_PASSWORD COMPOSE_PROJECT_NAME INSTALLATION_TYPE APP_ENV"

# Variables that require special handling (runtime password updates)
CRITICAL_VARS="MYSQL_ROOT_PASSWORD MYSQL_PASSWORD MYSQL_USER"

# Detect changes between .env and state file
detect_config_changes() {
    [[ ! -f "$TBS_STATE_FILE" ]] && return 0
    
    local content changes=""
    content=$(_get_state_content) || return 0
    
    for var in $REBUILD_REQUIRED_VARS $CRITICAL_VARS; do
        local current="${!var}"
        local saved=$(echo "$content" | grep "^${var}=" | head -1 | cut -d'=' -f2-)
        [[ -n "$saved" && "$current" != "$saved" ]] && changes+="$var\n"
    done
    
    echo -e "$changes" | grep -v '^$'
}

# Check if rebuild is required
needs_rebuild() {
    local changes="$1"
    [[ -z "$changes" ]] && return 1
    
    for var in $REBUILD_REQUIRED_VARS; do
        echo "$changes" | grep -q "^${var}$" && return 0
    done
    return 1
}

# Compare database versions
# Returns: "upgrade", "downgrade", "same", or "change"
compare_db_versions() {
    local old_db="$1" new_db="$2"
    
    [[ "$old_db" == "$new_db" ]] && echo "same" && return
    [[ -z "$old_db" ]] && echo "new" && return
    
    local old_type="${old_db%%[0-9]*}" new_type="${new_db%%[0-9]*}"
    [[ "$old_type" != "$new_type" ]] && echo "change" && return
    
    local old_ver="${old_db#$old_type}"
    local new_ver="${new_db#$new_type}"
    
    if [[ "$old_ver" == "$new_ver" ]]; then
        echo "same"
    else
        # Portable version comparison (works on macOS/Linux/Windows)
        local i old_parts=(${old_ver//./ }) new_parts=(${new_ver//./ })
        local len=${#old_parts[@]}
        [[ ${#new_parts[@]} -gt $len ]] && len=${#new_parts[@]}
        
        for ((i=0; i<len; i++)); do
            local o=${old_parts[i]:-0}
            local n=${new_parts[i]:-0}
            # Remove any non-numeric characters for comparison
            o=${o//[!0-9]/}
            n=${n//[!0-9]/}
            if ((n > o)); then echo "upgrade"; return; fi
            if ((n < o)); then echo "downgrade"; return; fi
        done
        echo "same"
    fi
}

# ============================================
# Database Operations
# ============================================

# Execute SQL command in database container
_exec_db_sql() {
    local password="$1" sql="$2"
    local escaped_pass="${password//\'/\'\'}"
    
    docker compose exec -T dbhost sh -c "
        if command -v mariadb >/dev/null 2>&1; then CLI='mariadb'; else CLI='mysql'; fi
        \$CLI -uroot -p'${escaped_pass}' -e \"${sql}\" 2>/dev/null
    "
}

# Update MySQL/MariaDB password
_update_db_password() {
    local root_pass="$1" user="$2" new_pass="$3"
    
    [[ -z "$user" || -z "$new_pass" ]] && return 1
    
    local escaped_new="${new_pass//\'/\'\'}"
    local host="%" 
    [[ "$user" == "root" ]] && host="localhost"
    
    local sql="ALTER USER '${user}'@'${host}' IDENTIFIED BY '${escaped_new}';"
    [[ "$user" == "root" ]] && sql+=" ALTER USER 'root'@'%' IDENTIFIED BY '${escaped_new}';"
    sql+=" FLUSH PRIVILEGES;"
    
    _exec_db_sql "$root_pass" "$sql"
}

# Update root password
update_db_root_password() {
    local old_pass="$1" new_pass="$2"
    
    [[ -z "$old_pass" || -z "$new_pass" || "$old_pass" == "$new_pass" ]] && return 0
    
    info_message "Updating database root password..."
    if _update_db_password "$old_pass" "root" "$new_pass"; then
        green_message "✅ Database root password updated!"
        return 0
    fi
    error_message "Failed to update database root password."
    return 1
}

# Update user password
update_db_user_password() {
    local root_pass="$1" user="$2" old_pass="$3" new_pass="$4"
    
    [[ -z "$user" || -z "$new_pass" || "$old_pass" == "$new_pass" ]] && return 0
    
    info_message "Updating database user '$user' password..."
    if _update_db_password "$root_pass" "$user" "$new_pass"; then
        green_message "✅ Database user '$user' password updated!"
        return 0
    fi
    error_message "Failed to update user password."
    return 1
}

# ============================================
# Database Version Change Handler
# ============================================

# Handle database version changes (upgrade/downgrade)
handle_db_version_change() {
    local old_db="$1"
    local new_db="$2"
    local change_type=$(compare_db_versions "$old_db" "$new_db")
    
    case "$change_type" in
        same)
            return 0
            ;;
        upgrade|change)
            echo ""
            blue_message "═══════════════════════════════════════════════════════════════"
            yellow_message "⚠️  DATABASE VERSION CHANGE DETECTED"
            blue_message "═══════════════════════════════════════════════════════════════"
            echo "  Current: $old_db"
            echo "  New:     $new_db"
            echo "  Type:    $(printf '%s' "$change_type" | tr '[:lower:]' '[:upper:]')"
            echo ""
            info_message "Creating automatic backup before version change..."
            
            # Create backup
            if _auto_backup_database; then
                local backup_path="$LATEST_DB_BACKUP"
                
                green_message "✅ Backup created successfully!"
                echo ""
                if yes_no_prompt "Would you like to attempt an automatic data migration? (Recommended)"; then
                    info_message "Starting database for migration..."
                    docker compose up -d --build dbhost
                    
                    info_message "Waiting for database to be ready..."
                    local count=0
                    local ready=false
                    while [ $count -lt 30 ]; do
                        # Try to connect to the database
                        if docker compose exec -T dbhost sh -c "if command -v mariadb >/dev/null 2>&1; then mariadb -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -e 'SELECT 1'; else mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -e 'SELECT 1'; fi" >/dev/null 2>&1; then
                            ready=true
                            break
                        fi
                        printf "."
                        sleep 2
                        ((count++))
                    done
                    echo ""
                    
                    if [[ "$ready" == "true" ]]; then
                        info_message "Running upgrade tools..."
                        local root_pass=$(get_state_value "MYSQL_ROOT_PASSWORD")
                        [[ -z "$root_pass" ]] && root_pass="${MYSQL_ROOT_PASSWORD:-root}"
                        
                        # MySQL 8.0+ handles upgrade automatically, but MariaDB still benefits from mariadb-upgrade
                        if [[ "$new_db" == *"mariadb"* ]]; then
                            docker compose exec -T -e MYSQL_PWD="$root_pass" dbhost sh -c "if command -v mariadb-upgrade >/dev/null 2>&1; then mariadb-upgrade -uroot; else mysql_upgrade -uroot; fi" 2>/dev/null
                        else
                            # For MySQL, we just check if it's 8.0+
                            info_message "MySQL 8.0+ handles upgrades automatically."
                        fi
                        green_message "✅ Upgrade/Migration attempt finished."
                    else
                        error_message "Database failed to become ready for migration."
                        yellow_message "You may need to run 'tbs status' and check logs."
                    fi
                fi
                
                update_state_file
                return 0
            else
                error_message "Backup failed!"
                if ! yes_no_prompt "Continue without backup? (DANGEROUS)"; then
                    # Revert .env to old version
                    sed_i "s|^DATABASE=.*|DATABASE=$old_db|" "$tbsPath/.env"
                    DATABASE="$old_db"
                    yellow_message "Reverted to $old_db"
                    return 0
                fi
            fi
            ;;
        downgrade)
            echo ""
            red_message "╔════════════════════════════════════════════════════════════╗"
            red_message "║         ⚠️  DATABASE DOWNGRADE DETECTED                    ║"
            red_message "╚════════════════════════════════════════════════════════════╝"
            echo ""
            echo "  Current installed: $old_db"
            echo "  Requested:         $new_db"
            echo ""
            red_message "⚠️  DOWNGRADE WARNING:"
            echo "  • Data in /data/mysql/ was created with $old_db"
            echo "  • $new_db may NOT be able to read this data"
            echo "  • This can cause DATA LOSS or corruption"
            echo ""
            yellow_message "Options:"
            echo "  1) Cancel - Keep using $old_db (RECOMMENDED)"
            echo "  2) Fresh Start - Backup data, delete /data/mysql/, use $new_db"
            echo ""
            read -p "  Select [1-2] (default: 1): " choice
            choice="${choice:-1}"
            
            case "$choice" in
                2)
                    echo ""
                    red_message "⚠️  FINAL WARNING: This will:"
                    echo "    • Backup ALL databases"
                    echo "    • Move current data to a safety backup folder"
                    echo "    • Start fresh with $new_db"
                    echo "    • Attempt automatic restoration"
                    echo ""
                    read -p "  Type 'DOWNGRADE' to confirm: " confirm
                    
                    if [[ "$confirm" == "DOWNGRADE" ]]; then
                        info_message "Creating backup..."
                        if _auto_backup_database; then
                            local backup_path="$LATEST_DB_BACKUP"
                            
                            # Safety Check: Ensure backup file exists and is not empty
                            if [[ ! -s "$backup_path" ]]; then
                                error_message "Backup file is empty or missing! Aborting for safety."
                                return 1
                            fi
                            
                            green_message "✅ Backup verified: $(basename "$backup_path")"
                            
                            info_message "Stopping database container..."
                            docker compose stop dbhost 2>/dev/null || true
                            docker compose rm -f dbhost 2>/dev/null || true
                            
                            local mysql_data_rel="${MYSQL_DATA_DIR:-data/mysql}"
                            local mysql_data="$tbsPath/${mysql_data_rel#./}"
                            
                            # Double check we are not deleting something critical
                            if [[ "$mysql_data" == "$tbsPath" || "$mysql_data" == "/" ]]; then
                                error_message "Invalid MYSQL_DATA_DIR path. Aborting."
                                return 1
                            fi

                            local safety_backup="$tbsPath/data/mysql_pre_downgrade_$(date +%Y%m%d_%H%M%S)"
                            info_message "Moving current data to $safety_backup for safety..."
                            mkdir -p "$safety_backup"
                            # Move all files and folders (including hidden ones) from mysql_data to safety_backup
                            find "$mysql_data" -mindepth 1 -maxdepth 1 -exec mv {} "$safety_backup/" \; 2>/dev/null || true
                            
                            green_message "✅ Data directory cleared (moved to safety backup)."
                            info_message "Starting fresh $new_db installation..."
                            
                            # Update state file immediately to reflect the new version
                            update_state_file
                            
                            # Force rebuild of the database container
                            docker compose up -d --build dbhost
                            
                            info_message "Waiting for database to initialize..."
                            local count=0
                            local ready=false
                            while [ $count -lt 60 ]; do
                                if docker compose exec -T dbhost sh -c "if command -v mariadb >/dev/null 2>&1; then mariadb -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -e 'SELECT 1'; else mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -e 'SELECT 1'; fi" >/dev/null 2>&1; then
                                    ready=true
                                    break
                                fi
                                printf "."
                                sleep 2
                                ((count++))
                            done
                            echo ""
                            
                            if [[ "$ready" == "true" ]]; then
                                green_message "✅ Database is up and running!"
                                echo ""
                                if yes_no_prompt "Would you like to restore your databases from the backup now?"; then
                                    info_message "Restoring databases..."
                                    
                                    local restore_success=false
                                    local root_pass=$(get_state_value "MYSQL_ROOT_PASSWORD")
                                    [[ -z "$root_pass" ]] && root_pass="${MYSQL_ROOT_PASSWORD:-root}"
                                    
                                    # Detect client binary inside container
                                    local client_cmd="if command -v mariadb >/dev/null 2>&1; then echo 'mariadb'; else echo 'mysql'; fi"
                                    local client_bin=$(docker compose exec -T dbhost sh -c "$client_cmd" 2>/dev/null | tr -d '\r\n')
                                    client_bin="${client_bin:-mysql}"

                                    if [[ "$backup_path" == *.gz ]]; then
                                        if gunzip -c "$backup_path" | docker compose exec -T -e MYSQL_PWD="$root_pass" dbhost "$client_bin" -uroot >/dev/null 2>&1; then restore_success=true; fi
                                    else
                                        if cat "$backup_path" | docker compose exec -T -e MYSQL_PWD="$root_pass" dbhost "$client_bin" -uroot >/dev/null 2>&1; then restore_success=true; fi
                                    fi
                                    
                                    if [[ "$restore_success" == "true" ]]; then
                                        green_message "✅ Databases restored successfully!"
                                    else
                                        yellow_message "⚠️  Restore finished with some warnings. Please check your data."
                                    fi
                                else
                                    info_message "You can restore manually later from: data/backup/$(basename "$backup_path")"
                                fi
                            else
                                error_message "Database failed to start or become ready. Please run: tbs status"
                            fi
                            return 0
                        else
                            error_message "Backup failed! Aborting downgrade."
                            sed_i "s|^DATABASE=.*|DATABASE=$old_db|" "$tbsPath/.env"
                            DATABASE="$old_db"
                            return 0
                        fi
                    else
                        yellow_message "Downgrade cancelled."
                        sed_i "s|^DATABASE=.*|DATABASE=$old_db|" "$tbsPath/.env"
                        DATABASE="$old_db"
                        return 0
                    fi
                    ;;
                *)
                    yellow_message "Keeping $old_db"
                    sed_i "s|^DATABASE=.*|DATABASE=$old_db|" "$tbsPath/.env"
                    DATABASE="$old_db"
                    # Continue with current DB version instead of aborting start.
                    return 0
                    ;;
            esac
            ;;
    esac
}

# Auto backup all databases (for version changes)
_auto_backup_database() {
    local backup_dir="$tbsPath/data/backup"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$backup_dir/db_auto_backup_${timestamp}.sql"
    local container_name="${COMPOSE_PROJECT_NAME:-turbo-stack}-db"
    
    mkdir -p "$backup_dir"
    LATEST_DB_BACKUP="" # Reset global variable
    
    # Check if database is running
    local running=false
    if is_service_running "dbhost"; then
        running=true
    else
        # Try to start the existing container if it exists but is stopped
        local container_id=$(docker ps -a --filter "name=${container_name}" --format "{{.ID}}" | head -n 1)
        if [[ -n "$container_id" ]]; then
            info_message "Database container stopped. Attempting to start for backup..."
            docker start "$container_id" >/dev/null 2>&1
            # Wait up to 20 seconds for it to be ready
            local count=0
            while [ $count -lt 10 ]; do
                if docker exec -i "$container_id" sh -c "if command -v mariadb >/dev/null 2>&1; then mariadb -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -e 'SELECT 1'; else mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -e 'SELECT 1'; fi" >/dev/null 2>&1; then
                    running=true
                    break
                fi
                sleep 2
                ((count++))
            done
        fi
    fi

    if [[ "$running" == "false" ]]; then
        yellow_message "⚠️  Database not running and could not be started. Skipping SQL backup."
        return 0
    fi
    
    # Get current root password from state or env
    local root_pass=$(get_state_value "MYSQL_ROOT_PASSWORD")
    [[ -z "$root_pass" ]] && root_pass="${MYSQL_ROOT_PASSWORD:-root}"
    
    # Get list of valid databases from information_schema (more reliable than SHOW DATABASES)
    local db_query="SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys', 'phpmyadmin') AND schema_name NOT REGEXP '^#';"
    
    # Detect client binary inside container
    local client_cmd="if command -v mariadb >/dev/null 2>&1; then echo 'mariadb'; else echo 'mysql'; fi"
    local client_bin
    if is_service_running "dbhost"; then
        client_bin=$(docker compose exec -T dbhost sh -c "$client_cmd" 2>/dev/null | tr -d '\r\n')
    else
        client_bin=$(docker exec -i "$container_name" sh -c "$client_cmd" 2>/dev/null | tr -d '\r\n')
    fi
    client_bin="${client_bin:-mysql}"

    local db_list=""
    local list_err=$(mktemp)
    if is_service_running "dbhost"; then
        db_list=$(docker compose exec -T -e MYSQL_PWD="$root_pass" dbhost "$client_bin" -uroot -N -B -e "$db_query" 2>"$list_err")
    else
        db_list=$(docker exec -i -e MYSQL_PWD="$root_pass" "$container_name" "$client_bin" -uroot -N -B -e "$db_query" 2>"$list_err")
    fi

    # If the output contains "OCI runtime exec failed" or similar, it's an error, not a list of DBs
    if grep -qE "OCI runtime|exec failed|not found" "$list_err" 2>/dev/null; then
        db_list=""
    fi
    rm -f "$list_err"

    if [[ -z "$db_list" ]]; then
        yellow_message "No valid databases found to backup (or database client not ready)."
        return 0
    fi

    # Dump databases one by one to handle potential corruption in individual DBs
    local err_file=$(mktemp)
    local success_count=0
    local total_count=0
    
    # Create a temporary combined SQL file
    local temp_sql=$(mktemp)
    
    for db in $db_list; do
        ((total_count++))
        info_message "  Backing up: $db..."
        
        local dump_cmd="if command -v mariadb-dump >/dev/null 2>&1; then CMD='mariadb-dump'; else CMD='mysqldump'; fi; \$CMD -uroot -p\"\$MYSQL_PWD\" --databases \"$db\" --single-transaction --routines --triggers --events"
        
        local db_success=false
        if docker compose exec -T -e MYSQL_PWD="$root_pass" dbhost sh -c "$dump_cmd" >> "$temp_sql" 2>>"$err_file"; then
            db_success=true
        elif docker exec -i -e MYSQL_PWD="$root_pass" "$container_name" sh -c "$dump_cmd" >> "$temp_sql" 2>>"$err_file"; then
            db_success=true
        fi
        
        if [[ "$db_success" == "true" ]]; then
            ((success_count++))
        else
            yellow_message "  ⚠️  Failed to backup '$db', skipping..."
        fi
    done

    if [[ $success_count -gt 0 ]]; then
        mv "$temp_sql" "$backup_file"
        gzip "$backup_file" 2>/dev/null || true
        [[ -f "${backup_file}.gz" ]] && backup_file="${backup_file}.gz"
        LATEST_DB_BACKUP="$backup_file" # Set global variable for other functions
        green_message "✅ Backup saved: $(basename "$backup_file") ($success_count/$total_count databases)"
        rm -f "$err_file"
        return 0
    fi
    
    # If we failed completely
    if [[ -s "$err_file" ]]; then
        yellow_message "  Dump error: $(cat "$err_file" | head -n 1)"
    fi
    
    rm -f "$backup_file" "${backup_file}.gz" "$err_file" "$temp_sql" 2>/dev/null
    return 1
}

# ============================================
# Pre-Start Configuration Check
# ============================================

# Main function to check and handle config changes before start
check_and_apply_config_changes() {
    local force_rebuild=false
    local changes=""
    
    # First run - initialize state only if actual DB data exists
    if ! has_valid_state; then
        local mysql_data="${MYSQL_DATA_DIR:-./data/mysql}"
        # Check for actual MySQL/MariaDB data files (ibdata1 = InnoDB data file)
        if [[ -f "$mysql_data/ibdata1" ]]; then
            yellow_message "Existing database detected. Initializing state tracker..."
            init_state_file
        else
            # Fresh install - no data yet, init state and skip change detection
            init_state_file
            return 0
        fi
    fi
    
    # Skip change detection if no actual database exists yet
    local mysql_data="${MYSQL_DATA_DIR:-./data/mysql}"
    if [[ ! -f "$mysql_data/ibdata1" ]]; then
        # No database data - just update state with current env values
        update_state_file
        return 0
    fi
    
    # Detect changes
    changes=$(detect_config_changes)
    
    [[ -z "$changes" ]] && return 0
    
    echo ""
    blue_message "═══════════════════════════════════════════════════════════════"
    yellow_message "📋 Configuration Changes Detected"
    blue_message "═══════════════════════════════════════════════════════════════"
    
    # Process each change
    local db_changed=false
    local old_db=$(get_state_value "DATABASE")
    local old_root_pass=$(get_state_value "MYSQL_ROOT_PASSWORD")
    local old_user_pass=$(get_state_value "MYSQL_PASSWORD")
    
    while IFS= read -r var; do
        [[ -z "$var" ]] && continue
        
        local old_val=$(get_state_value "$var")
        local new_val="${!var}"
        
        echo "  • $var: $old_val → $new_val"
        
        case "$var" in
            DATABASE)
                db_changed=true
                ;;
            PHPVERSION|STACK_MODE|APP_ENV|INSTALLATION_TYPE|INSTALL_XDEBUG)
                force_rebuild=true
                ;;
            REDIS_PASSWORD)
                force_rebuild=true
                yellow_message "  ↳ Redis password changed. Container will be rebuilt."
                ;;
            COMPOSE_PROJECT_NAME)
                force_rebuild=true
                yellow_message "  ↳ Project name changed. All containers will be rebuilt."
                ;;
        esac
    done <<< "$changes"
    
    echo ""
    
    # Handle database version change FIRST
    if [[ "$db_changed" == "true" ]]; then
        if ! handle_db_version_change "$old_db" "$DATABASE"; then
            return 1
        fi
        force_rebuild=true
    fi
    
    # Handle password changes (only if DB is running)
    if is_service_running "dbhost"; then
        # Root password change
        if echo "$changes" | grep -q "^MYSQL_ROOT_PASSWORD$"; then
            if ! update_db_root_password "$old_root_pass" "$MYSQL_ROOT_PASSWORD"; then
                error_message "Could not update root password. Using old password."
                MYSQL_ROOT_PASSWORD="$old_root_pass"
                sed_i "s|^MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=$old_root_pass|" "$tbsPath/.env"
            fi
        fi
        
        # User password change
        if echo "$changes" | grep -q "^MYSQL_PASSWORD$"; then
            # Use the current (possibly just updated) root password
            local current_root="${MYSQL_ROOT_PASSWORD}"
            if ! update_db_user_password "$current_root" "${MYSQL_USER:-docker}" "$old_user_pass" "$MYSQL_PASSWORD"; then
                error_message "Could not update user password."
            fi
        fi
    else
        # DB not running - password changes need special handling
        if echo "$changes" | grep -q "MYSQL_ROOT_PASSWORD\|MYSQL_PASSWORD"; then
            yellow_message "Database not running. Password will be updated on next start."
            
            # Save old password for update after container starts
            export TBS_PENDING_ROOT_PASS_UPDATE="$old_root_pass"
            export TBS_PENDING_USER_PASS_UPDATE="$old_user_pass"
        fi
    fi
    
    # Check if rebuild needed
    if [[ "$force_rebuild" == "true" ]] || needs_rebuild "$changes"; then
        echo ""
        yellow_message "⚠️  These changes require a REBUILD"
        info_message "Containers will be rebuilt with new configuration..."
        export TBS_FORCE_REBUILD=true
    fi
    
    # Update state file - BUT preserve old passwords if pending update
    # Password state will be updated ONLY after successful password change
    if [[ -n "${TBS_PENDING_ROOT_PASS_UPDATE:-}" || -n "${TBS_PENDING_USER_PASS_UPDATE:-}" ]]; then
        # Don't update password values in state yet - they haven't been applied
        # Only update non-password values
        _update_state_non_password_vars
    else
        update_state_file
    fi
    
    return 0
}

# Update only non-password variables in state (for pending password scenarios)
_update_state_non_password_vars() {
    [[ ! -f "$TBS_STATE_FILE" ]] && return
    
    local content
    content=$(_get_state_content) || return
    
    # Update only non-sensitive vars
    for key in DATABASE PHPVERSION STACK_MODE COMPOSE_PROJECT_NAME APP_ENV INSTALLATION_TYPE; do
        local value="${!key}"
        if echo "$content" | grep -q "^${key}="; then
            content=$(echo "$content" | sed "s|^${key}=.*|${key}=${value}|")
        fi
    done
    
    content=$(echo "$content" | sed "s|^LAST_UPDATED=.*|LAST_UPDATED=$(date +%s)|")
    _state_encode "$content" > "$TBS_STATE_FILE"
}

# Handle pending password updates after container starts
apply_pending_password_updates() {
    # Check if any pending updates
    [[ -z "${TBS_PENDING_ROOT_PASS_UPDATE:-}" && -z "${TBS_PENDING_USER_PASS_UPDATE:-}" ]] && return 0
    
    # Wait for DB to be healthy
    local max_wait=60
    local waited=0
    
    info_message "Waiting for database to be ready..."
    while ! is_service_running "dbhost" && [[ $waited -lt $max_wait ]]; do
        sleep 2
        waited=$((waited + 2))
    done
    
    # Check if DB actually started
    if ! is_service_running "dbhost"; then
        error_message "Database failed to start. Password update cancelled."
        error_message "Old password preserved in state file."
        # Don't update state - keep old password
        unset TBS_PENDING_ROOT_PASS_UPDATE TBS_PENDING_USER_PASS_UPDATE
        return 1
    fi
    
    # Additional wait for DB to be fully ready
    sleep 3
    
    local password_updated=false
    
    # Apply pending root password update
    if [[ -n "${TBS_PENDING_ROOT_PASS_UPDATE:-}" ]]; then
        info_message "Applying pending root password update..."
        if update_db_root_password "$TBS_PENDING_ROOT_PASS_UPDATE" "$MYSQL_ROOT_PASSWORD"; then
            password_updated=true
            unset TBS_PENDING_ROOT_PASS_UPDATE
        else
            error_message "Failed to update root password. Reverting .env..."
            sed_i "s|^MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=$TBS_PENDING_ROOT_PASS_UPDATE|" "$tbsPath/.env"
            MYSQL_ROOT_PASSWORD="$TBS_PENDING_ROOT_PASS_UPDATE"
            unset TBS_PENDING_ROOT_PASS_UPDATE
            # Don't update state - keep old values
            return 1
        fi
    fi
    
    # Apply pending user password update
    if [[ -n "${TBS_PENDING_USER_PASS_UPDATE:-}" ]]; then
        info_message "Applying pending user password update..."
        if update_db_user_password "$MYSQL_ROOT_PASSWORD" "${MYSQL_USER:-docker}" "$TBS_PENDING_USER_PASS_UPDATE" "$MYSQL_PASSWORD"; then
            password_updated=true
            unset TBS_PENDING_USER_PASS_UPDATE
        else
            error_message "Failed to update user password."
            unset TBS_PENDING_USER_PASS_UPDATE
        fi
    fi
    
    # Update state ONLY if password was successfully updated
    if [[ "$password_updated" == "true" ]]; then
        update_state_file
        green_message "✅ State file updated with new passwords."
    fi
}

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
        # Skip blanks/comments
        [[ "$line" =~ ^[[:space:]]*# || "$line" =~ ^[[:space:]]*$ ]] && continue

        # Remove 'export ' if present
        line="${line#export }"

        # Parse KEY=VALUE
        if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=[[:space:]]*(.*)[[:space:]]*$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Strip surrounding quotes (handles both " and ')
            if [[ "$value" =~ ^[\"\'](.*)[\"\']$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            printf -v "$key" '%s' "$value"
            [[ "$export_vars" == "true" ]] && export "$key"
        fi
    done < "$env_file"
}

# Cross-platform md5 hash (returns first 32 chars)
get_md5() {
    if command_exists md5sum; then
        echo "$1" | md5sum | cut -d' ' -f1
    elif command_exists md5; then
        echo "$1" | md5
    else
        # Fallback using checksum if available
        echo "$1" | cksum | cut -d' ' -f1
    fi
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
    if [[ "$OS_TYPE" == "windows" ]]; then
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

    # Normalize and validate the tbs.sh path before storing
    local normalized_path="$tbsFile"
    
    # On Windows, ensure path is in Unix format (/d/path)
    if [[ "$OS_TYPE" == "windows" ]]; then
        # Convert Windows path to Unix path if needed
        if [[ "$normalized_path" =~ ^[a-zA-Z]: ]]; then
            local drive="${normalized_path:0:1}"
            local path_part="${normalized_path:3}"
            normalized_path="/$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')$path_part"
            normalized_path="${normalized_path//\\//}"
        fi
        # Remove any double slashes
        normalized_path="${normalized_path//\/\///}"
    fi
    
    # Validate that the file exists
    if [[ ! -f "$normalized_path" ]]; then
        error_message "Cannot find tbs.sh at: $normalized_path"
        error_message "Current working directory: $(pwd)"
        error_message "BASH_SOURCE: ${BASH_SOURCE[0]}"
        return 1
    fi

    # Store normalized tbs.sh path in config file (updated on every run)
    echo "$normalized_path" > "$config_file"

    # Create smart wrapper that reads path from config (auto-updates when project moves)
    cat > "$wrapper_path" <<'WRAPPER'
#!/usr/bin/env bash
CONFIG_FILE="${HOME}/.tbs/config"
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ -f "$CONFIG_FILE" ]]; then
    TBS_SCRIPT="$(cat "$CONFIG_FILE" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    
    # On Windows, try to normalize the path if it doesn't exist
    if [[ ! -f "$TBS_SCRIPT" ]] && [[ "$(uname -s)" =~ ^(CYGWIN|MINGW|MSYS) ]]; then
        # Try converting Windows path format if needed
        if [[ "$TBS_SCRIPT" =~ ^[a-zA-Z]: ]]; then
            DRIVE="${TBS_SCRIPT:0:1}"
            PATH_PART="${TBS_SCRIPT:3}"
            TBS_SCRIPT="/$(printf '%s' "$DRIVE" | tr '[:upper:]' '[:lower:]')$PATH_PART"
            TBS_SCRIPT="${TBS_SCRIPT//\\//}"
        fi
        # Remove double slashes
        TBS_SCRIPT="${TBS_SCRIPT//\/\///}"
    fi
    
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

    # Remove old tbs() function definitions if they exist (they conflict with PATH-based command)
    # This ensures the PATH-based wrapper takes precedence over hardcoded function definitions
    if [[ -f "$shell_rc" ]] && grep -qE "^tbs\(\)|# Added by tbs\.sh for Turbo Stack CLI" "$shell_rc" 2>/dev/null; then
        # Create a backup before modifying (only if changes will be made)
        cp "$shell_rc" "${shell_rc}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        
        # Remove old function definitions using cross-platform sed_i function
        # Pattern 1: Remove function block from "tbs() {" to matching "}"
        sed_i '/^tbs() {/,/^}$/d' "$shell_rc" 2>/dev/null || true
        
        # Pattern 2: Remove comment header for old tbs installation
        sed_i '/^# Added by tbs\.sh for Turbo Stack CLI$/d' "$shell_rc" 2>/dev/null || true
        
        # Pattern 3: Remove any standalone lines with hardcoded old paths
        sed_i '/turbo-stack\/tbs\.sh/d' "$shell_rc" 2>/dev/null || true
        
        # Remove empty lines that might be left behind (max 2 consecutive)
        sed_i '/^$/N;/^\n$/d' "$shell_rc" 2>/dev/null || true
        
        needs_shell_restart=true
    fi

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
    if [[ "$OS_TYPE" == "windows" ]]; then
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
    if [[ "$OS_TYPE" == "linux" ]]; then
        local local_bin="$HOME/.local/bin"
        mkdir -p "$local_bin" 2>/dev/null || true
        ln -sf "$wrapper_path" "$local_bin/tbs" 2>/dev/null || true
    fi

    # macOS: symlink to /usr/local/bin if writable
    if [[ "$OS_TYPE" == "mac" && -w "/usr/local/bin" ]]; then
        ln -sf "$wrapper_path" "/usr/local/bin/tbs" 2>/dev/null || true
    fi

    # Show installation status and instructions
    echo ""
    if [[ "$needs_shell_restart" == "true" ]]; then
        green_message "✓ 'tbs' command installed successfully!"
        echo ""
        info_message "To use 'tbs' command in this terminal, run:"
        echo -e "  ${YELLOW}source $shell_rc${NC}"
        echo ""
        info_message "Or simply restart your terminal."
    else
        # PATH already in config, but check if it's in current session
        if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
            green_message "✓ 'tbs' command is installed!"
            echo ""
            info_message "To use 'tbs' command in this terminal, run:"
            echo -e "  ${YELLOW}source $shell_rc${NC}"
            echo ""
            info_message "Or restart your terminal."
            echo ""
            yellow_message "Note: You can also use the full path: $wrapper_path"
        # else
        #     green_message "✓ 'tbs' command is ready to use!"
        fi
    fi
    echo ""
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
    local dirs=("${VHOSTS_DIR}" "${NGINX_CONF_DIR}" "${NGINX_FPM_CONF_DIR}" "${SSL_DIR}")
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
        password=$(openssl rand -base64 48 2>/dev/null | tr -dc 'A-Za-z0-9!@$%^&*' | head -c "$length")
    fi
    
    # Fallback to /dev/urandom
    if [[ -z "$password" || ${#password} -lt $length ]]; then
        password=$(LC_ALL=C tr -dc 'A-Za-z0-9!@$%^&*' < /dev/urandom 2>/dev/null | head -c "$length" || true)
    fi
    
    # Ultimate fallback using $RANDOM (bash built-in)
    if [[ -z "$password" || ${#password} -lt $length ]]; then
        local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@$%^&*'
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
    [[ ! "$password" =~ [!@$%^\&*] ]] && needs_fix=true
    
    if [[ "$needs_fix" == "true" ]]; then
        # Add missing character types
        local upper='A' lower='z' number='7' special='!'
        if command_exists openssl; then
            upper=$(openssl rand -base64 4 2>/dev/null | tr -dc 'A-Z' | head -c 1 || echo 'A')
            lower=$(openssl rand -base64 4 2>/dev/null | tr -dc 'a-z' | head -c 1 || echo 'z')
            number=$(openssl rand -base64 4 2>/dev/null | tr -dc '0-9' | head -c 1 || echo '7')
        fi
        special=$(echo '!@$%^&*' | fold -w1 2>/dev/null | shuf 2>/dev/null | head -c 1 || echo '!')
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

# ============================================
# App Path Helper Functions
# ============================================

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
        if [[ "$HAS_JQ" == "true" ]]; then
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

# Generate Web Rules (Headers & Rewrites) for Nginx
_generate_web_rules_nginx() {
    local app_user="$1"
    local config_file=$(get_app_config_path "$app_user")
    [[ ! -f "$config_file" || "$HAS_JQ" != "true" ]] && return
    
    # Custom Header Rules
    local headers=$(jq -c '.web_rules.headers[]' "$config_file" 2>/dev/null)
    if [[ -n "$headers" ]]; then
        echo "    # Custom Header Rules"
        while read -r h; do
            [[ -z "$h" ]] && continue
            local name=$(echo "$h" | jq -r '.name')
            local val=$(echo "$h" | jq -r '.value' | sed 's/"/\\"/g')
            echo "    add_header \"$name\" \"$val\" always;"
        done <<< "$headers"
    fi
    
    # Custom Rewrite Rules
    local rewrites=$(jq -c '.web_rules.rewrites[]' "$config_file" 2>/dev/null)
    if [[ -n "$rewrites" ]]; then
        echo "    # Custom Rewrite Rules"
        while read -r r; do
            [[ -z "$r" ]] && continue
            local src=$(echo "$r" | jq -r '.source')
            local dst=$(echo "$r" | jq -r '.destination' | sed 's/"/\\"/g')
            local type=$(echo "$r" | jq -r '.type')
            local keep_q=$(echo "$r" | jq -r '.keep_query // true')
            local conds=$(echo "$r" | jq -c '.conditions // empty')
            
            # Handle query string discard
            [[ "$keep_q" == "false" ]] && [[ "$dst" != *"?"* ]] && dst="${dst}?"
            
            local rule_line=""
            if [[ "$type" == "301" ]]; then rule_line="rewrite \"$src\" \"$dst\" permanent;"
            elif [[ "$type" == "302" ]]; then rule_line="rewrite \"$src\" \"$dst\" redirect;"
            else rule_line="rewrite \"$src\" \"$dst\" last;"
            fi
            
            # Handle conditions (Supports one condition for now)
            if [[ -n "$conds" && "$conds" != "null" && "$conds" != "[]" ]]; then
                local c_type=$(echo "$conds" | jq -r '.[0].type')
                local c_op=$(echo "$conds" | jq -r '.[0].operator')
                local c_val=$(echo "$conds" | jq -r '.[0].value' | sed 's/"/\\"/g')
                local var=""
                case "$c_type" in
                    Host) var="\$http_host" ;;
                    URI) var="\$uri" ;;
                    "Query String") var="\$query_string" ;;
                esac
                
                if [[ -n "$var" ]]; then
                    local op_str="="
                    [[ "$c_op" == "!=" ]] && op_str="!="
                    [[ "$c_op" == "~" ]] && op_str="~"
                    [[ "$c_op" == "!~" ]] && op_str="!~"
                    echo "    if ($var $op_str \"$c_val\") {"
                    echo "        $rule_line"
                    echo "    }"
                else
                    echo "    $rule_line"
                fi
            else
                echo "    $rule_line"
            fi
        done <<< "$rewrites"
    fi
}

# Generate Web Rules (Headers & Rewrites) for Apache
_generate_web_rules_apache() {
    local app_user="$1"
    local config_file=$(get_app_config_path "$app_user")
    [[ ! -f "$config_file" || "$HAS_JQ" != "true" ]] && return
    
    # Custom Header Rules
    local headers=$(jq -c '.web_rules.headers[]' "$config_file" 2>/dev/null)
    if [[ -n "$headers" ]]; then
        echo "    # Custom Header Rules"
        while read -r h; do
            [[ -z "$h" ]] && continue
            local name=$(echo "$h" | jq -r '.name')
            local val=$(echo "$h" | jq -r '.value' | sed 's/"/\\"/g')
            echo "    Header set \"$name\" \"$val\""
        done <<< "$headers"
    fi
    
    # Custom Rewrite Rules
    local rewrites=$(jq -c '.web_rules.rewrites[]' "$config_file" 2>/dev/null)
    if [[ -n "$rewrites" ]]; then
        echo "    # Custom Rewrite Rules"
        echo "    RewriteEngine On"
        while read -r r; do
            [[ -z "$r" ]] && continue
            local src=$(echo "$r" | jq -r '.source')
            local dst=$(echo "$r" | jq -r '.destination' | sed 's/"/\\"/g')
            local type=$(echo "$r" | jq -r '.type')
            local keep_q=$(echo "$r" | jq -r '.keep_query // true')
            local conds=$(echo "$r" | jq -c '.conditions // empty')
            
            # Handle conditions
            if [[ -n "$conds" && "$conds" != "null" && "$conds" != "[]" ]]; then
                local c_type=$(echo "$conds" | jq -r '.[0].type')
                local c_op=$(echo "$conds" | jq -r '.[0].operator')
                local c_val=$(echo "$conds" | jq -r '.[0].value' | sed 's/"/\\"/g')
                local var=""
                case "$c_type" in
                    Host) var="%{HTTP_HOST}" ;;
                    URI) var="%{REQUEST_URI}" ;;
                    "Query String") var="%{QUERY_STRING}" ;;
                esac
                
                if [[ -n "$var" ]]; then
                    local flags=""
                    [[ "$c_op" == "!=" ]] && flags="!"
                    [[ "$c_op" == "~" ]] && flags="" # Regex is default
                    [[ "$c_op" == "!~" ]] && flags="!"
                    
                    if [[ "$c_op" == "=" ]]; then
                        echo "    RewriteCond $var =$c_val"
                    else
                        echo "    RewriteCond $var $flags$c_val"
                    fi
                fi
            fi
            
            local flags="L"
            [[ "$type" == "301" ]] && flags="R=301,L"
            [[ "$type" == "302" ]] && flags="R=302,L"
            [[ "$type" == "rewrite" ]] && flags="L,PT"
            [[ "$keep_q" == "false" ]] && flags="$flags,QSD"
            
            echo "    RewriteRule \"$src\" \"$dst\" [$flags]"
        done <<< "$rewrites"
    fi
}

# Generate Nginx and Apache configurations for an app
_generate_app_configs() {
    local app_user="$1"
    local domain="$2"
    local webroot="${3:-public_html}"
    
    local app_public_root="${APACHE_DOCUMENT_ROOT}/${APPLICATIONS_DIR_NAME}/${app_user}/${webroot}"
    
    # Apache config
    local vhost_file="${VHOSTS_DIR}/${domain}.conf"
    cat >"$vhost_file" <<EOF
<VirtualHost *:80>
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot $app_public_root
    Define APP_NAME $app_user
EOF
    _generate_web_rules_apache "$app_user" >> "$vhost_file"
    cat >>"$vhost_file" <<EOF
    Include /etc/apache2/sites-enabled/partials/app-common.inc
</VirtualHost>
<VirtualHost *:443>
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot $app_public_root
    Define APP_NAME $app_user
EOF
    _generate_web_rules_apache "$app_user" >> "$vhost_file"
    cat >>"$vhost_file" <<EOF
    Include /etc/apache2/sites-enabled/partials/app-common.inc
    SSLEngine on
    SSLCertificateFile /etc/apache2/ssl-sites/cert.pem
    SSLCertificateKeyFile /etc/apache2/ssl-sites/cert-key.pem
</VirtualHost>
EOF

    # Nginx config (Proxy)
    local nginx_file="${NGINX_CONF_DIR}/${domain}.conf"
    cat >"$nginx_file" <<EOF
server {
    listen 80;
    server_name $domain www.$domain;
    root $app_public_root;
EOF
    _generate_web_rules_nginx "$app_user" >> "$nginx_file"
    cat >>"$nginx_file" <<EOF
    index index.php index.html index.htm;
    include /etc/nginx/includes/common.conf;
    include /etc/nginx/includes/varnish-proxy.conf;
}
server {
    listen 443 ssl;
    server_name $domain www.$domain;
    root $app_public_root;
EOF
    _generate_web_rules_nginx "$app_user" >> "$nginx_file"
    cat >>"$nginx_file" <<EOF
    index index.php index.html index.htm;
    ssl_certificate /etc/nginx/ssl-sites/cert.pem;
    ssl_certificate_key /etc/nginx/ssl-sites/cert-key.pem;
    include /etc/nginx/includes/common.conf;
    include /etc/nginx/includes/varnish-proxy.conf;
}
EOF

    # Nginx-FPM config (Internal Backend)
    if [[ -n "$NGINX_FPM_CONF_DIR" ]]; then
        local fpm_nginx_file="${NGINX_FPM_CONF_DIR}/${domain}.conf"
        cat >"$fpm_nginx_file" <<EOF
server {
    listen 8080;
    server_name $domain www.$domain;
    root $app_public_root;
EOF
        _generate_web_rules_nginx "$app_user" >> "$fpm_nginx_file"
        cat >>"$fpm_nginx_file" <<EOF
    index index.php index.html index.htm;
    include /etc/nginx/includes/php-fpm.conf;
}
EOF
    fi
    
    # Fix SSL paths if custom certs exist
    if [[ -f "${SSL_DIR}/${domain}-cert.pem" ]]; then
        sed_i "s|cert.pem|${domain}-cert.pem|g" "$vhost_file"
        sed_i "s|cert-key.pem|${domain}-key.pem|g" "$vhost_file"
        sed_i "s|cert.pem|${domain}-cert.pem|g" "$nginx_file"
        sed_i "s|cert-key.pem|${domain}-key.pem|g" "$nginx_file"
        [[ -f "${NGINX_FPM_CONF_DIR}/${domain}.conf" ]] && {
            sed_i "s|cert.pem|${domain}-cert.pem|g" "${NGINX_FPM_CONF_DIR}/${domain}.conf"
            sed_i "s|cert-key.pem|${domain}-key.pem|g" "${NGINX_FPM_CONF_DIR}/${domain}.conf"
        }
    fi
}

# Set permissions for an app inside the container
_set_app_permissions() {
    local app_user="$1"
    local ssh_uid="$2"
    
    if is_service_running "$WEBSERVER_SERVICE"; then
        docker compose exec -T "$WEBSERVER_SERVICE" bash -c "
            if [[ -n \"$ssh_uid\" ]]; then
                groupadd -g $ssh_uid $app_user 2>/dev/null || true
                useradd -u $ssh_uid -g $ssh_uid -M -d /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user $app_user 2>/dev/null || true
                chown -R $ssh_uid:$ssh_uid /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user
            else
                chown -R www-data:www-data /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user
            fi
            find /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user -type d -exec chmod 755 {} \;
            find /var/www/html/${APPLICATIONS_DIR_NAME}/$app_user -type f -exec chmod 644 {} \;
        " 2>/dev/null
    fi
}

# Resolve input to app_user (accepts app_user or app_name)
resolve_app_user() {
    local input="$1"
    [[ -z "$input" ]] && return 1
    
    local config_file="$tbsPath/sites/apps/${input}.json"
    
    # If config exists with this name, it's already app_user
    if [[ -f "$config_file" ]]; then
        echo "$input"
        return 0
    fi
    
    # Check if app directory exists (fallback for apps without config)
    local app_dir="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$input"
    if [[ -d "$app_dir" ]]; then
        echo "$input"
        return 0
    fi
    
    # Otherwise search by app_name
    local found
    found=$(find_app_user_by_name "$input")
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
    "web_rules": {
        "headers": [],
        "rewrites": []
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
    
    if [[ "$HAS_JQ" == "true" ]]; then
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
    
    if [[ "$HAS_JQ" == "true" ]]; then
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
    # Use MYSQL_PWD to avoid password quoting issues
    local root_pass=$(get_state_value "MYSQL_ROOT_PASSWORD")
    [[ -z "$root_pass" ]] && root_pass="${MYSQL_ROOT_PASSWORD:-root}"
    
    # Detect client binary inside webserver container
    local client_bin="mysql"
    docker compose exec -T "$WEBSERVER_SERVICE" command -v mariadb >/dev/null 2>&1 && client_bin="mariadb"
    
    docker compose exec -T -e MYSQL_PWD="$root_pass" "$WEBSERVER_SERVICE" "$client_bin" -uroot -h dbhost "$@" 2>/dev/null
}

# Execute MySQL dump through webserver container
execute_mysqldump() {
    local database="$1"
    local output_file="$2"
    
    [[ -z "$database" ]] && { error_message "Database name required"; return 1; }
    [[ -z "$output_file" ]] && { error_message "Output file required"; return 1; }
    
    local root_pass=$(get_state_value "MYSQL_ROOT_PASSWORD")
    [[ -z "$root_pass" ]] && root_pass="${MYSQL_ROOT_PASSWORD:-root}"
    local dump_opts="--single-transaction --routines --triggers --events"
    
    # Detect dump binary inside webserver container
    local dump_bin="mysqldump"
    docker compose exec -T "$WEBSERVER_SERVICE" command -v mariadb-dump >/dev/null 2>&1 && dump_bin="mariadb-dump"
    
    # Ensure output directory exists
    mkdir -p "$(dirname "$output_file")" 2>/dev/null || true
    
    docker compose exec -T -e MYSQL_PWD="$root_pass" "$WEBSERVER_SERVICE" "$dump_bin" -uroot -h dbhost $dump_opts --databases "$database" >"$output_file" 2>/dev/null
}

# ============================================
# Database Helpers
# ============================================

# Helper: Select a database from list (returns selected db name in SELECTED_DB)
# Usage: _db_select_from_list db_list || return
_db_select_from_list() {
    local array_name=$1
    local prompt="${2:-Database}"
    SELECTED_DB=""
    
    local size
    eval "size=\${#$array_name[@]}"
    
    if [[ $size -eq 0 ]]; then
        error_message "No databases found"
        return 1
    fi
    
    echo "  Select database number:"
    read -p "  $prompt [1-$size]: " db_sel
    
    if [[ "$db_sel" =~ ^[0-9]+$ ]] && [[ $db_sel -ge 1 ]] && [[ $db_sel -le $size ]]; then
        eval "SELECTED_DB=\${$array_name[$((db_sel-1))]}"
        return 0
    else
        error_message "Invalid selection"
        return 1
    fi
}

# Helper: Update app config with jq (reduces repeated mktemp/mv pattern)
# Usage: _jq_update "config_file" "jq_expression"
_jq_update() {
    local cfg="$1" expr="$2"
    [[ -z "$cfg" || -z "$expr" ]] && return 1
    [[ "$HAS_JQ" == "true" ]] || { error_message "jq is required"; return 1; }
    [[ ! -f "$cfg" ]] && return 1
    local tmp
    tmp=$(mktemp) || return 1
    if jq "$expr" "$cfg" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$cfg"
        return 0
    else
        rm -f "$tmp"
        return 1
    fi
}

# Create a database
_db_create() {
    local db_name="$1"
    [[ -z "$db_name" ]] && { error_message "Database name required"; return 1; }
    
    # Validate database name (alphanumeric and underscore only)
    if [[ ! "$db_name" =~ ^[a-zA-Z0-9_]+$ ]]; then
        error_message "Invalid database name. Use only letters, numbers, and underscores."
        return 1
    fi
    
    if execute_mysql_command -e "CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
        green_message "Created database: $db_name"
        return 0
    else
        error_message "Failed to create database: $db_name"
        return 1
    fi
}

# Check if a database exists
_db_exists() {
    local db_name="$1"
    [[ -z "$db_name" ]] && return 1
    local result
    result=$(execute_mysql_command -N -B -e "SHOW DATABASES LIKE '$db_name';")
    [[ "$result" == "$db_name" ]]
}

# Check if a MySQL user exists
_db_user_exists() {
    local user="$1"
    [[ -z "$user" ]] && return 1
    local result
    result=$(execute_mysql_command -N -B -e "SELECT COUNT(*) FROM mysql.user WHERE user='$user';")
    [[ "$result" -gt 0 ]]
}

# Suggest a unique, app-scoped database name
_suggest_app_db_name() {
    local app_prefix="$1"
    [[ -z "$app_prefix" ]] && return 1
    local suffix
    suffix=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom 2>/dev/null | head -c 4)
    [[ -z "$suffix" || ${#suffix} -lt 4 ]] && suffix=$(printf "%04d" $((RANDOM%10000)))
    local candidate="${app_prefix}_${suffix}"
    if _db_exists "$candidate"; then
        candidate="${app_prefix}_$((RANDOM%9000+1000))"
    fi
    echo "$candidate"
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
    
    # Validate username (alphanumeric and underscore only, max 32 chars for MySQL)
    if [[ ! "$user" =~ ^[a-zA-Z0-9_]+$ ]] || [[ ${#user} -gt 32 ]]; then
        error_message "Invalid username. Use only letters, numbers, underscores (max 32 chars)."
        return 1
    fi
    
    # Escape single quotes in password for SQL
    local escaped_pass="${pass//\'/\'\'}" 
    
    if execute_mysql_command -e "CREATE USER IF NOT EXISTS '$user'@'%' IDENTIFIED BY '$escaped_pass'; GRANT ALL ON \`$db\`.* TO '$user'@'%'; FLUSH PRIVILEGES;"; then
        green_message "Created user: $user with access to $db"
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

    yellow_message "Reloading web servers..."
    
    # Reload Backend Webserver
    if [[ "$(docker compose ps -q "$WEBSERVER_SERVICE" 2>/dev/null)" ]]; then
        if [[ "$WEBSERVER_SERVICE" == "webserver-apache" ]]; then
            docker compose exec -T "$WEBSERVER_SERVICE" bash -c "service apache2 reload" 2>/dev/null || true
        else
            docker compose exec -T "$WEBSERVER_SERVICE" bash -c "kill -USR2 1" 2>/dev/null || true # Reload PHP-FPM
        fi
    fi

    # Reload Internal Nginx (Thunder Mode)
    if [[ "$(docker compose ps -q nginx-fpm 2>/dev/null)" ]]; then
        docker compose exec -T nginx-fpm nginx -s reload 2>/dev/null || true
    fi

    # Reload Frontend Proxies
    if [[ "$(docker compose ps -q reverse-proxy 2>/dev/null)" ]]; then
        docker compose exec -T reverse-proxy nginx -s reload 2>/dev/null || true
    fi
    if [[ "$(docker compose ps -q reverse-proxy-thunder 2>/dev/null)" ]]; then
        docker compose exec -T reverse-proxy-thunder nginx -s reload 2>/dev/null || true
    fi

    green_message "Web servers reloaded."
}

# Interactive password prompt for production security
# Returns 0 if password is strong, updates .env file
prompt_strong_password() {
    local var_name="$1"
    local display_name="$2"
    local current_val="${!var_name}"
    local min_length=15
    
    # Check if password is strong enough
    local is_weak=false
    [[ -z "$current_val" ]] && is_weak=true
    [[ ${#current_val} -lt $min_length ]] && is_weak=true
    [[ "$var_name" == "MYSQL_ROOT_PASSWORD" && "$current_val" == "root" ]] && is_weak=true
    [[ "$var_name" == "MYSQL_PASSWORD" && "$current_val" == "docker" ]] && is_weak=true
    [[ "$var_name" == "REDIS_PASSWORD" && "$current_val" == "redis" ]] && is_weak=true
    [[ "$var_name" == "TBS_ADMIN_PASSWORD" && "$current_val" == "tbsadmin123" ]] && is_weak=true
    
    # If password is strong, return success
    [[ "$is_weak" == "false" ]] && return 0
    
    # Show warning
    echo ""
    red_message "⚠️  $display_name: WEAK PASSWORD!"
    if [[ -n "$current_val" ]]; then
        echo -e "   Current: ${RED}$current_val${NC} (${#current_val} chars - minimum $min_length required)"
    else
        echo -e "   Current: ${RED}(empty)${NC}"
    fi
    
    # Generate strong suggestion
    local suggested_pass=$(generate_strong_password 20)
    echo -e "   Suggested: ${GREEN}$suggested_pass${NC}"
    
    # Loop until strong password is entered
    while true; do
        echo -ne "   Enter strong password (${YELLOW}Enter = use suggested${NC}): "
        read -r new_pass
        
        # Use suggested if empty
        if [[ -z "$new_pass" ]]; then
            new_pass="$suggested_pass"
            green_message "   ✓ Using suggested password"
        fi
        
        # Validate length
        if [[ ${#new_pass} -lt $min_length ]]; then
            red_message "   ✗ Password too short! Minimum $min_length characters required."
            suggested_pass=$(generate_strong_password 20)
            echo -e "   New suggestion: ${GREEN}$suggested_pass${NC}"
            continue
        fi
        
        # Password is strong, update .env
        export "$var_name"="$new_pass"
        if grep -q "^$var_name=" "$tbsPath/.env"; then
            sed_i "s|^$var_name=.*|$var_name=$new_pass|" "$tbsPath/.env"
        else
            echo "$var_name=$new_pass" >> "$tbsPath/.env"
        fi
        
        green_message "   ✓ $display_name updated!"
        return 0
    done
}

# Check production security - interactive prompts for weak passwords
check_production_security() {
    [[ "$APP_ENV" != "production" ]] && return 0
    
    local has_weak=false
    local min_length=15
    
    # Quick check if any password is weak
    [[ -z "$MYSQL_ROOT_PASSWORD" || ${#MYSQL_ROOT_PASSWORD} -lt $min_length || "$MYSQL_ROOT_PASSWORD" == "root" ]] && has_weak=true
    [[ -z "$MYSQL_PASSWORD" || ${#MYSQL_PASSWORD} -lt $min_length || "$MYSQL_PASSWORD" == "docker" ]] && has_weak=true
    [[ -z "$REDIS_PASSWORD" || ${#REDIS_PASSWORD} -lt $min_length || "$REDIS_PASSWORD" == "redis" ]] && has_weak=true
    [[ -n "$TBS_ADMIN_PASSWORD" && (${#TBS_ADMIN_PASSWORD} -lt $min_length || "$TBS_ADMIN_PASSWORD" == "tbsadmin123") ]] && has_weak=true
    
    if [[ "$has_weak" == "true" ]]; then
        echo ""
        blue_message "═══════════════════════════════════════════════════════════════"
        blue_message "🔐 PRODUCTION SECURITY CHECK"
        blue_message "═══════════════════════════════════════════════════════════════"
        yellow_message "Production mode requires strong passwords (min $min_length chars)"
        
        prompt_strong_password "MYSQL_ROOT_PASSWORD" "MySQL Root Password"
        prompt_strong_password "MYSQL_PASSWORD" "MySQL User Password"
        prompt_strong_password "REDIS_PASSWORD" "Redis Password"
        prompt_strong_password "TBS_ADMIN_PASSWORD" "TBS Admin Password"
        
        echo ""
        green_message "═══════════════════════════════════════════════════════════════"
        green_message "✅ All passwords are now secure!"
        green_message "═══════════════════════════════════════════════════════════════"
        yellow_message "💡 Passwords saved in .env - keep this file secure!"
        echo ""
    fi
    
    return 0
}

# Validate .env configuration before starting
validate_env_config() {
    local errors=0
    
    # Check if .env exists
    if [[ ! -f "$tbsPath/.env" ]]; then
        error_message ".env file not found!"
        info_message "Run: ./tbs.sh config"
        return 1
    fi
    
    # Load environment
    load_env_file "$tbsPath/.env"
    
    # Validate required variables
    local required_vars=(
        "COMPOSE_PROJECT_NAME"
        "PHPVERSION"
        "DATABASE"
        "STACK_MODE"
        "APP_ENV"
        "MYSQL_ROOT_PASSWORD"
        "MYSQL_DATABASE"
        "MYSQL_USER"
        "MYSQL_PASSWORD"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            error_message "Missing required variable: $var"
            ((errors++))
        fi
    done
    
    # Validate STACK_MODE
    if [[ -n "$STACK_MODE" && "$STACK_MODE" != "hybrid" && "$STACK_MODE" != "thunder" ]]; then
        error_message "Invalid STACK_MODE: $STACK_MODE (must be 'hybrid' or 'thunder')"
        ((errors++))
    fi
    
    # Validate APP_ENV
    if [[ -n "$APP_ENV" && "$APP_ENV" != "development" && "$APP_ENV" != "production" ]]; then
        error_message "Invalid APP_ENV: $APP_ENV (must be 'development' or 'production')"
        ((errors++))
    fi
    
    # Validate PHP version exists
    if [[ -n "$PHPVERSION" && ! -d "$tbsPath/bin/$PHPVERSION" ]]; then
        error_message "PHP version not found: $PHPVERSION"
        info_message "Available versions: $(ls -d $tbsPath/bin/php* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
        ((errors++))
    fi
    
    # Validate Database exists
    if [[ -n "$DATABASE" && ! -d "$tbsPath/bin/$DATABASE" ]]; then
        error_message "Database not found: $DATABASE"
        info_message "Available databases: $(ls -d $tbsPath/bin/mysql* $tbsPath/bin/mariadb* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
        ((errors++))
    fi
    
    # Return early if basic validation failed
    if [[ $errors -gt 0 ]]; then
        error_message "Configuration has $errors error(s). Please fix and try again."
        info_message "Run: ./tbs.sh config"
        return 1
    fi
    
    # Interactive production security check
    check_production_security
    
    return 0
}

# Ensure Docker is running
# Fix line endings in shell scripts and Docker files
# Prevents CRLF issues that cause container failures
# Cross-platform compatible (Windows, macOS, Linux)
fix_line_endings() {
    local fixed_count=0
    local checked_count=0
    
    # Check if dos2unix is available
    local use_dos2unix=false
    command -v dos2unix >/dev/null 2>&1 && use_dos2unix=true
    
    # Check if 'file' command is available (for detection)
    local has_file_cmd=false
    command -v file >/dev/null 2>&1 && has_file_cmd=true
    
    # Function to check if file has CRLF (multiple methods for compatibility)
    has_crlf() {
        local file="$1"
        
        # Method 1: Use 'file' command if available
        if [ "$has_file_cmd" = true ]; then
            if file "$file" 2>/dev/null | grep -q "CRLF\|with CR line terminators"; then
                return 0
            fi
        fi
        
        # Method 2: Check for \r in file (more reliable, works everywhere)
        if grep -q $'\r' "$file" 2>/dev/null; then
            return 0
        fi
        
        return 1
    }
    
    # Function to fix a single file
    fix_file() {
        local file="$1"
        checked_count=$((checked_count + 1))
        
        # Check if file has CRLF
        if has_crlf "$file"; then
            if [ "$use_dos2unix" = true ]; then
                dos2unix "$file" 2>/dev/null || sed_i 's/\r$//' "$file"
            else
                sed_i 's/\r$//' "$file"
            fi
            fixed_count=$((fixed_count + 1))
            return 0
        fi
        return 1
    }
    
    # Fix critical files that cause container failures
    local critical_files=(
        "bin/healthcheck.sh"
        "bin/nginx/entrypoint.sh"
        "bin/ssh/entrypoint.sh"
        "bin/php-entrypoint.sh"
        "bin/tbs-db-entrypoint.sh"
    )
    
    for file in "${critical_files[@]}"; do
        if [ -f "$tbsPath/$file" ]; then
            fix_file "$tbsPath/$file"
        fi
    done
    
    # Fix all shell scripts in bin directory
    while IFS= read -r -d '' file; do
        fix_file "$file"
    done < <(find "$tbsPath/bin" -type f \( -name "*.sh" -o -name "entrypoint.sh" \) -print0 2>/dev/null)
    
    # Show result if any files were fixed
    if [ $fixed_count -gt 0 ]; then
        yellow_message "Fixed line endings in $fixed_count file(s) to prevent container issues"
    fi
}

ensure_docker_running() {
    if ! docker info >/dev/null 2>&1; then
        yellow_message "Docker daemon is not running. Starting Docker daemon..."
        
        case "$OS_TYPE" in
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

    case "$OS_TYPE" in
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
    # sleep 1

    case "$OS_TYPE" in
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
        echo "   1. local (Select for Local PC/System)"
        info_message "    • Best for local development. Enables .localhost domains with trusted SSL (mkcert)."
        
        echo "   2. live  (Select for Live/Production Server)"
        info_message "    • Best for public servers. Uses Let's Encrypt for valid SSL on custom domains."
        yellow_message "    • NOTE: For custom domains, you MUST point the domain's DNS to this server's IP first."

        # Auto-detect default
        local default_index=1
        if [[ "$OS_TYPE" == "linux" ]]; then
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
            
            # Configure production passwords (interactive)
            check_production_security
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
    # Validate configuration first
    if ! validate_env_config; then
        exit 1
    fi
    
    # Check and handle config changes (password updates, DB version changes, etc.)
    if ! check_and_apply_config_changes; then
        error_message "Configuration check failed. Please resolve issues and try again."
        exit 1
    fi
    
    # Check if rebuild is required due to config changes
    local do_rebuild=false
    if [[ "${TBS_FORCE_REBUILD:-false}" == "true" ]]; then
        do_rebuild=true
        unset TBS_FORCE_REBUILD
    fi
    
    # Fix line endings before starting (prevents container failures)
    fix_line_endings
    
    # Check if Docker daemon is running
    ensure_docker_running

    # Build and start containers
    info_message "Starting Turbo Stack (${APP_ENV:-development} mode, ${STACK_MODE:-hybrid} stack)..."
    
    PROFILES=$(build_profiles)
    
    # Rebuild if required, otherwise just start
    if [[ "$do_rebuild" == "true" ]]; then
        yellow_message "Rebuilding containers due to configuration changes..."
        ALL_PROFILES=$(get_all_profiles)
        docker compose $ALL_PROFILES down --remove-orphans 2>/dev/null || true
        cleanup_stack_networks
        if ! docker compose $PROFILES up -d --build; then
            error_message "Failed to rebuild the Turbo Stack."
            exit 1
        fi
    else
        if ! docker compose $PROFILES up -d; then
            error_message "Failed to start the Turbo Stack."
            exit 1
        fi
    fi
    
    # Apply any pending password updates after containers are running
    if [[ -n "${TBS_PENDING_ROOT_PASS_UPDATE:-}" || -n "${TBS_PENDING_USER_PASS_UPDATE:-}" ]]; then
        apply_pending_password_updates
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
        echo "   8) Create Project (Laravel/WordPress/Blank)"
        echo "   9) Open App Code"
        echo "   10) App Configuration (varnish, webroot, perms)"

        echo -e "\n${BLUE}⚙️ Configuration & Tools${NC}"
        echo "   11) Configure Environment"
        echo "   12) System Info"
        echo "   13) Backup/Restore"
        
        echo -e "\n${BLUE}🔧 Shell & Tools${NC}"
        echo "   14) Container Shell"
        echo "   15) Mailpit | 16) phpMyAdmin | 17) Redis CLI"

        echo -e "\n   ${RED}0) Exit${NC}"
        
        echo ""
        read -p "Choice [0-17]: " choice

        local wait_needed=true
        case $choice in
            1) tbs start ;; 2) tbs stop ;; 3) tbs restart ;; 4) tbs build ;; 5) tbs status ;; 6) tbs logs ;;
            7) tbs app ;;
            8) echo ""; read -p "Type [laravel/wordpress/blank]: " t; t="${t:-blank}"; read -p "App name: " n; tbs create "$t" "$n" ;;
            9) tbs app code ;;
            10) tbs app config ;;
            11) tbs config ;; 12) tbs info ;;
            13) echo ""; echo "1) Backup  2) Restore"; read -p "Action: " a; [[ "$a" == "1" ]] && tbs backup || tbs restore ;;
            14) tbs shell ;; 15) tbs mail ;; 16) tbs pma ;; 17) tbs redis-cli ;;
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

    # Production security check - runs on every command except 'config', 'help', 'stop'
    if [[ "$APP_ENV" == "production" && ! "$1" =~ ^(config|help|--help|-h|stop)$ ]]; then
        check_production_security
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
        # Validate configuration first
        if ! validate_env_config; then
            exit 1
        fi
        
        # Check and handle config changes
        if ! check_and_apply_config_changes; then
            error_message "Configuration check failed. Please resolve issues and try again."
            exit 1
        fi
        
        # Check if rebuild is required
        local do_rebuild=false
        if [[ "${TBS_FORCE_REBUILD:-false}" == "true" ]]; then
            do_rebuild=true
            unset TBS_FORCE_REBUILD
        fi
        
        fix_line_endings
        ensure_docker_running
        
        PROFILES=$(build_profiles)
        ALL_PROFILES=$(get_all_profiles)
        docker compose $ALL_PROFILES down --remove-orphans
        cleanup_stack_networks
        
        if [[ "$do_rebuild" == "true" ]]; then
            yellow_message "Rebuilding containers due to configuration changes..."
            docker compose $PROFILES up -d --build
        else
            docker compose $PROFILES up -d
        fi
        
        # Apply any pending password updates
        if [[ -n "${TBS_PENDING_ROOT_PASS_UPDATE:-}" || -n "${TBS_PENDING_USER_PASS_UPDATE:-}" ]]; then
            apply_pending_password_updates
        fi
        
        green_message "Turbo Stack restarted."
        ;;

    # Rebuild & Start
    build)
        # Validate configuration first
        if ! validate_env_config; then
            exit 1
        fi
        
        # Check and handle config changes (especially DB version changes)
        if ! check_and_apply_config_changes; then
            error_message "Configuration check failed. Please resolve issues and try again."
            exit 1
        fi
        
        # Fix line endings before building (prevents container failures)
        fix_line_endings
        ensure_docker_running
        PROFILES=$(build_profiles)
        # Always tear down everything regardless of profile before rebuild
        ALL_PROFILES=$(get_all_profiles)
        docker compose $ALL_PROFILES down --remove-orphans
        cleanup_stack_networks
        docker compose $PROFILES up -d --build
        
        # Apply any pending password updates after rebuild
        if [[ -n "${TBS_PENDING_ROOT_PASS_UPDATE:-}" || -n "${TBS_PENDING_USER_PASS_UPDATE:-}" ]]; then
            apply_pending_password_updates
        fi
        
        # Update state file after successful build
        update_state_file
        
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
                local config_file=$(get_app_config_path "$u")
                
                local n="$u" d="N/A" icons=""
                
                if [[ -f "$config_file" && "$HAS_JQ" == "true" ]]; then
                    # Read all needed values in one jq call for performance
                    local vals=$(jq -r '[.name, .primary_domain, .database.created, .ssh.enabled, .varnish] | @tsv' "$config_file" 2>/dev/null)
                    if [[ -n "$vals" ]]; then
                        IFS=$'\t' read -r j_name j_domain j_db j_ssh j_varnish <<< "$vals"
                        [[ -n "$j_name" && "$j_name" != "null" ]] && n="$j_name"
                        [[ -n "$j_domain" && "$j_domain" != "null" ]] && d="$j_domain"
                        [[ "$j_db" == "true" ]] && icons+="💾"
                        [[ "$j_ssh" == "true" ]] && icons+="🔑"
                        [[ "$j_varnish" == "false" ]] && icons+="⚡"
                    fi
                else
                    # Fallback if jq is missing
                    n=$(get_app_config "$u" "name"); [[ -z "$n" || "$n" == "null" ]] && n="$u"
                    d=$(get_app_config "$u" "primary_domain"); [[ -z "$d" || "$d" == "null" ]] && d="N/A"
                    [[ "$(get_app_config "$u" "database.created")" == "true" ]] && icons+="💾"
                    [[ "$(get_app_config "$u" "ssh.enabled")" == "true" ]] && icons+="🔑"
                    [[ "$(get_app_config "$u" "varnish")" == "false" ]] && icons+="⚡"
                fi
                
                printf "║  ${CYAN}%2d${NC}) %-18s ${GREEN}%-22s${NC} %s\n" "$i" "$u" "$d" "$icons"
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

        # Backup a specific app
        _app_backup() {
            local app_user="$1"
            local backup_dir="$tbsPath/data/backup"
            mkdir -p "$backup_dir"
            local timestamp=$(date +"%Y%m%d%H%M%S")
            local backup_file="$backup_dir/app_backup_${app_user}_$timestamp.tgz"

            info_message "Backing up app '$app_user' to $(basename "$backup_file")..."
            
            # Check if required containers are running
            if ! check_containers_running true true; then
                return 1
            fi

            # Create temporary directories
            local temp_sql_dir="$backup_dir/sql_$app_user"
            local temp_app_dir="$backup_dir/app_$app_user"
            rm -rf "$temp_sql_dir" "$temp_app_dir"
            mkdir -p "$temp_sql_dir" "$temp_app_dir"

            # Backup databases
            local dbs=()
            while IFS= read -r line; do [[ -n "$line" ]] && dbs+=("$line"); done < <(_app_get_databases "$app_user")
            
            local db_count=0
            for db in "${dbs[@]}"; do
                local sql_file="$temp_sql_dir/db_backup_$db.sql"
                info_message "  Backing up database: $db..."
                if execute_mysqldump "$db" "$sql_file"; then
                    ((db_count++))
                else
                    yellow_message "  ⚠️  Failed to backup database: $db"
                fi
            done

            # Backup files
            local app_path="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_user"
            if [[ -d "$app_path" ]]; then
                info_message "  Backing up application files..."
                cp -a "$app_path/." "$temp_app_dir/" 2>/dev/null || cp -r "$app_path/." "$temp_app_dir/" 2>/dev/null
            else
                error_message "Application directory not found: $app_path"
                rm -rf "$temp_sql_dir" "$temp_app_dir"
                return 1
            fi

            # Create archive
            if tar -czf "$backup_file" -C "$backup_dir" "sql_$app_user" "app_$app_user" 2>/dev/null; then
                green_message "✅ App backup completed!"
                echo "   File: $(basename "$backup_file")"
                echo "   Databases: $db_count"
            else
                error_message "Failed to create backup archive."
            fi

            rm -rf "$temp_sql_dir" "$temp_app_dir"
        }

        # Restore a specific app
        _app_restore() {
            local app_user="$1"
            local backup_dir="$tbsPath/data/backup"
            
            local backup_files=($(ls -t "$backup_dir/app_backup_${app_user}_"*.tgz 2>/dev/null))
            if [[ ${#backup_files[@]} -eq 0 ]]; then
                error_message "No backups found for app: $app_user"
                return 1
            fi

            echo "Available backups for $app_user:"
            for i in "${!backup_files[@]}"; do
                echo "$((i + 1)). $(basename "${backup_files[$i]}")"
            done

            read -p "Choose a backup number to restore: " backup_num
            if [[ ! "$backup_num" =~ ^[0-9]+$ ]] || [[ "$backup_num" -lt 1 ]] || [[ "$backup_num" -gt "${#backup_files[@]}" ]]; then
                error_message "Invalid selection."
                return 1
            fi
            
            local selected_backup="${backup_files[$((backup_num - 1))]}"
            info_message "Restoring app '$app_user' from $(basename "$selected_backup")..."

            if ! check_containers_running true true; then return 1; fi

            local temp_restore_dir="$backup_dir/restore_${app_user}_temp"
            rm -rf "$temp_restore_dir" && mkdir -p "$temp_restore_dir"

            if ! tar -xzf "$selected_backup" -C "$temp_restore_dir" 2>/dev/null; then
                error_message "Failed to extract backup."
                rm -rf "$temp_restore_dir"
                return 1
            fi

            # Restore Databases
            local sql_dir="$temp_restore_dir/sql_$app_user"
            if [[ -d "$sql_dir" ]]; then
                for sql_file in "$sql_dir"/*.sql; do
                    if [[ -f "$sql_file" ]]; then
                        local db_name=$(basename "$sql_file" | sed 's/db_backup_//;s/\.sql//')
                        info_message "  Restoring database: $db_name..."
                        cat "$sql_file" | execute_mysql_command >/dev/null 2>&1 || yellow_message "  ⚠️  Failed: $db_name"
                    fi
                done
            fi

            # Restore Files
            local app_data_dir="$temp_restore_dir/app_$app_user"
            if [[ -d "$app_data_dir" ]]; then
                info_message "  Restoring application files..."
                local target_path="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/$app_user"
                mkdir -p "$target_path"
                cp -a "$app_data_dir/." "$target_path/" 2>/dev/null || cp -R "$app_data_dir/." "$target_path/" 2>/dev/null
            fi

            rm -rf "$temp_restore_dir"
            green_message "✅ App restore completed!"
            info_message "Run 'tbs app sync' if needed."
        }
        
        # Create database for app (supports multiple databases)
        _app_db_create() {
            local app_user="$1"
            
            is_service_running "dbhost" || { error_message "MySQL not running. Run: tbs start"; return 1; }
            
            local app_prefix="${app_user//-/_}"
            local db_name=""
            local default_name=$(_suggest_app_db_name "$app_prefix")

            yellow_message "  Database name and DB user will be the same."

            while true; do
                read -p "Database name [default: $default_name]: " input_db
                if [[ -z "$input_db" ]]; then
                    db_name="$default_name"
                else
                    if [[ ! "$input_db" =~ ^${app_prefix}_[A-Za-z0-9]+$ ]]; then
                        db_name="${app_prefix}_$input_db"
                    else
                        db_name="$input_db"
                    fi
                fi

                if _db_exists "$db_name"; then
                    error_message "Database '$db_name' already exists. Pick another name."
                    default_name=$(_suggest_app_db_name "$app_prefix")
                    continue
                fi
                if _db_user_exists "$db_name"; then
                    error_message "MySQL user '$db_name' already exists. Choose a different database name."
                    default_name=$(_suggest_app_db_name "$app_prefix")
                    continue
                fi
                break
            done
            
            local db_user="$db_name"

            local suggested_pass=$(generate_strong_password 16)
            echo -e "  Auto password: ${CYAN}$suggested_pass${NC}"
            read -p "Password (Enter=auto): " db_pass
            db_pass="${db_pass:-$suggested_pass}"
            
            _db_create "$db_name" && _db_create_user "$db_user" "$db_pass" "$db_name"
            
            # Add to databases array (supports multiple DBs per app)
            [[ "$HAS_JQ" == "true" ]] && {
                local cfg=$(get_app_config_path "$app_user")
                local tmp=$(mktemp)
                local new_db='{"name":"'"$db_name"'","user":"'"$db_user"'","password":"'"$db_pass"'","host":"dbhost","created":true}'
                # Check if databases array exists, if not create it
                if jq -e '.databases' "$cfg" >/dev/null 2>&1; then
                    jq '.databases += ['"$new_db"']' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
                else
                    jq '.databases = ['"$new_db"']' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
                fi
                # Also update legacy .database field for backward compatibility
                tmp=$(mktemp)
                jq '.database='"$new_db" "$cfg" > "$tmp" && mv "$tmp" "$cfg"
            }
            
            echo ""
            green_message "✅ Database Created!"
            echo "  Database: $db_name"
            echo "  Username: $db_user"  
            echo "  Password: $db_pass"
            echo "  Host: dbhost (container) / localhost:${HOST_MACHINE_MYSQL_PORT:-3306} (host)"
            echo ""
        }
        
        # Get all databases for an app (from config + auto-detect by prefix)
        _app_get_databases() {
            local app_user="$1"
            local app_prefix="${app_user//-/_}"
            local cfg=$(get_app_config_path "$app_user")
            local dbs=()
            
            # Get from config databases array
            if [[ "$HAS_JQ" == "true" ]] && [[ -f "$cfg" ]]; then
                while IFS= read -r db; do
                    [[ -n "$db" && "$db" != "null" ]] && dbs+=("$db")
                done < <(jq -r '.databases[]?.name // empty' "$cfg" 2>/dev/null)
            fi
            
            # Also auto-detect databases with app prefix from MySQL
            local mysql_dbs
            mysql_dbs=$(execute_mysql_command -N -B -e "SHOW DATABASES LIKE '${app_prefix}%';" 2>/dev/null | grep -v "^#" || true)
            while IFS= read -r db; do
                [[ -z "$db" ]] && continue
                # Check if already in array
                local found=false
                for existing in "${dbs[@]}"; do [[ "$existing" == "$db" ]] && found=true && break; done
                [[ "$found" == "false" ]] && dbs+=("$db")
            done <<< "$mysql_dbs"
            
            printf '%s\n' "${dbs[@]}"
        }
        
        # Get database info from config
        _app_get_db_info() {
            local app_user="$1"
            local db_name="$2"
            local field="$3"
            local cfg=$(get_app_config_path "$app_user")
            
            if [[ "$HAS_JQ" == "true" ]] && [[ -f "$cfg" ]]; then
                jq -r '.databases[]? | select(.name=="'"$db_name"'") | .'"$field"' // empty' "$cfg" 2>/dev/null
            fi
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
                echo "  4) 🌍 Domains              9) 🌐 Web Rules"
                echo "  5) 🔑 SSH/SFTP            10) 📦 Backup/Restore"
                echo "  11) 🗑️  Delete"
                echo "  0) ↩️  Back"
                echo ""
                read -p "Select [0-11]: " choice
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
                    9) tbs app rules "$SELECTED_APP" ;;
                    10) echo ""; echo "  1) Backup App  2) Restore App"; read -p "  Action: " ba
                       [[ "$ba" == "1" ]] && _app_backup "$SELECTED_APP"
                       [[ "$ba" == "2" ]] && _app_restore "$SELECTED_APP" ;;
                    11) tbs app rm "$SELECTED_APP"; return 0 ;;
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
            local uid_hash=$(get_md5 "$app_user$(date +%s)" | tr -dc '0-9' | head -c 4)
            local ssh_uid=$((2000 + ${uid_hash:-1}))
            
            [[ -z "$domain" ]] && domain="${app_user}.localhost"
            
            # Check if domain already exists
            if [[ -f "${VHOSTS_DIR}/${domain}.conf" ]]; then
                error_message "Domain '$domain' is already in use by another app."
                return 1
            fi

            info_message "Creating: $name → $app_user"
            
            # Generate configurations
            _generate_app_configs "$app_user" "$domain" "public_html"
            
            local vhost_file="${VHOSTS_DIR}/${domain}.conf"
            local nginx_file="${NGINX_CONF_DIR}/${domain}.conf"

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
            [[ "$HAS_JQ" == "true" ]] && {
                local tmp=$(mktemp)
                jq ".ssh={\"enabled\":true,\"username\":\"$app_user\",\"password\":\"$ssh_pass\",\"port\":${HOST_MACHINE_SSH_PORT:-2244},\"uid\":$ssh_uid,\"gid\":$ssh_uid}" "$config_file" > "$tmp" && mv "$tmp" "$config_file"
            }
            
            # Set permissions in container
            _set_app_permissions "$app_user" "$ssh_uid"
            
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
            rm -f "${VHOSTS_DIR}/${domain}.conf" "${NGINX_CONF_DIR}/${domain}.conf" "${NGINX_FPM_CONF_DIR}/${domain}.conf"
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
        
        # tbs app db [app] - Database management (supports multiple databases)
        db|database)
            _app_get "$app_arg1" || return 1
            local app_user="$SELECTED_APP"
            local app_prefix="${app_user//-/_}"
            local cfg=$(get_app_config_path "$app_user")
            
            is_service_running "dbhost" || { error_message "MySQL not running"; return 1; }
            
            while true; do
                _app_header "$app_user" "Database Management"
                
                # Get all databases for this app
                local db_list=()
                while IFS= read -r line; do
                    [[ -n "$line" ]] && db_list+=("$line")
                done < <(_app_get_databases "$app_user")
                
                if [[ ${#db_list[@]} -gt 0 ]]; then
                    echo -e "  ${CYAN}App Databases (prefix: ${app_prefix}_):${NC}"
                    for i in "${!db_list[@]}"; do
                        local db="${db_list[$i]}"
                        local db_user_info=$(_app_get_db_info "$app_user" "$db" "user")
                        echo "    $((i+1))) $db (user: ${db_user_info:-$db})"
                    done
                else
                    yellow_message "No databases found for this app"
                fi
                echo ""
                echo "  1) Create Database    4) Import SQL"
                echo "  2) Show Credentials   5) Export SQL"
                echo "  3) Reset Password     6) Delete Database"
                echo "  0) Back"
                echo ""
                read -p "Select [0-6]: " choice
                
                case "$choice" in
                    1) _app_db_create "$app_user" ;;
                    2) # Show credentials
                       _db_select_from_list db_list && {
                           local db_pass=$(_app_get_db_info "$app_user" "$SELECTED_DB" "password")
                           local db_user=$(_app_get_db_info "$app_user" "$SELECTED_DB" "user")
                           echo ""
                           echo "  Database: $SELECTED_DB"
                           echo "  Username: ${db_user:-$SELECTED_DB}"
                           [[ -n "$db_pass" ]] && echo "  Password: $db_pass" || yellow_message "  Password: (not in config)"
                           echo "  Host: dbhost / localhost:${HOST_MACHINE_MYSQL_PORT:-3306}"
                       }
                       ;;
                    3) # Reset password
                       _db_select_from_list db_list && {
                           local db_user=$(_app_get_db_info "$app_user" "$SELECTED_DB" "user")
                           [[ -z "$db_user" ]] && db_user="$SELECTED_DB"
                           local new_pass=$(generate_strong_password 16)
                           echo -e "  Auto: ${CYAN}$new_pass${NC}"
                           read -p "New password (Enter=auto): " input_pass
                           new_pass="${input_pass:-$new_pass}"
                           execute_mysql_command -e "ALTER USER '$db_user'@'%' IDENTIFIED BY '$new_pass'; FLUSH PRIVILEGES;"
                           _jq_update "$cfg" '(.databases[] | select(.name=="'"$SELECTED_DB"'")).password = "'"$new_pass"'"'
                           _jq_update "$cfg" 'if .database.name == "'"$SELECTED_DB"'" then .database.password = "'"$new_pass"'" else . end'
                           green_message "Password updated: $new_pass"
                       }
                       ;;
                    4) # Import
                       [[ ${#db_list[@]} -eq 0 ]] && { error_message "Create a database first"; } || {
                           _db_select_from_list db_list && {
                               read -p "SQL file path: " sql_file
                               _db_import "$SELECTED_DB" "$sql_file"
                           }
                       }
                       ;;
                    5) # Export
                       _db_select_from_list db_list && {
                           local out="$tbsPath/data/backup/${SELECTED_DB}_$(date +%Y%m%d_%H%M%S).sql"
                           _db_export "$SELECTED_DB" "$out"
                       }
                       ;;
                    6) # Delete
                       _db_select_from_list db_list "Delete" && {
                           local db_user=$(_app_get_db_info "$app_user" "$SELECTED_DB" "user")
                           read -p "Type '$SELECTED_DB' to confirm: " confirm
                           [[ "$confirm" == "$SELECTED_DB" ]] && {
                               _db_drop "$SELECTED_DB"
                               [[ -n "$db_user" ]] && _db_drop_user "$db_user"
                               _jq_update "$cfg" 'del(.databases[] | select(.name=="'"$SELECTED_DB"'"))'
                               _jq_update "$cfg" 'if .database.name == "'"$SELECTED_DB"'" then .database={"name":"","user":"","password":"","created":false} else . end'
                               green_message "Database '$SELECTED_DB' deleted!"
                           } || info_message "Cancelled"
                       }
                       ;;
                    0) return 0 ;;
                    *) error_message "Invalid option" ;;
                esac
                echo ""
                read -p "Press Enter..."
            done
            ;;
        
        # tbs app ssh [app] - SSH management
        ssh|sftp)
            _app_get "$app_arg1" || return 1
            local app_user="$SELECTED_APP"
            local ssh_file="$tbsPath/sites/ssh/${app_user}.json"
            
            while true; do
                local ssh_enabled=$(get_app_config "$app_user" "ssh.enabled")
                _app_header "$app_user" "SSH/SFTP"
                echo -e "  Status: $([[ "$ssh_enabled" == "true" ]] && echo "${GREEN}Enabled${NC}" || echo "${RED}Disabled${NC}")"
                echo ""
                echo "  1) Show Credentials    3) Reset Password"
                echo "  2) Enable SSH          4) Disable SSH"
                echo "  0) Back"
                echo ""
                read -p "Select [0-4]: " choice
                
                case "$choice" in
                    1) [[ "$ssh_enabled" != "true" ]] && { yellow_message "SSH not enabled"; } || {
                       [[ "$HAS_JQ" == "true" ]] && {
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
                       [[ -z "$uid" || "$uid" == "null" ]] && { local h=$(get_md5 "$app_user$(date +%s)" | tr -dc '0-9' | head -c 4); uid=$((2000 + ${h:-1})); }
                       mkdir -p "$tbsPath/sites/ssh"
                       echo "{\"app_user\":\"$app_user\",\"username\":\"$app_user\",\"password\":\"$pass\",\"enabled\":true,\"uid\":$uid,\"gid\":$uid}" > "$ssh_file"
                       [[ "$HAS_JQ" == "true" ]] && { local cfg=$(get_app_config_path "$app_user"); local tmp=$(mktemp); jq ".ssh={\"enabled\":true,\"username\":\"$app_user\",\"password\":\"$pass\",\"port\":${HOST_MACHINE_SSH_PORT:-2244},\"uid\":$uid,\"gid\":$uid}" "$cfg" > "$tmp" && mv "$tmp" "$cfg"; }
                       green_message "✅ SSH Enabled! Pass: $pass"
                       ;;
                    3) local pass=$(generate_strong_password 22)
                       [[ "$HAS_JQ" == "true" ]] && [[ -f "$ssh_file" ]] && { local tmp=$(mktemp); jq ".password=\"$pass\"|.enabled=true" "$ssh_file" > "$tmp" && mv "$tmp" "$ssh_file"; }
                       [[ "$HAS_JQ" == "true" ]] && { local cfg=$(get_app_config_path "$app_user"); local tmp=$(mktemp); jq ".ssh.password=\"$pass\"|.ssh.enabled=true" "$cfg" > "$tmp" && mv "$tmp" "$cfg"; }
                       green_message "✅ New password: $pass"
                       ;;
                    4) [[ "$HAS_JQ" == "true" ]] && [[ -f "$ssh_file" ]] && { local tmp=$(mktemp); jq ".enabled=false" "$ssh_file" > "$tmp" && mv "$tmp" "$ssh_file"; }
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
            local cfg=$(get_app_config_path "$app_user")
            
            while true; do
                _app_header "$app_user" "Domains"
                echo "  Current domains:"
                [[ "$HAS_JQ" == "true" ]] && jq -r '.domains[]? // empty' "$cfg" 2>/dev/null | while read d; do
                    local p=$(get_app_config "$app_user" "primary_domain")
                    [[ "$d" == "$p" ]] && echo "    * $d (primary)" || echo "    - $d"
                done
                echo ""
                echo "  1) Add Domain"
                echo "  2) Remove Domain"
                echo "  0) Back"
                echo ""
                read -p "Select [0-2]: " choice
                
                case "$choice" in
                    1) read -p "New domain: " new_dom
                       [[ -n "$new_dom" ]] && {
                           local primary=$(get_app_config "$app_user" "primary_domain")
                           [[ -f "${VHOSTS_DIR}/${primary}.conf" ]] && sed "s/$primary/$new_dom/g" "${VHOSTS_DIR}/${primary}.conf" > "${VHOSTS_DIR}/${new_dom}.conf"
                           [[ -f "${NGINX_CONF_DIR}/${primary}.conf" ]] && sed "s/$primary/$new_dom/g" "${NGINX_CONF_DIR}/${primary}.conf" > "${NGINX_CONF_DIR}/${new_dom}.conf"
                           [[ -f "${NGINX_FPM_CONF_DIR}/${primary}.conf" ]] && sed "s/$primary/$new_dom/g" "${NGINX_FPM_CONF_DIR}/${primary}.conf" > "${NGINX_FPM_CONF_DIR}/${new_dom}.conf"
                           _jq_update "$cfg" '.domains+=["'"$new_dom"'"]'
                           generate_ssl_certificates "$new_dom" "${VHOSTS_DIR}/${new_dom}.conf" "${NGINX_CONF_DIR}/${new_dom}.conf" 2>/dev/null || true
                           reload_webservers
                           green_message "Domain added: $new_dom"
                       }
                       ;;
                    2) read -p "Domain to remove: " rem_dom
                       local primary=$(get_app_config "$app_user" "primary_domain")
                       [[ "$rem_dom" == "$primary" ]] && { error_message "Cannot remove primary"; } || {
                           rm -f "${VHOSTS_DIR}/${rem_dom}.conf" "${NGINX_CONF_DIR}/${rem_dom}.conf" "${NGINX_FPM_CONF_DIR}/${rem_dom}.conf"
                           _jq_update "$cfg" '.domains-=["'"$rem_dom"'"]'
                           reload_webservers
                           green_message "Domain removed"
                       }
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
            local cfg=$(get_app_config_path "$app_user")
            
            while true; do
                _app_header "$app_user" "SSL Certificates"
                
                # Get all domains
                local domains=()
                if [[ "$HAS_JQ" == "true" ]]; then
                    while IFS= read -r line; do
                        [[ -n "$line" ]] && domains+=("$line")
                    done < <(jq -r '.domains[]? // empty' "$cfg" 2>/dev/null)
                fi
                [[ ${#domains[@]} -eq 0 ]] && domains=("$(get_app_config "$app_user" "primary_domain")")
                
                echo "  App Domains:"
                for i in "${!domains[@]}"; do
                    local d="${domains[$i]}"
                    [[ -z "$d" || "$d" == "null" ]] && continue
                    local cert="$ssl_dir/${d}-cert.pem"
                    [[ -f "$cert" ]] && echo -e "    $((i+1))) $d ${GREEN}[OK]${NC}" || echo -e "    $((i+1))) $d ${YELLOW}[NO]${NC}"
                done
                echo ""
                echo "  1) Generate SSL for ALL"
                echo "  2) Generate SSL for specific domain"
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

        # tbs app rules [app] [action] [args] - Web Rules (Headers & Rewrites)
        rules|webrules)
            _app_get "$app_arg1" || return 1
            local app_user="$SELECTED_APP"
            local sub_action="$app_arg2"
            local cfg=$(get_app_config_path "$app_user")

            # Ensure web_rules exists in config
            if [[ "$HAS_JQ" == "true" ]]; then
                local tmp=$(mktemp)
                if ! jq -e '.web_rules' "$cfg" >/dev/null 2>&1; then
                    jq '.web_rules = {"headers":[], "rewrites":[]}' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
                else
                    # Ensure sub-keys exist
                    jq 'if .web_rules.headers == null then .web_rules.headers = [] else . end | 
                        if .web_rules.rewrites == null then .web_rules.rewrites = [] else . end' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
                fi
                rm -f "$tmp" 2>/dev/null
            fi

            _rules_list() {
                _app_header "$app_user" "🌐 Web Rules"
                echo "  Header Rules:"
                local headers=$(jq -c '.web_rules.headers[]' "$cfg" 2>/dev/null)
                if [[ -z "$headers" ]]; then
                    echo "    (None)"
                else
                    local i=1
                    while read -r h; do
                        local name=$(echo "$h" | jq -r '.name')
                        local val=$(echo "$h" | jq -r '.value')
                        printf "    %d) %-20s : %s\n" "$i" "$name" "$val"
                        ((i++))
                    done <<< "$headers"
                fi
                echo ""
                echo "  Rewrite Rules:"
                local rewrites=$(jq -c '.web_rules.rewrites[]' "$cfg" 2>/dev/null)
                if [[ -z "$rewrites" ]]; then
                    echo "    (None)"
                else
                    local i=1
                    while read -r r; do
                        local src=$(echo "$r" | jq -r '.source')
                        local dst=$(echo "$r" | jq -r '.destination')
                        local type=$(echo "$r" | jq -r '.type')
                        printf "    %d) %-20s -> %-20s [%s]\n" "$i" "$src" "$dst" "$type"
                        ((i++))
                    done <<< "$rewrites"
                fi
                echo ""
            }

            if [[ -n "$sub_action" ]]; then
                case "$sub_action" in
                    list) _rules_list ;;
                    add-header)
                        local name="$app_arg3"
                        local value="$4"
                        [[ -z "$name" || -z "$value" ]] && { error_message "Usage: tbs app rules $app_user add-header <name> <value>"; return 1; }
                        local new_h=$(jq -n --arg n "$name" --arg v "$value" '{name: $n, value: $v}')
                        local tmp=$(mktemp)
                        jq ".web_rules.headers += [$new_h]" "$cfg" > "$tmp" && mv "$tmp" "$cfg"
                        green_message "✅ Header added. Apply with: tbs app sync $app_user" ;;
                    rm-header)
                        local idx="$app_arg3"
                        [[ -z "$idx" ]] && { error_message "Usage: tbs app rules $app_user rm-header <index>"; return 1; }
                        local tmp=$(mktemp)
                        jq "del(.web_rules.headers[$((idx-1))])" "$cfg" > "$tmp" && mv "$tmp" "$cfg"
                        green_message "✅ Header removed. Apply with: tbs app sync $app_user" ;;
                    add-rewrite)
                        local src="$app_arg3"
                        local dst="$4"
                        local type="${5:-301}"
                        local keep_q="${6:-true}"
                        local cond_json="${7:-null}"
                        [[ -z "$src" || -z "$dst" ]] && { error_message "Usage: tbs app rules $app_user add-rewrite <source> <destination> [type] [keep_query] [conditions_json]"; return 1; }
                        local new_r=$(jq -n --arg s "$src" --arg d "$dst" --arg t "$type" --arg k "$keep_q" --argjson c "$cond_json" \
                            '{source: $s, destination: $d, type: $t, keep_query: ($k == "true"), conditions: $c}')
                        local tmp=$(mktemp)
                        jq ".web_rules.rewrites += [$new_r]" "$cfg" > "$tmp" && mv "$tmp" "$cfg"
                        green_message "✅ Rewrite rule added. Apply with: tbs app sync $app_user" ;;
                    rm-rewrite)
                        local idx="$app_arg3"
                        [[ -z "$idx" ]] && { error_message "Usage: tbs app rules $app_user rm-rewrite <index>"; return 1; }
                        local tmp=$(mktemp)
                        jq "del(.web_rules.rewrites[$((idx-1))])" "$cfg" > "$tmp" && mv "$tmp" "$cfg"
                        green_message "✅ Rewrite rule removed. Apply with: tbs app sync $app_user" ;;
                    *) error_message "Unknown rules action: $sub_action" ;;
                esac
                return 0
            fi

            while true; do
                _rules_list
                echo "  1) Add Header Rule      3) Add Redirect/Rewrite Rule"
                echo "  2) Remove Header Rule   4) Remove Redirect/Rewrite Rule"
                echo "  5) Sync & Apply Rules"
                echo "  0) Back"
                echo ""
                read -p "Select [0-5]: " choice
                case "$choice" in
                    1) echo ""
                       blue_message "Add Header Rule"
                       echo "  Select Header Type:"
                       echo "    1) Custom (Manual)           5) Strict-Transport-Security"
                       echo "    2) X-Content-Type-Options    6) X-Frame-Options"
                       echo "    3) Content-Security-Policy   7) Referrer-Policy"
                       echo "    4) Permissions-Policy        0) Cancel"
                       echo ""
                       read -p "  Select [0-7]: " ht_choice
                       
                       local hn="" hv=""
                       case "$ht_choice" in
                           1) read -p "  Header Name: " hn; read -p "  Header Value: " hv ;;
                           2) hn="X-Content-Type-Options"; hv="nosniff" ;;
                           3) hn="Content-Security-Policy"; hv="default-src 'self' http: https: data: blob: 'unsafe-inline'" ;;
                           4) hn="Permissions-Policy"; hv="geolocation=(), microphone=(), camera=()" ;;
                           5) hn="Strict-Transport-Security"; hv="max-age=31536000; includeSubDomains; preload" ;;
                           6) hn="X-Frame-Options"; hv="SAMEORIGIN" ;;
                           7) hn="Referrer-Policy"; hv="strict-origin-when-cross-origin" ;;
                           *) continue ;;
                       esac
                       
                       if [[ "$ht_choice" != "1" ]]; then
                           echo "  Header: ${CYAN}$hn${NC}"
                           read -p "  Value [default: $hv]: " custom_hv
                           hv="${custom_hv:-$hv}"
                       fi
                       
                       [[ -n "$hn" && -n "$hv" ]] && tbs app rules "$app_user" add-header "$hn" "$hv" ;;
                    2) read -p "  Header Index to remove: " hi
                       [[ -n "$hi" ]] && tbs app rules "$app_user" rm-header "$hi" ;;
                    3) echo ""
                       blue_message "Add Redirect or Rewrite Rule"
                       
                       # Action
                       echo "  Action:"
                       echo "    1) Permanent Redirect (301) - Best for SEO"
                       echo "    2) Temporary Redirect (302)"
                       echo "    3) Internal Rewrite (Advanced)"
                       read -p "  Select [1-3] (default 1): " rt_choice
                       local rt="301"
                       [[ "$rt_choice" == "2" ]] && rt="302"
                       [[ "$rt_choice" == "3" ]] && rt="rewrite"
                       
                       # Query String
                       read -p "  Keep original query string? [Y/n]: " keep_q_choice
                       local keep_q="true"
                       [[ "$keep_q_choice" =~ ^[nN]$ ]] && keep_q="false"
                       
                       # Source & Destination
                       echo "  Old Path (e.g., /old-page or ^/blog/.*)"
                       read -p "  From: " rs
                       echo "  New Path (e.g., /new-page or /news/\$1)"
                       read -p "  To:   " rd
                       
                       # Conditions
                       local cond_json="null"
                       read -p "  Attach condition? [y/N]: " attach_cond
                       if [[ "$attach_cond" =~ ^[yY]$ ]]; then
                           echo ""
                           echo "  Condition Type:"
                           echo "    1) Host (Domain)"
                           echo "    2) URI (Path)"
                           echo "    3) Query String"
                           read -p "  Select [1-3]: " ct_choice
                           local ct="Host"
                           [[ "$ct_choice" == "2" ]] && ct="URI"
                           [[ "$ct_choice" == "3" ]] && ct="Query String"
                           
                           echo "  Operator:"
                           echo "    1) Equals (=)"
                           echo "    2) Not Equals (!=)"
                           echo "    3) Matches (~)"
                           echo "    4) Does Not Match (!~)"
                           read -p "  Select [1-4]: " op_choice
                           local op="="
                           [[ "$op_choice" == "2" ]] && op="!="
                           [[ "$op_choice" == "3" ]] && op="~"
                           [[ "$op_choice" == "4" ]] && op="!~"
                           
                           read -p "  Value (e.g., example.com): " cv
                           cond_json="[{\"type\": \"$ct\", \"operator\": \"$op\", \"value\": \"$cv\"}]"
                       fi
                       
                       [[ -n "$rs" && -n "$rd" ]] && tbs app rules "$app_user" add-rewrite "$rs" "$rd" "$rt" "$keep_q" "$cond_json" ;;
                    4) read -p "  Rule Index to remove: " ri
                       [[ -n "$ri" ]] && tbs app rules "$app_user" rm-rewrite "$ri" ;;
                    5) tbs app sync "$app_user" ;;
                    0|"") return 0 ;;
                esac
            done
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
                        # Ensure webroot starts with public_html
                        local new_wr
                        if [[ "$sub_val" == "public_html" || "$sub_val" == "." ]]; then
                            new_wr="public_html"
                        elif [[ "$sub_val" == public_html/* ]]; then
                            new_wr="$sub_val"
                        else
                            # User gave subpath only, prefix with public_html/
                            sub_val="${sub_val#/}"
                            new_wr="public_html/$sub_val"
                        fi
                        set_app_config "$app_user" "webroot" "\"$new_wr\""; green_message "Webroot: $new_wr"
                        local d=$(get_app_config "$app_user" "primary_domain") dr="/var/www/html/${APPLICATIONS_DIR_NAME}/$app_user/$new_wr"
                        [[ -f "${VHOSTS_DIR}/${d}.conf" ]] && sed_i "s|DocumentRoot.*|DocumentRoot $dr|g" "${VHOSTS_DIR}/${d}.conf"
                        [[ -f "${NGINX_CONF_DIR}/${d}.conf" ]] && sed_i "s|root.*/var/www/html/${APPLICATIONS_DIR_NAME}/$app_user[^;]*|root $dr|g" "${NGINX_CONF_DIR}/${d}.conf"
                        echo "  Full path: $dr"
                        info_message "Restart to apply: tbs restart" ;;
                    perms|permissions)
                        local uid=$(get_app_config "$app_user" "ssh.uid")
                        [[ "$uid" == "null" ]] && uid=""
                        _set_app_permissions "$app_user" "$uid" && green_message "✅ Permissions reset" ;;
                    show) [[ "$HAS_JQ" == "true" ]] && jq '.' "$(get_app_config_path "$app_user")" || cat "$(get_app_config_path "$app_user")" ;;
                    *) error_message "Unknown config action: $sub_action" ;;
                esac
                return 0
            fi
            
            while true; do
                _app_header "$app_user" "⚙️  Settings"
                local varnish=$(get_app_config "$app_user" "varnish")
                local webroot=$(get_app_config "$app_user" "webroot")
                
                # Show development mode warning
                if [[ "${APP_ENV:-development}" == "development" ]]; then
                    yellow_message "  [Development Mode] - Cache is minimal by default"
                fi
                echo ""
                echo "  Varnish Cache: ${varnish:-true}"
                echo "  Webroot:       ${webroot:-public_html}"
                echo ""
                echo "  1) Toggle Varnish Cache"
                echo "  2) Change Webroot"
                echo "  3) Reset Permissions"
                echo "  4) Show Full Config"
                echo "  0) Back"
                echo ""
                read -p "Select [0-4]: " choice
                
                case "$choice" in
                    1) # Toggle Varnish - fixed logic
                       if [[ "$varnish" == "false" ]]; then
                           set_app_config "$app_user" "varnish" "true"
                           green_message "Varnish Cache: ON"
                       else
                           set_app_config "$app_user" "varnish" "false"
                           yellow_message "Varnish Cache: OFF"
                       fi
                       if [[ "${APP_ENV:-development}" == "development" ]]; then
                           info_message "Note: In development mode, Varnish has minimal caching enabled."
                       fi
                       ;;
                    2) # Change Webroot - only subpath after public_html/
                       local current_wr=$(get_app_config "$app_user" "webroot")
                       [[ -z "$current_wr" || "$current_wr" == "null" ]] && current_wr="public_html"
                       local base_path="/${app_user}/public_html"
                       local full_path="/var/www/html/${APPLICATIONS_DIR_NAME}${base_path}"
                       
                       echo ""
                       blue_message "Webroot Configuration"
                       echo "  Base path (fixed): $full_path/"
                       echo "  Current webroot:   $current_wr"
                       echo ""
                       yellow_message "  Note: You can only change the path AFTER public_html/"
                       echo "  Example: For Laravel, enter 'public' to set public_html/public"
                       echo "  Leave empty or enter '.' for public_html itself"
                       echo ""
                       read -p "  Subpath after public_html/ : " new_subpath
                       
                       # Clean input - remove leading/trailing slashes
                       new_subpath="${new_subpath#/}"
                       new_subpath="${new_subpath%/}"
                       
                       # Set the webroot
                       local new_wr
                       if [[ -z "$new_subpath" || "$new_subpath" == "." ]]; then
                           new_wr="public_html"
                       else
                           new_wr="public_html/$new_subpath"
                       fi
                       
                       set_app_config "$app_user" "webroot" "\"$new_wr\""
                       
                       # Update vhost configs
                       local d=$(get_app_config "$app_user" "primary_domain")
                       local dr="/var/www/html/${APPLICATIONS_DIR_NAME}/$app_user/$new_wr"
                       [[ -f "${VHOSTS_DIR}/${d}.conf" ]] && sed_i "s|DocumentRoot.*|DocumentRoot $dr|g" "${VHOSTS_DIR}/${d}.conf"
                       [[ -f "${NGINX_CONF_DIR}/${d}.conf" ]] && sed_i "s|root.*/var/www/html/${APPLICATIONS_DIR_NAME}/$app_user[^;]*|root $dr|g" "${NGINX_CONF_DIR}/${d}.conf"
                       
                       reload_webservers
                       echo ""
                       green_message "Webroot updated and servers reloaded!"
                       echo "  New webroot: $new_wr"
                       echo "  Full path:   $dr"
                       ;;
                    3) local uid=$(get_app_config "$app_user" "ssh.uid")
                       [[ "$uid" == "null" ]] && uid=""
                       _set_app_permissions "$app_user" "$uid" && green_message "✅ Permissions reset" ;;
                    4) [[ "$HAS_JQ" == "true" ]] && jq '.' "$(get_app_config_path "$app_user")" || cat "$(get_app_config_path "$app_user")" ;;
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
            [[ "$HAS_JQ" == "true" ]] && jq '.' "$(get_app_config_path "$SELECTED_APP")"
            ;;
        
        # tbs app backup [app] - Backup specific app
        backup)
            _app_get "$app_arg1" || return 1
            _app_backup "$SELECTED_APP"
            ;;
            
        # tbs app restore [app] - Restore specific app
        restore)
            _app_get "$app_arg1" || return 1
            _app_restore "$SELECTED_APP"
            ;;
        
        # tbs app sync [app] - Sync app configs with current stack mode
        sync)
            local target_app="$app_arg1"
            if [[ -n "$target_app" ]]; then
                local u=$(resolve_app_user "$target_app")
                [[ -z "$u" ]] && { error_message "App '$target_app' not found."; return 1; }
                local d=$(get_app_config "$u" "primary_domain")
                [[ -z "$d" || "$d" == "null" ]] && d="${u}.localhost"
                local webroot=$(get_app_config "$u" "webroot")
                [[ -z "$webroot" || "$webroot" == "null" ]] && webroot="public_html"
                
                info_message "Syncing configuration for $u ($d)..."
                _generate_app_configs "$u" "$d" "$webroot"
            else
                info_message "Syncing all application configurations with current STACK_MODE: ${STACK_MODE}..."
                local apps_dir="$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME"
                [[ ! -d "$apps_dir" ]] && { yellow_message "No apps to sync."; return 0; }
                
                for app_dir in "$apps_dir"/*/; do
                    [[ ! -d "$app_dir" ]] && continue
                    local u=$(basename "$app_dir")
                    local d=$(get_app_config "$u" "primary_domain")
                    [[ -z "$d" || "$d" == "null" ]] && d="${u}.localhost"
                    
                    info_message "  Syncing: $u ($d)..."
                    
                    local webroot=$(get_app_config "$u" "webroot")
                    [[ -z "$webroot" || "$webroot" == "null" ]] && webroot="public_html"
                    
                    _generate_app_configs "$u" "$d" "$webroot"
                done
            fi
            
            reload_webservers
            green_message "✅ Sync completed and web servers reloaded."
            ;;
        
        # Help
        help|--help|-h)
            echo ""
            blue_message "╔══════════════════════════════════════════════════════════════╗"
            blue_message "║                    📦 tbs app - Help                         ║"
            blue_message "╚══════════════════════════════════════════════════════════════╝"
            echo ""
            echo -e "  ${CYAN}tbs app${NC}                    Interactive app manager"
            echo -e "  ${CYAN}tbs app add <name>${NC}         Create new app"
            echo -e "  ${CYAN}tbs app rm [app]${NC}           Delete app"
            echo -e "  ${CYAN}tbs app db [app]${NC}           Database management"
            echo -e "  ${CYAN}tbs app ssh [app]${NC}          SSH/SFTP settings"
            echo -e "  ${CYAN}tbs app domain [app]${NC}       Manage domains"
            echo -e "  ${CYAN}tbs app ssl [app]${NC}          SSL certificates"
            echo -e "  ${CYAN}tbs app php [app]${NC}          PHP configuration"
            echo -e "  ${CYAN}tbs app config [app]${NC}       App settings"
            echo -e "  ${CYAN}tbs app code [app]${NC}         Open in VS Code"
            echo -e "  ${CYAN}tbs app open [app]${NC}         Open in browser"
            echo -e "  ${CYAN}tbs app info [app]${NC}         Show app config"
            echo -e "  ${CYAN}tbs app sync${NC}               Sync all apps with current mode"
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
        blue_message "State Tracking"
        if has_valid_state; then
            local saved_db=$(get_state_value "DATABASE")
            local saved_php=$(get_state_value "PHPVERSION")
            local changes=$(detect_config_changes)
            echo -e "  State File: ${GREEN}Active${NC}"
            echo "  Tracked DB: $saved_db"
            echo "  Tracked PHP: $saved_php"
            if [[ -n "$changes" ]]; then
                echo -e "  Pending Changes: ${YELLOW}Yes${NC} (run 'tbs state diff')"
            else
                echo -e "  Pending Changes: ${GREEN}None${NC}"
            fi
        else
            echo -e "  State File: ${YELLOW}Not initialized${NC}"
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
        
        local databases
        databases=$(execute_mysql_command -N -B -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "^(information_schema|performance_schema|mysql|phpmyadmin|sys|Database|#.*)$" || true)

        if [[ -z "$databases" ]]; then
            yellow_message "No databases found to backup."
        fi

        # Create temporary directories for SQL and app data
        local temp_sql_dir="$backup_dir/sql"
        local temp_app_dir="$backup_dir/app"
        rm -rf "$temp_sql_dir" "$temp_app_dir"
        mkdir -p "$temp_sql_dir" "$temp_app_dir"

        local db_count=0
        for db in $databases; do
            if [[ -n "$db" ]]; then
                local backup_sql_file="$temp_sql_dir/db_backup_$db.sql"
                info_message "  Backing up database: $db..."
                if execute_mysqldump "$db" "$backup_sql_file"; then
                    ((db_count++))
                else
                    yellow_message "  ⚠️  Failed to backup database: $db"
                    rm -f "$backup_sql_file"
                fi
            fi
        done

        # Copy application data to the temporary app directory
        local app_count=0
        if [[ -d "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME" ]]; then
            info_message "  Backing up application files..."
            # Use -a if possible for better preservation, fallback to -r
            if cp -a "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/." "$temp_app_dir/" 2>/dev/null; then
                app_count=$(ls -1 "$temp_app_dir" | wc -l)
            else
                cp -r "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/." "$temp_app_dir/" 2>/dev/null || true
                app_count=$(ls -1 "$temp_app_dir" | wc -l)
            fi
        else
            yellow_message "  ⚠️  Applications directory not found, skipping app backup."
        fi

        # Create the compressed backup file containing both SQL and app data
        if ! tar -czf "$backup_file" -C "$backup_dir" sql app 2>/dev/null; then
            error_message "Failed to create backup archive."
            rm -rf "$temp_sql_dir" "$temp_app_dir"
            return 1
        fi

        # Clean up temporary directories
        rm -rf "$temp_sql_dir" "$temp_app_dir"

        green_message "✅ Backup completed: ${backup_file}"
        echo "   Databases: $db_count | Apps: $app_count"
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
            if [[ "$OS_TYPE" == "mac" ]]; then
                backup_time=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$backup_file" 2>/dev/null || date -r "$backup_file" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
            elif [[ "$OS_TYPE" == "linux" ]]; then
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
            local sql_files=("$temp_restore_dir/sql"/*.sql)
            if [[ -e "${sql_files[0]}" ]]; then
                info_message "Restoring databases..."
                for sql_file in "${sql_files[@]}"; do
                    if [[ -f "$sql_file" ]]; then
                        local db_name=$(basename "$sql_file" | sed 's/db_backup_//;s/\.sql//')
                        info_message "  Restoring database: $db_name..."
                        # Pipe content directly to mysql client
                        if ! cat "$sql_file" | execute_mysql_command >/dev/null 2>&1; then
                            yellow_message "  ⚠️  Failed to restore database: $db_name"
                        fi
                    fi
                done
            else
                yellow_message "No database backups found in archive."
            fi
        fi
        
        # Restore Applications
        if [[ -d "$temp_restore_dir/app" ]]; then
            if [[ -n "$(ls -A "$temp_restore_dir/app" 2>/dev/null)" ]]; then
                info_message "Restoring applications..."
                # Ensure applications directory exists
                mkdir -p "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME"
                # Copy with error handling
                if cp -a "$temp_restore_dir/app/." "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/" 2>/dev/null; then
                    green_message "  ✅ Application files restored."
                else
                    cp -R "$temp_restore_dir/app/." "$DOCUMENT_ROOT/$APPLICATIONS_DIR_NAME/" 2>/dev/null || yellow_message "  ⚠️  Some application files may not have been restored."
                fi
            else
                yellow_message "No application files found in archive."
            fi
        fi
        
        # Clean up
        rm -rf "$temp_restore_dir"
        
        green_message "✅ Restore completed from $selected_backup"
        info_message "You may need to run 'tbs app sync' to refresh configurations."
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

    # Fix line endings in shell scripts
    fix-line-endings|fix)
        fix_line_endings
        green_message "Line endings check completed!"
        ;;
    
    # Database management
    db)
        error_message "Direct database commands have been removed. Use: tbs app db <app_user>"
        return 1
        ;;

    # Quick project creators
    create)
        local t="${2:-blank}" n="${3:-}"
        is_service_running "$WEBSERVER_SERVICE" || { yellow_message "Starting stack..."; tbs_start; }
        [[ -z "$2" ]] && { info_message "Types: laravel, wordpress, blank"; read -p "Type [blank]: " t; t="${t:-blank}"; }
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
                    local app_prefix="${u//-/_}"
                    while true; do
                        db_name=$(_suggest_app_db_name "$app_prefix")
                        [[ -z "$db_name" ]] && db_name="${app_prefix}_$((RANDOM%9000+1000))"
                        if _db_exists "$db_name" || _db_user_exists "$db_name"; then
                            continue
                        fi
                        break
                    done
                    local db_user="$db_name"
                    local db_pass=$(generate_strong_password 16)
                    
                    _db_create "$db_name" && _db_create_user "$db_user" "$db_pass" "$db_name"
                    
                    # Update app config
                    [[ "$HAS_JQ" == "true" ]] && {
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
            blank|empty) green_message "Blank: https://${u}.localhost" ;;
            *) error_message "Unknown: $t. Available: laravel, wordpress, blank" ;;
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

    # State management command
    state)
        local state_action="${2:-show}"
        case "$state_action" in
            show|status)
                if has_valid_state; then
                    echo ""
                    blue_message "╔══════════════════════════════════════════════════════════════╗"
                    blue_message "║                    📋 TBS State File                         ║"
                    blue_message "╚══════════════════════════════════════════════════════════════╝"
                    echo ""
                    echo "  File: $TBS_STATE_FILE"
                    echo ""
                    info_message "Tracked Configuration:"
                    for var in DATABASE PHPVERSION STACK_MODE INSTALLATION_TYPE APP_ENV MYSQL_ROOT_PASSWORD MYSQL_USER MYSQL_PASSWORD MYSQL_DATABASE REDIS_PASSWORD COMPOSE_PROJECT_NAME; do
                        local val=$(get_state_value "$var")
                        # Mask passwords
                        if [[ "$var" == *PASSWORD* && -n "$val" ]]; then
                            local masked="${val:0:3}***${val: -2}"
                            echo "    $var: $masked"
                        else
                            echo "    $var: ${val:-<not set>}"
                        fi
                    done
                    echo ""
                    local init_time=$(get_state_value "STATE_INITIALIZED")
                    local update_time=$(get_state_value "LAST_UPDATED")
                    [[ -n "$init_time" ]] && echo "  Initialized: $(date -r "$init_time" 2>/dev/null || date -d "@$init_time" 2>/dev/null || echo "$init_time")"
                    [[ -n "$update_time" ]] && echo "  Last Updated: $(date -r "$update_time" 2>/dev/null || date -d "@$update_time" 2>/dev/null || echo "$update_time")"
                    echo ""
                else
                    yellow_message "No state file found. Run 'tbs start' to initialize."
                fi
                ;;
            reset|clear)
                if [[ -f "$TBS_STATE_FILE" ]]; then
                    rm -f "$TBS_STATE_FILE"
                    green_message "State file cleared."
                    info_message "New state will be created on next start."
                else
                    yellow_message "No state file to clear."
                fi
                ;;
            init)
                if [[ -f "$tbsPath/.env" ]]; then
                    load_env_file "$tbsPath/.env" true
                    init_state_file
                    green_message "State file initialized from current .env"
                else
                    error_message "No .env file found."
                fi
                ;;
            diff|changes)
                if has_valid_state; then
                    local changes=$(detect_config_changes)
                    if [[ -n "$changes" ]]; then
                        echo ""
                        yellow_message "⚠️  Pending Configuration Changes:"
                        echo ""
                        while IFS= read -r var; do
                            [[ -z "$var" ]] && continue
                            local old_val=$(get_state_value "$var")
                            local new_val="${!var}"
                            # Mask passwords
                            if [[ "$var" == *PASSWORD* ]]; then
                                [[ -n "$old_val" ]] && old_val="${old_val:0:3}***"
                                [[ -n "$new_val" ]] && new_val="${new_val:0:3}***"
                            fi
                            echo "  • $var: $old_val → $new_val"
                        done <<< "$changes"
                        echo ""
                        info_message "These changes will be applied on next start/restart."
                    else
                        green_message "No pending configuration changes."
                    fi
                else
                    yellow_message "No state file. Cannot detect changes."
                fi
                ;;
            *)
                echo "Usage: tbs state [show|reset|init|diff]"
                echo "  show  - Display current state (default)"
                echo "  reset - Clear state file"
                echo "  init  - Initialize state from current .env"
                echo "  diff  - Show pending changes"
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
            echo -e "${BLUE}Stack Management:${NC}"
            echo -e "  ${CYAN}start${NC}              Start the stack & open browser"
            echo -e "  ${CYAN}stop${NC}               Stop all services & cleanup"
            echo -e "  ${CYAN}restart${NC}            Restart stack & apply changes"
            echo -e "  ${CYAN}build${NC}              Rebuild containers & start"
            echo -e "  ${CYAN}status${NC}             Show running services"
            echo -e "  ${CYAN}info${NC}               Show stack & system info"
            echo -e "  ${CYAN}config${NC}             Interactive configuration"
            echo ""
            echo -e "${BLUE}Application Management:${NC}"
            echo -e "  ${CYAN}app${NC}                Interactive app manager"
            echo -e "  ${CYAN}app add <name>${NC}     Create a new application"
            echo -e "  ${CYAN}app rm <app>${NC}       Delete an application"
            echo -e "  ${CYAN}app db <app>${NC}       Manage app databases"
            echo -e "  ${CYAN}app domain <app>${NC}   Manage app domains"
            echo -e "  ${CYAN}app ssl <app>${NC}      Manage SSL certificates"
            echo -e "  ${CYAN}app php <app>${NC}      Configure PHP settings"
            echo -e "  ${CYAN}app ssh <app>${NC}      SSH/SFTP settings"
            echo -e "  ${CYAN}app config <app>${NC}   Advanced app settings"
            echo -e "  ${CYAN}app info <app>${NC}     Show app configuration"
            echo -e "  ${CYAN}app backup <app>${NC}   Backup specific app"
            echo -e "  ${CYAN}app restore <app>${NC}  Restore specific app"
            echo -e "  ${CYAN}app code <app>${NC}     Open app in VS Code"
            echo -e "  ${CYAN}app open <app>${NC}     Open app in browser"
            echo -e "  ${CYAN}app sync${NC}           Sync all apps with mode"
            echo ""
            echo -e "${BLUE}Project Creators:${NC}"
            echo -e "  ${CYAN}create laravel${NC}     New Laravel project"
            echo -e "  ${CYAN}create wordpress${NC}   New WordPress project"
            echo -e "  ${CYAN}create blank${NC}       New blank PHP project"
            echo ""
            echo -e "${BLUE}Development Tools:${NC}"
            echo -e "  ${CYAN}shell [service]${NC}    Shell (php, mysql, redis, nginx)"
            echo -e "  ${CYAN}logs [service]${NC}     View logs (use -f to follow)"
            echo -e "  ${CYAN}code [app|root]${NC}    Open in VS Code"
            echo -e "  ${CYAN}pma${NC}                Open phpMyAdmin"
            echo -e "  ${CYAN}mail${NC}               Open Mailpit"
            echo -e "  ${CYAN}redis-cli${NC}          Open Redis CLI"
            echo ""
            echo -e "${BLUE}Maintenance & Security:${NC}"
            echo -e "  ${CYAN}backup${NC}             Backup databases & apps"
            echo -e "  ${CYAN}restore${NC}            Restore from backup"
            echo -e "  ${CYAN}sshadmin${NC}           Manage master SSH user"
            echo -e "  ${CYAN}fix${NC}                Fix script line endings"
            echo -e "  ${CYAN}state [diff|show]${NC}  Manage config state"
            echo -e "  ${CYAN}ssl-localhost${NC}      Generate localhost SSL"
            echo ""
            ;;
        *)
            error_message "Unknown: $1 | Run: tbs help"
            ;;
    esac
}

# Check requirements
for c in docker sed curl tar; do command_exists "$c" || { error_message "$c not found"; exit 1; }; done
docker compose version >/dev/null 2>&1 || { error_message "Docker Compose missing"; exit 1; }

tbs "$@"
