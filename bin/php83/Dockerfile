# Use the official PHP 8.3 Apache image as the base
FROM php:8.3-apache-bookworm

# Suppress debconf complaints when installing apt packages
ARG DEBIAN_FRONTEND=noninteractive

# Update, upgrade, and install required packages in a single RUN layer to reduce image size
RUN apt-get update --fix-missing && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
        apt-utils \
        cron \
        supervisor \
        nano \
        vim \
        wget \
        curl \
        git \
        unzip \
        zip \
        dialog \
        libsqlite3-dev \
        default-mysql-client \
        zlib1g-dev \
        libzip-dev \
        libicu-dev \
        build-essential \
        libonig-dev \
        iputils-ping \
        libcurl4-openssl-dev \
        libmagickwand-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        libmemcached-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install Composer globally
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Install and configure PHP extensions
RUN docker-php-ext-install \
        pdo_mysql \
        pdo_sqlite \
        bcmath \
        mysqli \
        curl \
        zip \
        intl \
        mbstring \
        gettext \
        calendar \
        exif && \
    docker-php-ext-configure gd --enable-gd --with-freetype --with-jpeg && \
    docker-php-ext-install gd

# Install Redis PHP extension via PECL
RUN pecl install redis && docker-php-ext-enable redis

# Install Memcached PHP extension via PECL
RUN pecl install memcached && docker-php-ext-enable memcached

# Install Xdebug
RUN pecl install xdebug && docker-php-ext-enable xdebug

# Install mhsendmail for Mailpit
RUN curl -Lsf 'https://github.com/mailhog/mhsendmail/releases/download/v0.2.0/mhsendmail_linux_amd64' -o /usr/local/bin/mhsendmail && \
    chmod +x /usr/local/bin/mhsendmail

# Install Imagick PHP extension from a specific commit
ARG IMAGICK_COMMIT="28f27044e435a2b203e32675e942eb8de620ee58"
RUN git clone https://github.com/Imagick/imagick /usr/local/src/imagick && \
    cd /usr/local/src/imagick && \
    git checkout ${IMAGICK_COMMIT} && \
    phpize && ./configure && make && make install && \
    rm -rf /usr/local/src/imagick && \
    docker-php-ext-enable imagick

# Enable necessary Apache modules
RUN a2enmod ssl rewrite headers

# Create required directories and files
RUN mkdir -p /etc/apache2/ssl /var/log/{cron,supervisor} && \
    touch /var/log/cron.log /var/log/supervisor/supervisord.log

# Copy custom cron jobs and Supervisor configuration
COPY supervisord.conf /etc/supervisor/supervisord.conf



# Clean up unnecessary files to reduce image size
RUN rm -rf /usr/src/* /tmp/* /var/tmp/*

# Set the default command to start Supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]