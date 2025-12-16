# ============================================
# Nginx Reverse Proxy with Brotli & Zstd
# ============================================
FROM alpine:3.20

LABEL maintainer="PHP Turbo Stack <github.com/kevinpareek/turbo-stack>"
LABEL version="2.0"
LABEL description="Nginx reverse proxy with Brotli and Zstd compression"
LABEL org.opencontainers.image.source="https://github.com/kevinpareek/turbo-stack"

# Install Nginx, Brotli module, Zstd module, gettext (for envsubst), and netcat
RUN apk add --no-cache nginx nginx-mod-http-brotli nginx-mod-http-zstd gettext curl netcat-openbsd openssl

# Forward logs to Docker
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# Copy custom nginx.conf
COPY nginx.conf /etc/nginx/nginx.conf

# Create directory for extra configs and templates
RUN mkdir -p /etc/nginx/extra-conf.d /etc/nginx/templates /var/www/html /etc/nginx/ssl-sites

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Health Check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost/nginx-health || exit 1

# Expose ports
EXPOSE 80 443

CMD ["/entrypoint.sh"]
