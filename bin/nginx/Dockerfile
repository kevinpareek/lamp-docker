FROM alpine:3.20

# Install Nginx, Brotli module, Zstd module, gettext (for envsubst), and netcat
RUN apk add --no-cache nginx nginx-mod-http-brotli nginx-mod-http-zstd nginx-mod-http-zstd gettext curl netcat-openbsd

# Forward logs to Docker
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# Copy custom nginx.conf
COPY nginx.conf /etc/nginx/nginx.conf

# Create directory for extra configs and templates
RUN mkdir -p /etc/nginx/extra-conf.d /etc/nginx/templates /var/www/html

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports
EXPOSE 80 443

CMD ["/entrypoint.sh"]
