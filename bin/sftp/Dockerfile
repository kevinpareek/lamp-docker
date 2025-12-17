# SFTP Server for per-app SSH/SFTP access
FROM atmoz/sftp:alpine

# Install additional tools
RUN apk add --no-cache \
    bash \
    jq \
    openssl

# User management scripts directory
RUN mkdir -p /etc/sftp.d /var/run/sftp

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Users config directory (mounted from host)
VOLUME /etc/sftp.d

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
