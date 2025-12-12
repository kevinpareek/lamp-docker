#!/bin/sh
set -e

# Ensure the destination directory exists
mkdir -p /etc/nginx/http.d

# Perform env substitution
# We only substitute specific variables to avoid breaking Nginx variables like $host
# The list of variables must match what is used in docker-compose.yml and templates
echo "Generating Nginx configuration..."
envsubst '${APACHE_DOCUMENT_ROOT} ${APPLICATIONS_DIR_NAME}' < /etc/nginx/templates/00-default.conf.template > /etc/nginx/http.d/default.conf

# Start Nginx
echo "Starting Nginx with Brotli support..."
exec nginx -g "daemon off;"
