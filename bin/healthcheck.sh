#!/bin/sh
# Simple healthcheck wrapper for MySQL/MariaDB to satisfy docker-compose configuration
# Ignores arguments passed by docker-compose (like --connect --innodb_initialized)
# and performs a standard ping check.

# Determine which client to use
if command -v mariadb-admin >/dev/null 2>&1; then
    MYSQLADMIN="mariadb-admin"
elif command -v mysqladmin >/dev/null 2>&1; then
    MYSQLADMIN="mysqladmin"
else
    echo "Error: neither mariadb-admin nor mysqladmin could be found"
    exit 1
fi

# Perform ping check
# We use MYSQL_ROOT_PASSWORD from environment if available
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo "Warning: MYSQL_ROOT_PASSWORD not set, attempting without password"
    $MYSQLADMIN ping -h localhost --silent
else
    $MYSQLADMIN ping -h localhost -u root -p"${MYSQL_ROOT_PASSWORD}" --silent
fi

exit $?
