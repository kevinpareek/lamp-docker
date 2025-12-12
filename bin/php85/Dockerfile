# ============================================
# PHP 8.5 RC Production Ready Docker Image
# NOTE: PHP 8.5 is in development (RC stage)
# ============================================
FROM php:8.5-rc-apache-bookworm

LABEL maintainer="LAMP Docker <github.com/kevinpareek/lamp-docker>"
LABEL version="2.0"
LABEL description="PHP 8.5 RC with Apache, Redis, Imagick"

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
# Install System Dependencies
# ============================================
RUN set -eux; \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        cron \
        supervisor \
        curl \
        wget \
        git \
        unzip \
        zip \
        ca-certificates \
        default-mysql-client \
        libsqlite3-dev \
        zlib1g-dev \
        libzip-dev \
        libicu-dev \
        libonig-dev \
        libcurl4-openssl-dev \
        libssl-dev \
        libmagickwand-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libavif-dev \
        autoconf \
        pkg-config \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ============================================
# Install PHP Extensions
# ============================================
RUN set -eux; \
    docker-php-ext-configure gd \
        --enable-gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
        --with-avif \
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
        gd

# ============================================
# Install PECL Extensions
# ============================================
RUN set -eux; \
    pecl channel-update pecl.php.net \
    && pecl install -o -f redis apcu imagick \
    && docker-php-ext-enable redis apcu imagick \
    && pecl clear-cache \
    && rm -rf /tmp/pear

# ============================================
# Install Xdebug (Conditional - from source for PHP 8.5)
# ============================================
RUN set -eux; \
    if [ "${INSTALL_XDEBUG}" = "true" ]; then \
        git clone https://github.com/xdebug/xdebug.git /tmp/xdebug \
        && cd /tmp/xdebug \
        && phpize \
        && ./configure --enable-xdebug \
        && make -j"$(nproc)" \
        && make install \
        && docker-php-ext-enable xdebug \
        && rm -rf /tmp/xdebug; \
    fi

# ============================================
# Install Composer
# ============================================
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

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
    a2enmod ssl rewrite headers expires deflate proxy proxy_http \
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
# Copy Configuration
# ============================================
COPY supervisord.conf /etc/supervisor/supervisord.conf

# ============================================
# Health Check
# ============================================
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost/ || exit 1

EXPOSE 80 443

CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
