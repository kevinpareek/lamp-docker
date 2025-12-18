# ============================================
# PHP 8.3 Production Ready Docker Image
# Optimized for Performance & Security
# ============================================
FROM php:8.3-apache-bookworm AS base

LABEL maintainer="PHP Turbo Stack <github.com/kevinpareek/turbo-stack>"
LABEL version="2.0"
LABEL description="Production-ready PHP 8.3 with Apache, Redis, Imagick"
LABEL org.opencontainers.image.source="https://github.com/kevinpareek/turbo-stack"

# ============================================
# Build Arguments
# ============================================
ARG DEBIAN_FRONTEND=noninteractive
ARG INSTALL_XDEBUG=false

# ============================================
# Environment Variables
# ============================================
ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_HOME=/tmp/composer \
    COMPOSER_NO_INTERACTION=1

# ============================================
# Install System Dependencies (Single Layer)
# ============================================
RUN set -eux; \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        # Essential
        cron \
        supervisor \
        curl \
        wget \
        git \
        unzip \
        zip \
        ca-certificates \
        # Database
        default-mysql-client \
        # PHP Dependencies
        libsqlite3-dev \
        zlib1g-dev \
        libzip-dev \
        libicu-dev \
        libonig-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libmemcached-dev \
        # Image Processing
        libmagickwand-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libavif-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/*

# ============================================
# Install PHP Extensions (Optimized)
# ============================================
RUN set -eux; \
    # Configure GD with all formats
    docker-php-ext-configure gd \
        --enable-gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
        --with-avif \
    # Install all extensions in parallel
    && docker-php-ext-install -j"$(nproc)" \
        pdo_mysql \
        pdo_sqlite \
        mysqli \
        bcmath \
        zip \
        intl \
        mbstring \
        gettext \
        calendar \
        exif \
        opcache \
        pcntl \
        sockets \
        gd \
    # PECL Extensions
    && pecl channel-update pecl.php.net \
    && pecl install -o -f redis apcu imagick memcached \
    && docker-php-ext-enable redis apcu imagick memcached \
    && pecl clear-cache \
    && rm -rf /tmp/pear

# ============================================
# Install Xdebug (Conditional)
# ============================================
RUN set -eux; \
    if [ "${INSTALL_XDEBUG}" = "true" ]; then \
        pecl install xdebug \
        && docker-php-ext-enable xdebug \
        && pecl clear-cache; \
    fi

# ============================================
# Install Composer (Latest Stable)
# ============================================
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# ============================================
# Install WP-CLI
# ============================================
RUN curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

# ============================================
# Install mhsendmail
# ============================================
RUN curl -fsSL 'https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64' \
        -o /usr/local/bin/mhsendmail \
    && chmod +x /usr/local/bin/mhsendmail

# ============================================
# Apache Configuration
# ============================================
RUN set -eux; \
    echo "ServerName localhost" >> /etc/apache2/apache2.conf \
    && a2enmod ssl rewrite headers expires deflate proxy proxy_http \
    && { \
        echo 'ServerTokens Prod'; \
        echo 'ServerSignature Off'; \
        echo 'TraceEnable Off'; \
        echo 'Header always set X-Content-Type-Options "nosniff"'; \
        echo 'Header always set X-Frame-Options "SAMEORIGIN"'; \
        echo 'Header always set X-XSS-Protection "1; mode=block"'; \
    } >> /etc/apache2/conf-available/security.conf \
    && a2enconf security

# ============================================
# Setup Directories & Permissions
# ============================================
RUN set -eux; \
    mkdir -p /etc/apache2/ssl /var/log/{cron,supervisor} /var/www/html \
    && touch /var/log/cron.log /var/log/supervisor/supervisord.log \
    && chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html

# ============================================
# Health Check
# ============================================
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost/server-status || curl -sf http://localhost/ || exit 1

# ============================================
# Expose Ports
# ============================================
EXPOSE 80 443

# ============================================
# Entrypoint
# ============================================
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
