# ============================================
# MariaDB 10.4 Production Ready Docker Image
# ============================================
FROM mariadb:10.4

LABEL maintainer="PHP Turbo Stack <github.com/kevinpareek/turbo-stack>"
LABEL version="2.0"
LABEL description="Production-ready MariaDB 10.4 with optimized settings"
LABEL org.opencontainers.image.source="https://github.com/kevinpareek/turbo-stack"

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
    CMD mysqladmin ping -h localhost -u root -p"${MYSQL_ROOT_PASSWORD}" --silent

EXPOSE 3306
