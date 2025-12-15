#!/bin/sh
set -e

# Ensure the destination directory exists
mkdir -p /etc/nginx/http.d

# Wait for webserver to be ready
echo "Waiting for webserver..."
if [ "$STACK_MODE" = "thunder" ]; then
    # Check for PHP-FPM on port 9000
    until nc -z webserver 9000 > /dev/null 2>&1; do
        echo "Waiting for PHP-FPM..."
        sleep 2
    done
else
    # Check for Apache on port 80
    # curl exit code 52 (empty reply) still means the TCP connection is working.
    while :; do
        curl_rc=0
        curl -s -o /dev/null "http://webserver" || curl_rc=$?
        if [ "$curl_rc" -eq 0 ] || [ "$curl_rc" -eq 52 ]; then
            break
        fi
        echo "Waiting for Apache..."
        sleep 2
    done
fi
echo "Webserver is reachable."

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

# Process main template
envsubst '${APACHE_DOCUMENT_ROOT} ${APPLICATIONS_DIR_NAME} ${NGINX_STATIC_EXPIRES}' < /etc/nginx/templates/00-default.conf.template > /etc/nginx/http.d/default.conf

# Start Nginx
echo "Starting Nginx with Brotli support..."
exec nginx -g "daemon off;"
