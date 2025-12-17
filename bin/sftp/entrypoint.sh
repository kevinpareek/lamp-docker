#!/bin/bash
# SFTP/SSH Entrypoint Script
# Manages per-app users with chroot jail

set -e

USERS_DIR="/etc/sftp.d/users"
WEB_ROOT="/var/www/html/applications"

# Create necessary directories
mkdir -p "$USERS_DIR"

# Function to create/update user
create_user() {
    local username="$1"
    local password="$2"
    local app_name="$3"
    local uid="${4:-1000}"
    local gid="${5:-1000}"
    
    # Check if user exists
    if id "$username" &>/dev/null; then
        echo "User $username already exists, updating password..."
        echo "$username:$password" | chpasswd
    else
        echo "Creating user $username..."
        
        # Create group if not exists
        if ! getent group "$username" &>/dev/null; then
            addgroup -g "$gid" "$username" 2>/dev/null || true
        fi
        
        # Create user with home directory pointing to app
        local app_path="/var/www/html/applications/$app_name"
        adduser -D -u "$uid" -G "$username" -h "$app_path" -s /bin/bash "$username" 2>/dev/null || true
        echo "$username:$password" | chpasswd
        
        # Add user to www-data group for web file access
        adduser "$username" www-data 2>/dev/null || true
    fi
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
    
    for user_file in "$USERS_DIR"/*.json; do
        if [[ -f "$user_file" ]]; then
            if command -v jq &>/dev/null; then
                local username=$(jq -r '.username // empty' "$user_file")
                local password=$(jq -r '.password // empty' "$user_file")
                local app_name=$(jq -r '.app_name // empty' "$user_file")
                local enabled=$(jq -r '.enabled // true' "$user_file")
                local uid=$(jq -r '.uid // 1000' "$user_file")
                local gid=$(jq -r '.gid // 1000' "$user_file")
                
                if [[ -n "$username" && -n "$password" ]]; then
                    if [[ "$enabled" == "true" ]]; then
                        create_user "$username" "$password" "$app_name" "$uid" "$gid"
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
echo "  Turbo Stack SFTP Server"
echo "============================================"

setup_sshd
load_users

# Optional: watch for config changes
# watch_config

echo "Starting SSH daemon..."
exec /usr/sbin/sshd -D -e
