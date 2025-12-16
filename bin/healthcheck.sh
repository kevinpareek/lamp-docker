#!/bin/sh
#
# Healthcheck helper for MySQL/MariaDB containers.
# docker-compose (and some official images) call healthcheck scripts with flags like:
#   --connect --innodb_initialized
# Older versions of this repo ignored those flags and only performed a ping check,
# which could mark the DB as "healthy" too early during initialization.
#
# This script is POSIX sh compatible.

set -eu

want_connect=false
want_innodb=false

# Parse flags (ignore unknown flags for forward compatibility)
for arg in "$@"; do
    case "$arg" in
        --connect) want_connect=true ;;
        --innodb_initialized|--innodb-initialized) want_innodb=true ;;
        *) : ;;
    esac
done

# Determine which client to use
if command -v mariadb-admin >/dev/null 2>&1; then
    MYSQLADMIN="mariadb-admin"
elif command -v mysqladmin >/dev/null 2>&1; then
    MYSQLADMIN="mysqladmin"
else
    echo "Error: neither mariadb-admin nor mysqladmin could be found"
    exit 1
fi

# Auth (use env when available; support both MYSQL_ROOT_PASSWORD and MARIADB_ROOT_PASSWORD)
ROOT_PW="${MYSQL_ROOT_PASSWORD:-${MARIADB_ROOT_PASSWORD:-}}"
USER_OPT=""
PASS_OPT=""
if [ -n "$ROOT_PW" ]; then
    USER_OPT="-u root"
    PASS_OPT="-p${ROOT_PW}"
fi

# Always ensure the server is reachable
$MYSQLADMIN ping -h localhost $USER_OPT $PASS_OPT --silent

# If requested, verify InnoDB is initialized/available (stricter "ready" signal)
if [ "$want_innodb" = "true" ] || [ "$want_connect" = "true" ]; then
    if command -v mariadb >/dev/null 2>&1; then
        MYSQLCLI="mariadb"
    elif command -v mysql >/dev/null 2>&1; then
        MYSQLCLI="mysql"
    else
        # If no SQL client exists, fall back to ping-only (still better than failing hard).
        exit 0
    fi

    # Basic connect check
    $MYSQLCLI -h localhost $USER_OPT $PASS_OPT -e "SELECT 1" >/dev/null 2>&1
fi

if [ "$want_innodb" = "true" ]; then
    # Confirm InnoDB engine is available (YES or DEFAULT)
    $MYSQLCLI -h localhost $USER_OPT $PASS_OPT -Nse \
        "SELECT 1 FROM information_schema.engines WHERE engine='InnoDB' AND support IN ('YES','DEFAULT') LIMIT 1;" \
        | grep -q '^1$'
fi

exit $?
