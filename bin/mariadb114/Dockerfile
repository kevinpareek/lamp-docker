# ============================================
# MariaDB 11.4 Production Ready Docker Image
# ============================================
FROM mariadb:11.4

LABEL maintainer="LAMP Docker <github.com/kevinpareek/lamp-docker>"
LABEL version="2.0"
LABEL description="Production-ready MariaDB 11.4 with optimized settings"
LABEL org.opencontainers.image.source="https://github.com/kevinpareek/lamp-docker"

# ============================================
# Environment Variables
# ============================================
ENV MARIADB_AUTO_UPGRADE=1 \
    MARIADB_DISABLE_UPGRADE_BACKUP=1 \
    TZ=Asia/Kolkata

# ============================================
# Copy Custom Configuration
# ============================================


# ============================================
# Create Log Directory
# ============================================
RUN mkdir -p /var/log/mysql \
    && chown -R mysql:mysql /var/log/mysql \
    && chmod 755 /var/log/mysql

# ============================================
# Health Check
# ============================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD mariadb-admin ping -h localhost -u root -p"${MYSQL_ROOT_PASSWORD}" --silent

EXPOSE 3306
