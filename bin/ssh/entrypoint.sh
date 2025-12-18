#!/bin/bash
# SFTP/SSH Entrypoint Script
# Manages per-app users with isolated access
# - Admin user: From TBS_ADMIN_* env vars (master user)
# - App users: From /etc/ssh.d/users/*.json (per-app access)

set -e

USERS_DIR="/etc/ssh.d/users"
WEB_ROOT="/var/www/html/${APPLICATIONS_DIR_NAME:-applications}"
ADMIN_FILE="/etc/ssh.d/admin.json"

# Function to create/update admin user (access to all apps)
create_admin_user() {
    local username="$1"
    local password="$2"
    
    if [[ -z "$username" || -z "$password" ]]; then
        echo "Admin credentials not configured, skipping..."
        return
    fi
    
    echo "Setting up admin user: $username..."
    
    # Admin gets access to all applications root
    if id "$username" &>/dev/null; then
        echo "$username:$password" | chpasswd
    else
        # Create admin group if not exists
        if ! getent group "tbsadmin" &>/dev/null; then
            addgroup -g 1000 "tbsadmin" 2>/dev/null || true
        fi
        
        # Admin home is applications root - can see all apps
        adduser -D -u 1000 -G "tbsadmin" -h "$WEB_ROOT" -s /bin/bash "$username" 2>/dev/null || true
        echo "$username:$password" | chpasswd
        
        # Add admin to www-data group for file access
        adduser "$username" www-data 2>/dev/null || true
    fi
    
    # Add admin to all app groups for read/write access
    # This is done by reading all user config files and adding admin to each group
    for user_file in "$USERS_DIR"/*.json; do
        if [[ -f "$user_file" ]] && command -v jq &>/dev/null; then
            local app_user=$(jq -r '.username // empty' "$user_file")
            if [[ -n "$app_user" ]] && getent group "$app_user" &>/dev/null; then
                adduser "$username" "$app_user" 2>/dev/null || true
                echo "Added $username to group $app_user"
            fi
        fi
    done
    
    echo "Admin user $username configured with access to all apps"
}

# Function to create/update app user (isolated access)
create_user() {
    local username="$1"
    local password="$2"
    local dir_name="$3"
    local uid="${4:-1000}"
    local gid="${5:-1000}"
    
    # App user home directory is their specific app folder
    local app_path="$WEB_ROOT/$dir_name"
    
    # Check if user exists
    if id "$username" &>/dev/null; then
        echo "User $username already exists, updating password..."
        echo "$username:$password" | chpasswd
    else
        echo "Creating app user $username (dir: $dir_name)..."
        
        # Create dedicated group for this app
        if ! getent group "$username" &>/dev/null; then
            addgroup -g "$gid" "$username" 2>/dev/null || true
        fi
        
        # Create user with home directory pointing ONLY to their app
        adduser -D -u "$uid" -G "$username" -h "$app_path" -s /bin/bash "$username" 2>/dev/null || true
        echo "$username:$password" | chpasswd
        
        # Add user to www-data for web compatibility
        adduser "$username" www-data 2>/dev/null || true
        
        # Add admin user (tbsadmin) to this app's group so admin can access
        if id "tbsadmin" &>/dev/null 2>&1 || getent passwd | grep -q "tbsadmin"; then
            # Find admin username from /etc/ssh.d/admin.json
            if [[ -f "$ADMIN_FILE" ]] && command -v jq &>/dev/null; then
                local admin_user=$(jq -r '.username // empty' "$ADMIN_FILE")
                if [[ -n "$admin_user" ]] && id "$admin_user" &>/dev/null; then
                    adduser "$admin_user" "$username" 2>/dev/null || true
                fi
            fi
        fi
        
        # Set ownership: user owns their app directory
        if [[ -d "$app_path" ]]; then
            chown -R "$uid:$gid" "$app_path"
            # Proper permissions - group readable for admin access
            find "$app_path" -type d -exec chmod 750 {} \;
            find "$app_path" -type f -exec chmod 640 {} \;
            # .ssh needs to be more restrictive
            chmod 700 "$app_path/.ssh" 2>/dev/null || true
            find "$app_path/.ssh" -type f -exec chmod 600 {} \; 2>/dev/null || true
            # tmp needs to be writable
            chmod 1770 "$app_path/tmp" 2>/dev/null || true
        fi
    fi
    
    echo "User $username has access only to: $app_path"
}

# Function to disable user
disable_user() {
    local username="$1"
    
    if id "$username" &>/dev/null; then
        passwd -l "$username" 2>/dev/null || true
        echo "User $username disabled"
    fi
}

# Function to enable user
enable_user() {
    local username="$1"
    local password="$2"
    
    if id "$username" &>/dev/null; then
        passwd -u "$username" 2>/dev/null || true
        echo "$username:$password" | chpasswd
        echo "User $username enabled"
    fi
}

# Load users from config files
load_users() {
    echo "Loading SSH users..."
    
    # First, setup admin user from environment variables
    local admin_user="${TBS_ADMIN_USER:-}"
    local admin_pass="${TBS_ADMIN_PASSWORD:-}"
    
    if [[ -n "$admin_user" && -n "$admin_pass" ]]; then
        create_admin_user "$admin_user" "$admin_pass"
    else
        echo "TBS Admin not configured (set TBS_ADMIN_USER and TBS_ADMIN_PASSWORD)"
    fi
    
    # Load app-specific users from JSON files
    for user_file in "$USERS_DIR"/*.json; do
        if [[ -f "$user_file" ]]; then
            if command -v jq &>/dev/null; then
                local username=$(jq -r '.username // .app_user // empty' "$user_file")
                local password=$(jq -r '.password // empty' "$user_file")
                local dir_name=$(jq -r '.app_user // .dir_name // .app_name // empty' "$user_file")
                local enabled=$(jq -r '.enabled // true' "$user_file")
                local uid=$(jq -r '.uid // 1000' "$user_file")
                local gid=$(jq -r '.gid // 1000' "$user_file")
                
                if [[ -n "$username" && -n "$password" && -n "$dir_name" ]]; then
                    if [[ "$enabled" == "true" ]]; then
                        create_user "$username" "$password" "$dir_name" "$uid" "$gid"
                    else
                        disable_user "$username"
                    fi
                fi
            fi
        fi
    done
}

# Setup SSH server
setup_sshd() {
    # Generate host keys if not exist
    ssh-keygen -A
    
    # Configure SSHD for both SSH and SFTP access
    cat > /etc/ssh/sshd_config <<'EOF'
# SSH Server Configuration for per-app SSH/SFTP access
Port 22
Protocol 2

# Host keys
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Logging
SyslogFacility AUTH
LogLevel INFO

# Authentication
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# Security
StrictModes yes
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30

# Allow TCP forwarding for development
AllowTcpForwarding yes
X11Forwarding no

# SFTP Subsystem
Subsystem sftp internal-sftp

# Match users for chroot (optional - uncomment for restricted access)
# Match User *,!root
#     ChrootDirectory /home/%u
#     ForceCommand internal-sftp
#     AllowTcpForwarding no
EOF
}

# Watch for config changes (optional background process)
watch_config() {
    while true; do
        inotifywait -q -e modify,create,delete "$USERS_DIR" 2>/dev/null || sleep 30
        echo "Config change detected, reloading users..."
        load_users
    done &
}

# Main
echo "============================================"
echo "  Turbo Stack SSH Server"
echo "============================================"

setup_sshd
load_users

# Optional: watch for config changes
# watch_config

echo "Starting SSH daemon..."
exec /usr/sbin/sshd -D -e
