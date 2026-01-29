#!/bin/bash
set -e

PHP_VERSION="8.3"
APP_DIR="/var/www/paymenter"
NGINX_CONF="/etc/nginx/sites-available/paymenter.conf"
SERVICE_FILE="/etc/systemd/system/paymenter.service"

install_ssl() {
    apt -y install certbot python3-certbot-nginx
    certbot --nginx -d "$DOMAIN" \
      --non-interactive --agree-tos -m admin@"$DOMAIN" --redirect || true
}

install_paymenter() {
    read -p "🌐 Enter domain name: " DOMAIN
    read -s -p "🔑 Enter DB password: " DB_PASSWORD
    echo

    apt update && apt upgrade -y
    apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg unzip git redis-server nginx

    add-apt-repository -y ppa:ondrej/php
    apt update
    apt install -y \
    php$PHP_VERSION php$PHP_VERSION-{cli,fpm,common,gd,mysql,mbstring,bcmath,xml,curl,zip,intl,redis}

    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash -s -- --mariadb-server-version="mariadb-10.11"
    apt update && apt install -y mariadb-server

    if ! command -v composer &>/dev/null; then
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi

    mysql -e "CREATE DATABASE IF NOT EXISTS paymenter;"
    mysql -e "CREATE USER IF NOT EXISTS 'paymenter'@'localhost' IDENTIFIED BY '$DB_PASSWORD';"
    mysql -e "GRANT ALL PRIVILEGES ON paymenter.* TO 'paymenter'@'localhost'; FLUSH PRIVILEGES;"

    rm -rf $APP_DIR
    mkdir -p $APP_DIR
    cd $APP_DIR
    curl -Lo paymenter.tar.gz https://github.com/paymenter/paymenter/releases/latest/download/paymenter.tar.gz
    tar -xzf paymenter.tar.gz && rm paymenter.tar.gz

    cp .env.example .env
    sed -i "s|APP_URL=.*|APP_URL=https://$DOMAIN|" .env
    sed -i "s/^DB_DATABASE=.*/DB_DATABASE=paymenter/" .env
    sed -i "s/^DB_USERNAME=.*/DB_USERNAME=paymenter/" .env
    sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env
    sed -i "s/^QUEUE_CONNECTION=.*/QUEUE_CONNECTION=redis/" .env
    sed -i "s/^CACHE_DRIVER=.*/CACHE_DRIVER=redis/" .env
    sed -i "s/^SESSION_DRIVER=.*/SESSION_DRIVER=redis/" .env

    chown -R www-data:www-data $APP_DIR
    sudo -u www-data composer install --no-dev --optimize-autoloader
    sudo -u www-data php artisan key:generate --force
    sudo -u www-data php artisan storage:link
    sudo -u www-data php artisan migrate --force --seed

    cat <<EOF > $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;
    root $APP_DIR/public;
    index index.php;

    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php$PHP_VERSION-fpm.sock;
    }
}
EOF

    ln -sf $NGINX_CONF /etc/nginx/sites-enabled/paymenter.conf
    nginx -t && systemctl reload nginx

    install_ssl

    cat <<EOF > $SERVICE_FILE
[Unit]
Description=Paymenter Queue Worker
After=redis-server.service

[Service]
User=www-data
ExecStart=/usr/bin/php $APP_DIR/artisan queue:work --sleep=3 --tries=3
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now paymenter

    echo "✅ Paymenter Installed Successfully"
    echo "👉 https://$DOMAIN"
}

create_user() {
    cd $APP_DIR || { echo "❌ Paymenter not installed"; exit 1; }
    echo "1) Admin User"
    echo "2) Normal User"
    read -p "Select user type: " UT

    if [ "$UT" == "1" ]; then
        sudo -u www-data php artisan app:user:create --admin
    else
        sudo -u www-data php artisan app:user:create
    fi
}

uninstall_paymenter() {
    read -p "⚠️ Are you sure you want to UNINSTALL Paymenter? (yes/no): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then exit 0; fi

    systemctl stop paymenter || true
    systemctl disable paymenter || true
    rm -f $SERVICE_FILE

    rm -rf $APP_DIR
    rm -f /etc/nginx/sites-enabled/paymenter.conf
    rm -f /etc/nginx/sites-available/paymenter.conf
    systemctl reload nginx

    mysql -e "DROP DATABASE IF EXISTS paymenter;"
    mysql -e "DROP USER IF EXISTS 'paymenter'@'localhost';"

    echo "🗑️ Paymenter completely removed"
}

echo "=============================="
echo " PAYMENTER MANAGEMENT SCRIPT "
echo "=============================="
echo "1) Install Paymenter"
echo "2) Create New User"
echo "3) Uninstall Paymenter"
read -p "Select option: " CHOICE

case $CHOICE in
    1) install_paymenter ;;
    2) create_user ;;
    3) uninstall_paymenter ;;
    *) echo "❌ Invalid option" ;;
esac
