#!/bin/bash

# Function to install SSL using Certbot
install_ssl() {
    echo "Installing Certbot and configuring SSL for $1..."
    apt -y install certbot python3-certbot-nginx
    certbot --nginx -d $1
    echo "SSL configured successfully."
}

# Prompt for database password
read -p "Enter the database password for Paymenter: " DB_PASSWORD

# Setup database
mysql -e "SELECT 1 FROM mysql.db WHERE Db='paymenter'" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    read -p "The database 'paymenter' already exists. Do you want to delete and recreate it? (Y/N): " recreate_db_choice
    if [ "$recreate_db_choice" = "Y" ] || [ "$recreate_db_choice" = "y" ]; then
        mysql -e "DROP DATABASE IF EXISTS paymenter;"
        mysql -e "CREATE DATABASE paymenter;"
    else
        echo "Skipping database creation."
    fi
else
    mysql -e "CREATE DATABASE paymenter;"
fi

mysql -e "CREATE USER IF NOT EXISTS 'paymenter'@'127.0.0.1' IDENTIFIED BY '$DB_PASSWORD';"
mysql -e "GRANT ALL PRIVILEGES ON paymenter.* TO 'paymenter'@'127.0.0.1' WITH GRANT OPTION;"

# Install dependencies
apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version="mariadb-10.11"
apt update
apt -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server

# Install Composer
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

# Download Paymenter
mkdir /var/www/paymenter
cd /var/www/paymenter
curl -Lo paymenter.tar.gz https://github.com/paymenter/paymenter/releases/latest/download/paymenter.tar.gz
tar -xzvf paymenter.tar.gz
chmod -R 755 storage/* bootstrap/cache/

# Configure Nginx
read -p "Enter your domain name or IP address: " domain
cat <<EOF > /etc/nginx/sites-available/paymenter.conf
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    root /var/www/paymenter/public;
    index index.php;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
    }
}
EOF

ln -s /etc/nginx/sites-available/paymenter.conf /etc/nginx/sites-enabled/
systemctl restart nginx

# Ask user if they want SSL
read -p "Do you want to install SSL for your domain? (Y/N): " ssl_choice

if [ "$ssl_choice" = "Y" ] || [ "$ssl_choice" = "y" ]; then
    install_ssl $domain
fi

# Configure Paymenter
cp .env.example .env
composer install --no-dev --optimize-autoloader
php artisan key:generate --force
php artisan storage:link
echo "DB_DATABASE=paymenter" >> .env
echo "DB_USERNAME=paymenter" >> .env
echo "DB_PASSWORD=$DB_PASSWORD" >> .env

# Run migrations
php artisan migrate --force --seed

# Set permissions
chown -R www-data:www-data /var/www/paymenter/*

# Configure cronjob
echo "* * * * * php /var/www/paymenter/artisan schedule:run >> /dev/null 2>&1" | crontab -

# Create queue worker
cat <<EOF > /etc/systemd/system/paymenter.service
[Unit]
Description=Paymenter Queue Worker
[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/paymenter/artisan queue:work
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now paymenter.service

#Create First User
cd /var/www/paymenter
php artisan p:user:create

echo "Paymenter installation complete."
