#!/bin/sh
# Root password guard for MySQL/MariaDB.
#
# Goal: If MYSQL_ROOT_PASSWORD changes but the DB still has the old password,
# this wrapper attempts to authenticate using a cached previous password and
# rotates root to the desired password.
#
# Notes:
# - Stores cached passwords in the DB volume with strict permissions.
# - Does NOT attempt skip-grant-tables recovery (break-glass should be manual).
# - Designed to work for both mysql:* and mariadb:* official images.

set -eu

log() {
  printf '%s\n' "tbs-db-guard: $*" >&2
}

# Find original entrypoint
ORIG=""
for p in /usr/local/bin/docker-entrypoint.sh /docker-entrypoint.sh /entrypoint.sh; do
  if [ -x "$p" ]; then
    ORIG="$p"
    break
  fi
done

if [ -z "$ORIG" ]; then
  log "original entrypoint not found"
  exit 1
fi

DESIRED_PW="${MYSQL_ROOT_PASSWORD:-${MARIADB_ROOT_PASSWORD:-}}"

# If no desired password is provided, behave like stock image.
if [ -z "$DESIRED_PW" ]; then
  exec "$ORIG" "$@"
fi

# Some compose/build combinations can result in an empty CMD when overriding entrypoint.
# The official MySQL/MariaDB entrypoints expect a server command (typically mysqld).
if [ "$#" -eq 0 ]; then
  if command -v mariadbd >/dev/null 2>&1; then
    set -- mariadbd
  elif command -v mysqld >/dev/null 2>&1; then
    set -- mysqld
  else
    # Last resort: let the original entrypoint decide (may still fail, but avoids hardcoding)
    set -- mariadbd
  fi
fi

# Pick SQL client
if command -v mariadb >/dev/null 2>&1; then
  MYSQLCLI="mariadb"
elif command -v mysql >/dev/null 2>&1; then
  MYSQLCLI="mysql"
else
  MYSQLCLI=""
fi

socket_candidates() {
  for s in /run/mysqld/mysqld.sock /var/run/mysqld/mysqld.sock /tmp/mysql.sock; do
    [ -S "$s" ] && printf '%s\n' "$s"
  done
}

# Cache location (inside the persistent DB volume)
GUARD_DIR="/var/lib/mysql/.tbs"
CUR_FILE="$GUARD_DIR/root_password.cur"
PREV_FILE="$GUARD_DIR/root_password.prev"

mkdir -p "$GUARD_DIR" 2>/dev/null || true
chmod 700 "$GUARD_DIR" 2>/dev/null || true

read_file() {
  f="$1"
  if [ -f "$f" ]; then
    cat "$f" 2>/dev/null || true
  fi
}

write_secret() {
  f="$1"; v="$2"
  umask 077
  # Avoid trailing newline issues by using printf
  printf '%s' "$v" > "$f"
  chmod 600 "$f" 2>/dev/null || true
}

try_auth() {
  pw="$1"
  [ -n "$MYSQLCLI" ] || return 1

  # Use a real SQL round-trip to validate credentials.
  # Prefer TCP, but fall back to socket if TCP auth is restricted.
  "$MYSQLCLI" -h 127.0.0.1 -uroot "-p$pw" -e "SELECT 1" >/dev/null 2>&1 && return 0

  for sock in $(socket_candidates); do
    "$MYSQLCLI" --protocol=SOCKET --socket="$sock" -uroot "-p$pw" -e "SELECT 1" >/dev/null 2>&1 && return 0
  done
  return 1
}

exec_sql() {
  pw="$1"; sql="$2"
  [ -n "$MYSQLCLI" ] || return 1
  "$MYSQLCLI" -h 127.0.0.1 -uroot "-p$pw" -e "$sql" >/dev/null 2>&1 && return 0
  for sock in $(socket_candidates); do
    "$MYSQLCLI" --protocol=SOCKET --socket="$sock" -uroot "-p$pw" -e "$sql" >/dev/null 2>&1 && return 0
  done
  return 1
}

rotate_root_password() {
  old_pw="$1"; new_pw="$2"

  # Escape single quotes for SQL (minimal)
  esc_new=$(printf '%s' "$new_pw" | sed "s/'/''/g")

  # Ensure both localhost and % accounts exist (healthchecks typically use TCP to localhost)
  sql="FLUSH PRIVILEGES;"
  sql="$sql CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED BY '${esc_new}';"
  sql="$sql CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '${esc_new}';"
  sql="$sql ALTER USER 'root'@'localhost' IDENTIFIED BY '${esc_new}';"
  sql="$sql ALTER USER 'root'@'%' IDENTIFIED BY '${esc_new}';"
  sql="$sql GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;"
  sql="$sql GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"
  sql="$sql FLUSH PRIVILEGES;"

  exec_sql "$old_pw" "$sql"
}

# Start the original entrypoint as the server process
"$ORIG" "$@" &
child=$!

# Forward signals to child
trap 'kill -TERM "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true' INT TERM

# Wait until server is up enough to respond to ping (with some password)
max_wait=90
waited=0

# Load cached passwords
CUR_PW="$(read_file "$CUR_FILE")"
PREV_PW="$(read_file "$PREV_FILE")"

while :; do
  # Child died -> exit with same status
  if ! kill -0 "$child" 2>/dev/null; then
    wait "$child" || true
    exit 1
  fi

  # If desired works, we are good.
  if try_auth "$DESIRED_PW"; then
    if [ "$CUR_PW" != "$DESIRED_PW" ]; then
      [ -n "$CUR_PW" ] && write_secret "$PREV_FILE" "$CUR_PW"
      write_secret "$CUR_FILE" "$DESIRED_PW"
      log "root password OK (cached)"
    fi
    break
  fi

  # If current cached works, rotate to desired.
  if [ -n "$CUR_PW" ] && try_auth "$CUR_PW"; then
    log "detected root password mismatch; rotating using cached current password"
    if rotate_root_password "$CUR_PW" "$DESIRED_PW"; then
      write_secret "$PREV_FILE" "$CUR_PW"
      write_secret "$CUR_FILE" "$DESIRED_PW"
      log "root password rotated to desired"
      break
    fi
  fi

  # If previous cached works, rotate to desired.
  if [ -n "$PREV_PW" ] && try_auth "$PREV_PW"; then
    log "detected root password mismatch; rotating using cached previous password"
    if rotate_root_password "$PREV_PW" "$DESIRED_PW"; then
      # Keep prev as-is; set current to desired
      write_secret "$CUR_FILE" "$DESIRED_PW"
      log "root password rotated to desired"
      break
    fi
  fi

  waited=$((waited + 2))
  if [ "$waited" -ge "$max_wait" ]; then
    log "server did not become accessible with desired/cached passwords; leaving as-is"
    break
  fi
  sleep 2
done

# Keep container alive as long as the original entrypoint is running
wait "$child"
