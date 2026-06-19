# ── builder ────────────────────────────────────────────────────────────────
# Identical to the upstream build stage: installs PHP + Node, runs Composer
# and npm to compile all assets, then discards build tools.
FROM php:8.5-cli AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git gnupg libicu-dev libzip-dev unzip \
    && docker-php-ext-install -j"$(nproc)" intl zip \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && curl -sS https://getcomposer.org/installer | php -- \
       --install-dir=/usr/local/bin --filename=composer \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . /app

RUN composer install --no-dev --prefer-dist --no-interaction --no-progress \
    && npm install --legacy-peer-deps --no-audit --no-fund \
    && npm run build:templates \
    && npm run build:css \
    && npm run build:js \
    && rm -rf node_modules \
    && rm -rf var/log/* var/cache/twig/* var/cache/profiler/*

# ── runtime ────────────────────────────────────────────────────────────────
# Alpine-based php-fpm + nginx replaces php:8.5-apache (Debian ~490 MB).
# Final image is ~200-300 MB instead of ~900 MB.
FROM php:8.5-fpm-alpine AS runtime

RUN apk add --no-cache nginx icu-data-full icu-libs libzip \
    && apk add --no-cache --virtual .build-deps libzip-dev icu-dev \
    && docker-php-ext-install -j"$(nproc)" pdo_mysql intl zip \
    && apk del .build-deps \
    && rm -rf /var/cache/apk/*

# Nginx vhost — replicates public/.htaccess front-controller routing and
# preserves the Authorization header (needed for CalDAV basic auth passthrough).
RUN cat > /etc/nginx/http.d/default.conf <<'NGINX'
server {
    listen 80;
    server_name _;
    root /app/public;
    index index.php;

    location / {
        try_files $uri /index.php$is_args$args;
    }

    location ~ ^/index\.php(/|$) {
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_split_path_info ^(.+\.php)(/.*)$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;
        fastcgi_param HTTP_AUTHORIZATION $http_authorization;
        internal;
    }

    # Block direct access to any other .php file.
    location ~ \.php$ {
        return 404;
    }
}
NGINX

WORKDIR /app

COPY --from=builder --chown=www-data:www-data /app /app

RUN chmod -R 750 /app/var /app/config

ENV AGENDAV_ENVIRONMENT=prod

EXPOSE 80

# php-fpm in background, nginx in foreground (holds the container alive).
CMD ["sh", "-c", "php-fpm -D && exec nginx -g 'daemon off;'"]
