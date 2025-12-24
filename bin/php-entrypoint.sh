#!/bin/bash
# ============================================
# PHP Container Entrypoint Script
# Handles runtime configuration substitution
# ============================================
set -e

# Configuration Paths
PHP_INI_DIR="/usr/local/etc/php"
TEMPLATE_FILE="${PHP_INI_DIR}/php.ini-template"
TARGET_FILE="${PHP_INI_DIR}/php.ini"

# ============================================
# Process PHP.ini for Dynamic Variables
# ============================================
process_php_ini() {
    # Skip if template doesn't exist
    [[ ! -f "$TEMPLATE_FILE" ]] && return 0

    echo "Configuring PHP for ${APP_ENV:-development}..."

    # Create a temporary file for processing to ensure atomicity
    local tmp_file
    tmp_file=$(mktemp)

    # Handle Redis Password substitution
    if [[ -n "$REDIS_PASSWORD" ]]; then
        # Replace placeholder with actual password
        sed "s|\${REDIS_PASSWORD}|${REDIS_PASSWORD}|g" "$TEMPLATE_FILE" > "$tmp_file"
    else
        # No password - remove auth parameter and placeholder
        sed -e 's|?auth=\${REDIS_PASSWORD}||g' -e 's|\${REDIS_PASSWORD}||g' "$TEMPLATE_FILE" > "$tmp_file"
    fi

    # Move to final location and set correct permissions
    mv "$tmp_file" "$TARGET_FILE"
    chmod 644 "$TARGET_FILE"
    
    echo "✓ PHP configuration generated successfully"
}

# ============================================
# Ensure SSL Certificates Exist
# ============================================
setup_ssl() {
    local ssl_dir="/etc/apache2/ssl-sites"
    
    # Skip if not an Apache container, directory not writable, or openssl missing
    [[ ! -w "$ssl_dir" ]] && return 0
    command -v openssl >/dev/null 2>&1 || return 0
    
    if [[ ! -f "${ssl_dir}/cert.pem" || ! -f "${ssl_dir}/cert-key.pem" ]]; then
        echo "Generating self-signed SSL certificates..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "${ssl_dir}/cert-key.pem" \
            -out "${ssl_dir}/cert.pem" \
            -subj "/CN=localhost" 2>/dev/null

        chmod 644 "${ssl_dir}/cert.pem" "${ssl_dir}/cert-key.pem"
        echo "✓ SSL certificates generated"
    fi
}

# ============================================
# Ensure Required Directories & Logs
# ============================================
setup_environment() {
    # Create necessary directories
    mkdir -p /var/log/{supervisor,cron,php-fpm} /var/run/apache2 2>/dev/null || true

    # Cleanup stale PID files to ensure clean startup
    rm -f /var/run/apache2/apache2.pid /var/run/supervisord.pid /var/run/supervisor.sock 2>/dev/null || true

    # Initialize log files
    touch /var/log/{cron.log,php_errors.log} 2>/dev/null || true
    chmod 666 /var/log/php_errors.log 2>/dev/null || true
    
    echo "✓ Environment initialized"
}

# ============================================
# Main Execution
# ============================================
echo "Initializing PHP container..."
process_php_ini
setup_ssl
setup_environment
echo "Starting services..."
exec "$@"
