# ============================================
# MySQL 8.0 Production Ready Docker Image
# ============================================
FROM mysql:8.0

LABEL maintainer="PHP Turbo Stack <github.com/kevinpareek/turbo-stack>"
LABEL version="2.0"
LABEL description="Production-ready MySQL 8.0 with optimized settings"
LABEL org.opencontainers.image.source="https://github.com/kevinpareek/turbo-stack"

# ============================================
# Enable mysql_native_password for compatibility
# ============================================
RUN echo "[mysqld]" >> /etc/mysql/my.cnf && \
    echo "mysql_native_password=ON" >> /etc/mysql/my.cnf

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
