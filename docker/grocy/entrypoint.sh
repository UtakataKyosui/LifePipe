#!/bin/sh
set -eu

data=/var/www/html/data
[ -f "$data/config.php" ] || cp /var/www/html/config-dist.php "$data/config.php"
chown -R www-data:www-data "$data"

php-fpm -D
exec nginx -g 'daemon off;'
