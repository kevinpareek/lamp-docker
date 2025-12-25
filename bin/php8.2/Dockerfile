# ============================================
# PHP 8.2 Production Ready Docker Image
# Optimized for Performance & Security
# ============================================
FROM php:8.2-apache-bookworm AS base

LABEL maintainer="PHP Turbo Stack <github.com/kevinpareek/turbo-stack>"
LABEL version="2.0"
LABEL description="Production-ready PHP 8.2 with Apache, Redis, Imagick"
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
        # Essential runtime tools
        cron \
        supervisor \
        curl \
        wget \
        git \
        unzip \
        zip \
        ca-certificates \
        openssl \
        # Database client
        default-mysql-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/*

# ============================================
# Install PHP Extensions (Optimized)
# ============================================
COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/

RUN set -eux; \
    install-php-extensions \
        bcmath \
        bz2 \
        calendar \
        ctype \
        dba \
        dom \
        enchant \
        exif \
        ffi \
        fileinfo \
        ftp \
        gd \
        gettext \
        gmp \
        iconv \
        igbinary \
        imagick \
        imap \
        intl \
        mbstring \
        memcached \
        mongodb \
        msgpack \
        mysqli \
        odbc \
        opcache \
        pcntl \
        pdo_dblib \
        pdo_firebird \
        pdo_mysql \
        pdo_odbc \
        pdo_pgsql \
        pdo_sqlite \
        pgsql \
        phar \
        posix \
        readline \
        redis \
        shmop \
        simplexml \
        soap \
        sockets \
        sodium \
        sqlite3 \
        sysvmsg \
        sysvsem \
        sysvshm \
        tidy \
        tokenizer \
        xml \
        xmlreader \
        xmlrpc \
        xmlwriter \
        xsl \
        zip \
        ioncube_loader

# ============================================
# Install Xdebug (Conditional)
# ============================================
RUN set -eux; \
    if [ "${INSTALL_XDEBUG}" = "true" ]; then \
        install-php-extensions xdebug; \
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
    && a2enmod ssl rewrite headers expires deflate proxy proxy_http remoteip \
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
