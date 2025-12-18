#!/bin/sh
set -e

# Ensure the destination directory exists
mkdir -p /etc/nginx/http.d

echo "Checking for SSL certificates..."
# Check and generate default SSL if missing
if [ ! -f /etc/nginx/ssl-sites/cert.pem ] || [ ! -f /etc/nginx/ssl-sites/cert-key.pem ]; then
    echo "Default SSL certificates not found in /etc/nginx/ssl-sites/. Generating self-signed certificates..."
    mkdir -p /etc/nginx/ssl-sites
    if openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl-sites/cert-key.pem \
        -out /etc/nginx/ssl-sites/cert.pem \
        -subj "/C=IN/ST=Rajasthan/L=Jaipur/O=TurboStack/OU=Local/CN=localhost"; then
        echo "Self-signed SSL certificates generated successfully."
        ls -la /etc/nginx/ssl-sites/
    else
        echo "ERROR: Failed to generate SSL certificates!"
        exit 1
    fi
else
    echo "SSL certificates already exist. Skipping generation."
fi

# Wait for Varnish backend to be ready
echo "Waiting for Varnish..."
while :; do
    curl_rc=0
    curl -s -o /dev/null "http://varnish" || curl_rc=$?
    if [ "$curl_rc" -eq 0 ] || [ "$curl_rc" -eq 52 ]; then
        break
    fi
    sleep 2
done
echo "Varnish is reachable."

# Determine Static Asset Expiration based on Environment
if [ "$APP_ENV" = "production" ]; then
    export NGINX_STATIC_EXPIRES="365d"
    echo "Production mode: Static assets expire in 365 days."
else
    export NGINX_STATIC_EXPIRES="off"
    echo "Development mode: Static asset caching disabled."
fi

# Perform env substitution
# We only substitute specific variables to avoid breaking Nginx variables like $host
# The list of variables must match what is used in docker-compose.yml and templates
echo "Generating Nginx configuration..."

# Create directory for processed includes
mkdir -p /etc/nginx/includes

# Process common.conf
envsubst '${APACHE_DOCUMENT_ROOT} ${NGINX_STATIC_EXPIRES}' < /etc/nginx/partials/common.conf > /etc/nginx/includes/common.conf

# Process varnish-proxy.conf with APP_ENV for development mode detection
if [ -f /etc/nginx/partials/varnish-proxy.conf ]; then
    envsubst '${APP_ENV}' < /etc/nginx/partials/varnish-proxy.conf > /etc/nginx/includes/varnish-proxy.conf
fi

# Copy php-fpm.conf to includes (no variable substitution needed)
if [ -f /etc/nginx/partials/php-fpm.conf ]; then
    cp /etc/nginx/partials/php-fpm.conf /etc/nginx/includes/php-fpm.conf
fi

# Process main template
envsubst '${APACHE_DOCUMENT_ROOT} ${APPLICATIONS_DIR_NAME} ${NGINX_STATIC_EXPIRES}' < /etc/nginx/templates/00-default.conf.template > /etc/nginx/http.d/default.conf

# Start Nginx
echo "Starting Nginx with Brotli support..."
exec nginx -g "daemon off;"
