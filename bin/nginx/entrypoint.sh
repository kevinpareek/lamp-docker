#!/bin/sh
set -e

# Ensure the destination directory exists
mkdir -p /etc/nginx/http.d

# Wait for webserver to be ready
echo "Waiting for webserver..."
until curl -s "http://webserver" > /dev/null 2>&1 || [ $? -eq 52 ] || [ $? -eq 7 ]; do
  echo "Waiting for webserver..."
  sleep 2
done
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
envsubst '${APACHE_DOCUMENT_ROOT} ${APPLICATIONS_DIR_NAME} ${NGINX_STATIC_EXPIRES}' < /etc/nginx/templates/00-default.conf.template > /etc/nginx/http.d/default.conf

# Start Nginx
echo "Starting Nginx with Brotli support..."
exec nginx -g "daemon off;"
