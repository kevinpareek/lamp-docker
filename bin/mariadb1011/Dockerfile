FROM mariadb:10.11

COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/healthcheck.sh
COPY my.cnf /etc/mysql/conf.d/custom.cnf
