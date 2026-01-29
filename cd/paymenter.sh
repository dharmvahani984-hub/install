#!/bin/bash
set -e

### VARIABLES
PHP_VERSION="8.3"
APP_DIR="/var/www/paymenter"
NGINX_CONF="/etc/nginx/sites-available/paymenter.conf"

### FUNCTIONS
install_ssl() {
    echo "🔐 Installing SSL for $1"
    apt -y install certbot python3-certbot-nginx
    certbot --nginx -d "$1" \
      --non-interactive \
      --agree-tos \
      -m admin@"$1" \
      --redirect || true
}

### INPUTS
read -p "🌐 Enter domain name (example.com): " DOMAIN
read -s -p "🔑 Enter DB password for Paymenter: " DB_PASSWORD
echo

### SYSTEM UPDATE
apt update && apt upgrade -y

### DEPENDENCIES
apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg unzip git redis-server

### PHP
add-apt-repository -y ppa:ondrej/php
apt update
apt install -y \
php$PHP_VERSION php$PHP_VERSION-{cli,fpm,common,gd,mysql,mbstring,bcmath,xml,curl,zip,intl}

### MARIADB
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash -s -- --mariadb-server-version="mariadb-10.11"
apt update
apt install -y mariadb-server

### NGINX
apt install -y nginx

### COMPOSER
if ! command -v composer &>/dev/null; then
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
fi

### DATABASE SETUP
DB_EXISTS=$(mysql -N -s -e "SHOW DATABASES LIKE 'paymenter';")
if [ "$DB_EXISTS" = "paymenter" ]; then
  read -p "⚠️ Database exists. Recreate? (y/N): " DB_RE
  if [[ "$DB_RE" =~ ^[Yy]$ ]]; then
    mysql -e "DROP DATABASE paymenter;"
    mysql -e "CREATE DATABASE paymenter;"
  fi
else
  mysql -e "CREATE DATABASE paymenter;"
fi

mysql -e "CREATE USER IF NOT EXISTS 'paymenter'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
mysql -e "GRANT ALL PRIVILEGES ON paymenter.* TO 'paymenter'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

### DOWNLOAD PAYMENTER
rm -rf $APP_DIR
mkdir -p $APP_DIR
cd $APP_DIR
curl -Lo paymenter.tar.gz https://github.com/paymenter/paymenter/releases/latest/download/paymenter.tar.gz
tar -xzf paymenter.tar.gz
rm paymenter.tar.gz

### PERMISSIONS
chown -R www-data:www-data $APP_DIR
chmod -R 755 storage bootstrap/cache

### ENV SETUP
cp .env.example .env

sed -i "s/^APP_ENV=.*/APP_ENV=production/" .env
sed -i "s/^APP_DEBUG=.*/APP_DEBUG=false/" .env
sed -i "s/^APP_URL=.*/APP_URL=https:\/\/$DOMAIN/" .env

sed -i "s/^DB_DATABASE=.*/DB_DATABASE=paymenter/" .env
sed -i "s/^DB_USERNAME=.*/DB_USERNAME=paymenter/" .env
sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env

sed -i "s/^QUEUE_CONNECTION=.*/QUEUE_CONNECTION=redis/" .env
sed -i "s/^CACHE_DRIVER=.*/CACHE_DRIVER=redis/" .env
sed -i "s/^SESSION_DRIVER=.*/SESSION_DRIVER=redis/" .env

### INSTALL APP
composer install --no-dev --optimize-autoloader
php artisan key:generate --force
php artisan storage:link

### MIGRATE
php artisan migrate --force --seed

### PHP LIMITS
cat <<EOF > /etc/php/$PHP_VERSION/fpm/conf.d/99-paymenter.ini
upload_max_filesize=64M
post_max_size=64M
memory_limit=512M
max_execution_time=300
EOF

systemctl restart php$PHP_VERSION-fpm

### NGINX CONFIG (CLOUDFLARE SAFE)
cat <<EOF > $NGINX_CONF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root $APP_DIR/public;

    index index.php;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header Referrer-Policy "strict-origin";

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
    }

    location ~ /\. {
        deny all;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-enabled/paymenter.conf
ln -s $NGINX_CONF /etc/nginx/sites-enabled/paymenter.conf

nginx -t && systemctl reload nginx

### SSL
read -p "🔐 Install SSL now? (y/N): " SSL_YES
if [[ "$SSL_YES" =~ ^[Yy]$ ]]; then
  install_ssl "$DOMAIN"
fi

### CRON (WWW-DATA)
(crontab -u www-data -l 2>/dev/null; echo "* * * * * php $APP_DIR/artisan schedule:run >> /dev/null 2>&1") | crontab -u www-data -

### QUEUE WORKER
cat <<EOF > /etc/systemd/system/paymenter.service
[Unit]
Description=Paymenter Queue Worker
After=network.target redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php $APP_DIR/artisan queue:work --sleep=3 --tries=3
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now paymenter

### FINAL USER
php artisan p:user:create

echo
echo "✅ PAYMENTER INSTALLATION COMPLETE"
echo "🌐 https://$DOMAIN"
echo "⚡ Optimized for Pterodactyl & Cloudflare"
