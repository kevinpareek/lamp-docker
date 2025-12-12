FROM mysql:8.4
RUN echo "[mysqld]" >> /etc/mysql/my.cnf
RUN echo "mysql_native_password=ON" >> /etc/mysql/my.cnf

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

