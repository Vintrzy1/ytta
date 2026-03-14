#!/bin/bash

# Pastikan script dijalankan sebagai root
if [[ $EUID -ne 0 ]]; then
   echo "⚠️ Script ini harus dijalankan sebagai root (gunakan sudo su)."
   exit 1
fi

clear
echo "========================================================="
echo "       🚀 REVIACTYL UNOFFICIAL AUTO INSTALLER 🚀         "
echo "========================================================="
echo "Pilih menu instalasi di bawah ini:"
echo ""
echo "  [1] Install Panel Reviactyl (Web UI & Database)"
echo "  [2] Install Wings (Daemon/Node Server)"
echo "  [3] Uninstall Panel & Wings (Hapus Semua Data)"
echo "  [4] Keluar"
echo ""
echo "========================================================="
read -p "Masukkan pilihan Anda [1-4]: " MENU_OPTION

case $MENU_OPTION in
  1)
    echo "⚙️ Memulai Instalasi Panel Reviactyl..."
    sleep 2
    
    # Update & Install Dependencies
    apt update -y && apt-get purge -y cmdtest yarn && rm -f /usr/bin/yarn
    apt -y install software-properties-common curl ca-certificates gnupg
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt update -y
    apt -y install nodejs php8.1 php8.1-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx git redis-server unzip
    npm install -g yarn
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

    # Setup Panel & Database
    rm -rf /var/www/reviactyl && mkdir -p /var/www/reviactyl && cd /var/www/reviactyl
    git clone https://github.com/reviactyl/panel.git .
    cp .env.example .env
    chmod -R 755 storage/* bootstrap/cache/
    
    systemctl start mariadb
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS panel;"
    mysql -u root -e "CREATE USER IF NOT EXISTS 'reviactyl'@'127.0.0.1' IDENTIFIED BY 'vintrzy123';"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'reviactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "FLUSH PRIVILEGES;"

    export COMPOSER_ALLOW_SUPERUSER=1
    composer install --no-dev --optimize-autoloader
    yarn install && yarn build:production

    # Setup Nginx
    rm -f /etc/nginx/sites-enabled/default
    cat << 'EOF' > /etc/nginx/sites-available/reviactyl.conf
server {
    listen 80;
    server_name _;
    root /var/www/reviactyl/public;
    index index.html index.htm index.php;
    charset utf-8;
    location / { try_files $uri $uri/ /index.php?$query_string; }
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
    access_log off;
    error_log  /var/log/nginx/reviactyl.app-error.log error;
    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;
    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
    }
    location ~ /\.ht { deny all; }
}
EOF
    ln -s /etc/nginx/sites-available/reviactyl.conf /etc/nginx/sites-enabled/reviactyl.conf
    systemctl restart nginx
    
    (crontab -l 2>/dev/null; echo "* * * * * php /var/www/reviactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -
    
    echo "========================================================="
    echo "⚠️ TAHAP AKHIR PANEL: Siapkan Environment & Akun Admin!"
    echo "Info Database: Host=127.0.0.1 | Port=3306 | DB=panel | User=reviactyl | Pass=vintrzy123"
    echo "========================================================="
    php artisan key:generate --force
    php artisan p:environment:setup
    php artisan p:environment:database
    php artisan migrate --seed --force
    php artisan p:user:make
    chown -R www-data:www-data /var/www/reviactyl/*
    
    echo "✅ INSTALL PANEL SELESAI! Buka IP VPS di browser."
    ;;
    
  2)
    echo "⚙️ Memulai Instalasi Wings..."
    sleep 2
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod u+x /usr/local/bin/wings
    
    cat << 'EOF' > /etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service
[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable wings
    echo "✅ INSTALL WINGS SELESAI! Jangan lupa buat Node di Panel, lalu paste konfigurasi Wings ke /etc/pterodactyl/config.yml dan jalankan: systemctl start wings"
    ;;
    
  3)
    echo "🧨 PERINGATAN: Ini akan menghapus Reviactyl, Database, dan Wings!"
    read -p "Anda yakin ingin melanjutkan? (y/n): " UNINSTALL_CONFIRM
    if [[ "$UNINSTALL_CONFIRM" == "y" || "$UNINSTALL_CONFIRM" == "Y" ]]; then
        echo "🗑️ Menghapus data..."
        systemctl stop nginx wings > /dev/null 2>&1
        rm -rf /var/www/reviactyl
        rm -f /etc/nginx/sites-enabled/reviactyl.conf
        rm -f /etc/nginx/sites-available/reviactyl.conf
        rm -rf /etc/pterodactyl
        rm -f /usr/local/bin/wings
        rm -f /etc/systemd/system/wings.service
        mysql -u root -e "DROP DATABASE IF EXISTS panel;"
        mysql -u root -e "DROP USER IF EXISTS 'reviactyl'@'127.0.0.1';"
        systemctl daemon-reload
        systemctl restart nginx
        echo "✅ UNINSTALL SELESAI! Server sudah bersih."
    else
        echo "❌ Uninstall dibatalkan."
    fi
    ;;
    
  4)
    echo "👋 Keluar dari Installer..."
    exit 0
    ;;
    
  *)
    echo "❌ Pilihan tidak valid. Silakan jalankan ulang script."
    exit 1
    ;;
esac
