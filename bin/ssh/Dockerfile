# SSH Server for per-app SSH/SFTP access
FROM alpine:3.20

# Install SSH server and useful tools
RUN apk add --no-cache \
    openssh-server \
    openssh-sftp-server \
    bash \
    jq \
    openssl \
    curl \
    wget \
    git \
    nano \
    vim \
    htop \
    rsync \
    zip \
    unzip \
    shadow

# Create www-data group (matching PHP container)
RUN addgroup -g 82 -S www-data 2>/dev/null || true

# User management scripts directory
RUN mkdir -p /etc/ssh.d /var/run/sshd

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Users config directory (mounted from host)
VOLUME /etc/ssh.d

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
