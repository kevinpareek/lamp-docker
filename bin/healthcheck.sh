#!/bin/bash
# Simple healthcheck wrapper for MySQL to satisfy docker-compose configuration
# Ignores arguments passed by docker-compose (like --connect --innodb_initialized)
# and performs a standard ping check.

# Check if mysqladmin is available
if ! command -v mysqladmin &> /dev/null; then
    echo "Error: mysqladmin could not be found"
    exit 1
fi

# Perform ping check
# We use MYSQL_ROOT_PASSWORD from environment if available
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo "Warning: MYSQL_ROOT_PASSWORD not set, attempting without password"
    mysqladmin ping -h localhost --silent
else
    mysqladmin ping -h localhost -u root -p"${MYSQL_ROOT_PASSWORD}" --silent
fi

exit $?
