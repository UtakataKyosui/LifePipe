FROM php:8.5-cli-alpine@sha256:1ff5b45922ab30f418447c6089dbe2eba5f01e0b2742863d0327ac349305d70f AS composer
RUN apk add --no-cache git unzip
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --no-scripts --optimize-autoloader --ignore-platform-reqs

FROM node:24-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS assets
RUN apk add --no-cache git
WORKDIR /app
COPY package.json yarn.lock .yarnrc ./
RUN yarn install --frozen-lockfile

FROM php:8.5-fpm-alpine@sha256:951fb5b1780219b81d5daffa4cebef8e0077c537f3893d9790a5dfcd66ca334d AS extensions
RUN apk add --no-cache $PHPIZE_DEPS libpng-dev libjpeg-turbo-dev freetype-dev libwebp-dev icu-dev && \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp && \
    docker-php-ext-install -j2 gd intl

FROM php:8.5-fpm-alpine@sha256:951fb5b1780219b81d5daffa4cebef8e0077c537f3893d9790a5dfcd66ca334d
RUN apk add --no-cache nginx libpng libjpeg-turbo freetype libwebp icu-libs icu-data-full
COPY --from=extensions /usr/local/lib/php/extensions /usr/local/lib/php/extensions
COPY --from=extensions /usr/local/etc/php/conf.d /usr/local/etc/php/conf.d

WORKDIR /var/www/html
COPY app.php routes.php config-dist.php version.json grocy.openapi.json ./
COPY controllers ./controllers
COPY helpers ./helpers
COPY localization ./localization
COPY middleware ./middleware
COPY migrations ./migrations
COPY plugins ./plugins
COPY services ./services
COPY views ./views
COPY public ./public
COPY data ./data
COPY --from=composer /app/packages ./packages
COPY --from=assets /app/public/packages ./public/packages

COPY --from=config --chmod=644 nginx.conf /etc/nginx/http.d/default.conf
COPY --from=config --chmod=755 entrypoint.sh /entrypoint.sh

VOLUME /var/www/html/data
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD wget -q --spider http://127.0.0.1/login || exit 1
ENTRYPOINT ["/entrypoint.sh"]
