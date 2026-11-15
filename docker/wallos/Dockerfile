FROM php:8.3-fpm-alpine AS extensions
RUN apk add --no-cache $PHPIZE_DEPS libpng-dev libjpeg-turbo-dev freetype-dev libwebp-dev icu-dev libzip-dev && \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp && \
    docker-php-ext-install -j2 gd intl zip calendar

FROM php:8.3-fpm-alpine
RUN apk upgrade --no-cache && \
    apk add --no-cache dumb-init shadow curl nginx dcron tzdata \
        libpng libjpeg-turbo freetype libwebp libzip icu-libs icu-data-full
COPY --from=extensions /usr/local/lib/php/extensions /usr/local/lib/php/extensions
COPY --from=extensions /usr/local/etc/php/conf.d /usr/local/etc/php/conf.d

WORKDIR /var/www/html
COPY *.php robots.txt service-worker.js ./
COPY api ./api
COPY db ./db
COPY endpoints ./endpoints
COPY images ./images
COPY includes ./includes
COPY libs ./libs
COPY migrations ./migrations
COPY scripts ./scripts
COPY styles ./styles
COPY webfonts ./webfonts
COPY --chmod=755 startup.sh ./startup.sh
COPY nginx.conf /etc/nginx/nginx.conf
COPY nginx.default.conf /etc/nginx/http.d/default.conf
COPY cronjobs /etc/cron.d/cronjobs

RUN sed -i 's/\r$//' /etc/cron.d/cronjobs && \
    chmod 0644 /etc/cron.d/cronjobs && \
    /usr/bin/crontab /etc/cron.d/cronjobs && \
    mkdir /var/log/cron && \
    chown -R www-data:www-data /var/www/html && \
    echo 'pm.max_children = 15' >> /usr/local/etc/php-fpm.d/zz-docker.conf && \
    echo 'pm.max_requests = 500' >> /usr/local/etc/php-fpm.d/zz-docker.conf && \
    printf 'upload_max_filesize = 256M\npost_max_size = 256M\n' > /usr/local/etc/php/conf.d/wallos-uploads.ini

EXPOSE 80
HEALTHCHECK --interval=2m --timeout=2s --start-period=20s --start-interval=5s --retries=3 \
    CMD ["curl", "-fsS", "http://127.0.0.1/health.php"]
ENTRYPOINT ["dumb-init", "--"]
CMD ["/var/www/html/startup.sh"]
