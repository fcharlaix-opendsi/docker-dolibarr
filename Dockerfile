ARG ARCH=

FROM ${ARCH}php:7.4-fpm-alpine

LABEL maintainer="Florian Charlaix <fcharlaix@open-dsi.fr>"

ENV DOLI_VERSION 2022.5.2

ENV DOLI_DB_TYPE mysqli
ENV DOLI_DB_HOST mysql
ENV DOLI_DB_HOST_PORT 3306
ENV DOLI_DB_NAME dolidb

ENV DOLI_URL_ROOT 'http://localhost'

ENV WWW_USER_ID 33
ENV WWW_GROUP_ID 33

ENV PHP_INI_DATE_TIMEZONE 'UTC'
ENV PHP_INI_MEMORY_LIMIT 256M

RUN apk add --no-cache \
        imap-dev \
        freetype-dev \
        libjpeg-turbo-dev \
        krb5-dev \
        openldap-dev \
        libpng-dev \
        libpq-dev \
        libxml2-dev \
        libzip-dev \
        icu-dev \
        icu-data-full \
        mariadb-client \
        postgresql-client

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) calendar intl mysqli pdo_mysql gd soap zip \
    && docker-php-ext-configure pgsql -with-pgsql \
    && docker-php-ext-install pdo_pgsql pgsql \
    && docker-php-ext-configure ldap --with-libdir=lib/$(gcc -dumpmachine)/ \
    && docker-php-ext-install -j$(nproc) ldap \
    && docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
    && docker-php-ext-install imap \
    && mv ${PHP_INI_DIR}/php.ini-production ${PHP_INI_DIR}/php.ini

EXPOSE 9000
HEALTHCHECK CMD netstat -an | grep 9000 > /dev/null; if [ 0 != $? ]; then exit 1; fi;
VOLUME /var/www/documents
VOLUME /var/www/html

COPY docker-run.sh /usr/local/bin/
COPY cron.sh /usr/local/bin/
ENTRYPOINT ["docker-run.sh"]

CMD ["php-fpm"]
