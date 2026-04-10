#!/bin/bash

# ============================================================
#   Auto Script Migrasi Pterodactyl Panel
#   GitHub  : https://github.com/SankaVollereii/Migrate-Pterodactyl
#   Version : 2.1.0 — Fully Automated
# ============================================================

trap 'log_error "Error pada line $LINENO"; exit 1' ERR

LOG_FILE="/root/migrate_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  ███████╗ █████╗ ███╗   ██╗██╗  ██╗ █████╗ "
    echo "  ██╔════╝██╔══██╗████╗  ██║██║ ██╔╝██╔══██╗"
    echo "  ███████╗███████║██╔██╗ ██║█████╔╝ ███████║"
    echo "  ╚════██║██╔══██║██║╚██╗██║██╔═██╗ ██╔══██║"
    echo "  ███████║██║  ██║██║ ╚████║██║  ██╗██║  ██║"
    echo "  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝"
    echo -e "${NC}"
    echo -e "${BOLD}  Auto Script Migrasi Pterodactyl Panel v2.1.0${NC}"
    echo -e "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

log_info()    { echo -e "  ${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "  ${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "  ${RED}[✗]${NC} $1"; }
log_step()    { echo -e "\n  ${CYAN}${BOLD}[>>]${NC}${BOLD} $1${NC}"; }
log_section() { echo -e "\n  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

validate_ip() {
    local ip="$1"
    if [ -z "$ip" ]; then
        log_error "IP tidak boleh kosong!"
        return 1
    fi
    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ ! "$ip" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        log_error "Format IP/hostname tidak valid: $ip"
        return 1
    fi
    return 0
}

cleanup_env() {
    unset MYSQL_PWD MYSQL_ROOT_PASS DB_PASSWORD NEW_VPS_PASS 2>/dev/null || true
}

START_TIME=0
timer_start() { START_TIME=$(date +%s); }
timer_show() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - START_TIME))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    if [ $mins -gt 0 ]; then
        log_info "Waktu eksekusi: ${BOLD}${mins}m ${secs}s${NC}"
    else
        log_info "Waktu eksekusi: ${BOLD}${secs}s${NC}"
    fi
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Script ini harus dijalankan sebagai root!"
        echo -e "  Gunakan: ${YELLOW}sudo bash migrate.sh${NC}"
        exit 1
    fi
}

detect_os() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt-get"
        PKG_UPDATE="apt-get update -qq"
        PKG_INSTALL="apt-get install -y -qq"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum update -y -q"
        PKG_INSTALL="yum install -y -q"
    else
        log_error "Package manager tidak dikenali (bukan apt/yum)!"
        exit 1
    fi
}

ensure_pkg() {
    local cmd="$1"
    local pkg="$2"
    if ! command -v "$cmd" &>/dev/null; then
        log_info "Menginstall ${pkg}..."
        $PKG_INSTALL "$pkg" > /dev/null 2>&1 && log_info "${pkg} berhasil diinstall." || {
            log_error "Gagal install ${pkg}!"
            exit 1
        }
    fi
}

# ============================================================
#   INSTALL DEPENDENCIES DI VPS BARU
# ============================================================
install_dependencies() {
    log_step "Mengecek & menginstall semua dependencies..."

    detect_os
    $PKG_UPDATE > /dev/null 2>&1

    local php_ver=""
    if [ "$PKG_MANAGER" = "apt-get" ]; then
        for v in 8.3 8.2 8.1; do
            if apt-cache show "php${v}" &>/dev/null 2>&1; then
                php_ver="$v"
                break
            fi
        done

        if [ -z "$php_ver" ]; then
            if grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
                log_info "Menambahkan repository PHP (ondrej/php)..."
                ensure_pkg "add-apt-repository" "software-properties-common"
                add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1
                $PKG_UPDATE > /dev/null 2>&1
            else
                log_info "Menambahkan repository PHP (sury.org) untuk Debian..."
                ensure_pkg "curl" "curl"
                curl -sSL https://packages.sury.org/php/apt.gpg | apt-key add - > /dev/null 2>&1
                echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
                $PKG_UPDATE > /dev/null 2>&1
            fi
            php_ver="8.3"
        fi
    elif [ "$PKG_MANAGER" = "yum" ]; then
        for v in 83 82 81; do
            if yum list available "php${v}" &>/dev/null 2>&1 || command -v php &>/dev/null; then
                php_ver="${v:0:1}.${v:1:1}"
                break
            fi
        done

        if [ -z "$php_ver" ]; then
            log_info "Menambahkan repository Remi untuk PHP..."
            ensure_pkg "curl" "curl"
            yum install -y -q epel-release > /dev/null 2>&1
            yum install -y -q https://rpms.remirepo.net/enterprise/remi-release-$(rpm -E %rhel).rpm > /dev/null 2>&1
            yum module enable -y php:remi-8.3 > /dev/null 2>&1 || true
            php_ver="8.3"
        fi
    fi

    log_info "Menggunakan PHP ${php_ver}"

    if ! command -v nginx &>/dev/null; then
        log_info "Menginstall Nginx..."
        $PKG_INSTALL nginx > /dev/null 2>&1
        systemctl enable nginx --quiet 2>/dev/null
        systemctl start nginx 2>/dev/null
        log_info "Nginx terinstall."
    else
        log_info "Nginx sudah ada, skip."
    fi

    if ! command -v mysql &>/dev/null; then
        log_info "Menginstall MariaDB..."
        $PKG_INSTALL mariadb-server mariadb-client > /dev/null 2>&1
        systemctl enable mariadb --quiet 2>/dev/null
        systemctl start mariadb 2>/dev/null
        log_info "MariaDB terinstall."
    else
        log_info "MariaDB sudah ada, skip."
    fi

    if ! command -v redis-cli &>/dev/null; then
        log_info "Menginstall Redis..."
        $PKG_INSTALL redis-server > /dev/null 2>&1
        systemctl enable redis-server --quiet 2>/dev/null
        systemctl start redis-server 2>/dev/null
        log_info "Redis terinstall."
    else
        log_info "Redis sudah ada, skip."
    fi

    if ! command -v php &>/dev/null; then
        log_info "Menginstall PHP ${php_ver} & ekstensi..."
        $PKG_INSTALL \
            "php${php_ver}" "php${php_ver}-cli" "php${php_ver}-fpm" \
            "php${php_ver}-mysql" "php${php_ver}-mbstring" "php${php_ver}-xml" \
            "php${php_ver}-bcmath" "php${php_ver}-curl" "php${php_ver}-zip" \
            "php${php_ver}-gd" "php${php_ver}-common" "php${php_ver}-redis" \
            > /dev/null 2>&1
        systemctl enable "php${php_ver}-fpm" --quiet 2>/dev/null
        systemctl start "php${php_ver}-fpm" 2>/dev/null
        log_info "PHP ${php_ver} terinstall."
    else
        log_info "PHP sudah ada ($(php -r 'echo PHP_VERSION;')), skip."
    fi

    if ! command -v composer &>/dev/null; then
        log_info "Menginstall Composer..."
        ensure_pkg "curl" "curl"
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer > /dev/null 2>&1
        log_info "Composer terinstall."
    else
        log_info "Composer sudah ada, skip."
    fi

    ensure_pkg "tar" "tar"
    ensure_pkg "unzip" "unzip"

    log_info "Semua dependencies siap."
}

# ============================================================
#   SETUP NGINX CONFIG DI VPS BARU
# ============================================================
setup_nginx() {
    log_step "Setup konfigurasi Nginx untuk Pterodactyl..."

    local php_ver
    php_ver=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)

    local nginx_conf
    if [ -d "/etc/nginx/sites-available" ]; then
        nginx_conf="/etc/nginx/sites-available/pterodactyl.conf"
    elif [ -d "/etc/nginx/conf.d" ]; then
        nginx_conf="/etc/nginx/conf.d/pterodactyl.conf"
    else
        log_warn "Direktori konfigurasi Nginx tidak ditemukan, membuat /etc/nginx/conf.d/"
        mkdir -p /etc/nginx/conf.d
        nginx_conf="/etc/nginx/conf.d/pterodactyl.conf"
    fi

    local domain
    domain=$(grep -w "^APP_URL" /var/www/pterodactyl/.env 2>/dev/null \
        | cut -d '=' -f2- | tr -d ' \r' | sed 's|https\?://||')
    domain=${domain:-"_"}

    if [ ! -f "$nginx_conf" ]; then
        cat > "$nginx_conf" <<NGINXEOF
server {
    listen 80;
    server_name ${domain};

    root /var/www/pterodactyl/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php${php_ver}-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINXEOF
        if [ -d "/etc/nginx/sites-enabled" ]; then
            ln -sf "$nginx_conf" /etc/nginx/sites-enabled/pterodactyl.conf 2>/dev/null
            rm -f /etc/nginx/sites-enabled/default 2>/dev/null
        fi
        nginx -t > /dev/null 2>&1 && systemctl reload nginx 2>/dev/null
        log_info "Konfigurasi Nginx dibuat untuk domain: ${domain}"
    else
        log_info "Konfigurasi Nginx sudah ada, skip."
    fi
}

# ============================================================
#   SETUP CRONJOB & QUEUE WORKER
# ============================================================
setup_cron_and_worker() {
    log_step "Setup Cronjob & Queue Worker..."

    local cron_entry="* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
    if ! crontab -l 2>/dev/null | grep -q "pterodactyl/artisan schedule:run"; then
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        log_info "Cronjob berhasil ditambahkan."
    else
        log_info "Cronjob sudah ada, skip."
    fi

    local service_file="/etc/systemd/system/pteroq.service"
    if [ ! -f "$service_file" ]; then
        cat > "$service_file" <<'SVCEOF'
[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
SVCEOF
        systemctl daemon-reload 2>/dev/null
        systemctl enable pteroq --quiet 2>/dev/null
        systemctl start pteroq 2>/dev/null
        log_info "Queue Worker (pteroq) berhasil disetup & dijalankan."
    else
        systemctl restart pteroq 2>/dev/null
        log_info "Queue Worker (pteroq) di-restart."
    fi
}

# ============================================================
#   OPSI 1: BACKUP DATA +  KIRIM KE VPS BARU
# ============================================================
run_backup() {
    log_section
    log_step "Memulai proses BACKUP di VPS Lama..."
    log_section

    detect_os

    ensure_pkg "sshpass" "sshpass"

    if [ ! -d "/var/www/pterodactyl" ]; then
        log_error "Folder /var/www/pterodactyl tidak ditemukan!"
        log_warn "Pastikan kamu menjalankan script ini di VPS yang benar (VPS LAMA)."
        exit 1
    fi

    cd /var/www/pterodactyl || { log_error "Gagal masuk ke /var/www/pterodactyl!"; exit 1; }

    log_step "Masukkan informasi VPS Baru untuk transfer otomatis..."
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} IP VPS Baru: ${NC}"
    read -r NEW_VPS_IP
    validate_ip "$NEW_VPS_IP" || exit 1
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Port SSH VPS Baru [22]: ${NC}"
    read -r NEW_VPS_PORT
    NEW_VPS_PORT=${NEW_VPS_PORT:-22}
    if ! [[ "$NEW_VPS_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_VPS_PORT" -lt 1 ] || [ "$NEW_VPS_PORT" -gt 65535 ]; then
        log_error "Port SSH tidak valid: $NEW_VPS_PORT (harus 1-65535)"
        exit 1
    fi
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Username SSH VPS Baru [root]: ${NC}"
    read -r NEW_VPS_USER
    NEW_VPS_USER=${NEW_VPS_USER:-root}
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Password SSH VPS Baru: ${NC}"
    read -s NEW_VPS_PASS
    echo ""
    if [ -z "$NEW_VPS_PASS" ]; then
        log_error "Password SSH tidak boleh kosong!"
        exit 1
    fi

    log_step "Menguji koneksi SSH ke VPS Baru (${NEW_VPS_IP})..."
    if ! sshpass -p "$NEW_VPS_PASS" ssh \
        -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -p "$NEW_VPS_PORT" \
        "${NEW_VPS_USER}@${NEW_VPS_IP}" "echo ok" &>/dev/null; then
        log_error "Tidak bisa terhubung ke VPS Baru! Periksa IP, port, username, dan password."
        exit 1
    fi
    log_info "Koneksi SSH ke VPS Baru berhasil."

    log_step "Mengaktifkan maintenance mode..."
    php artisan down --quiet 2>/dev/null \
        && log_info "Maintenance mode aktif." \
        || log_warn "Gagal maintenance mode, lanjut..."

    log_step "Membaca konfigurasi dari .env..."
    if [ ! -f ".env" ]; then
        log_error "File .env tidak ditemukan!"
        php artisan up --quiet 2>/dev/null
        exit 1
    fi

    DB_HOST=$(grep -w "^DB_HOST" .env | cut -d '=' -f2- | tr -d ' \r')
    DB_PORT=$(grep -w "^DB_PORT" .env | cut -d '=' -f2- | tr -d ' \r')
    DB_DATABASE=$(grep -w "^DB_DATABASE" .env | cut -d '=' -f2- | tr -d ' \r')
    DB_USERNAME=$(grep -w "^DB_USERNAME" .env | cut -d '=' -f2- | tr -d ' \r')
    DB_PASSWORD=$(grep -w "^DB_PASSWORD" .env | cut -d '=' -f2- | tr -d ' \r')
    DB_PORT=${DB_PORT:-3306}

    log_info "Database : ${DB_DATABASE} | Host: ${DB_HOST}:${DB_PORT}"

    log_step "Mem-backup database '${DB_DATABASE}'..."
    if MYSQL_PWD="$DB_PASSWORD" mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" \
        "$DB_DATABASE" > /root/panel_db_backup.sql 2>/dev/null; then
        local db_size
        db_size=$(du -sh /root/panel_db_backup.sql | cut -f1)
        log_info "Database berhasil di-backup! (${db_size})"
    else
        log_error "Gagal backup database!"
        php artisan up --quiet 2>/dev/null
        exit 1
    fi

    log_step "Mem-backup folder /var/www/pterodactyl..."
    if tar -czf /root/panel_files_backup.tar.gz /var/www/pterodactyl 2>/dev/null; then
        local files_size
        files_size=$(du -sh /root/panel_files_backup.tar.gz | cut -f1)
        log_info "File panel berhasil di-backup! (${files_size})"
    else
        log_error "Gagal membuat tar backup!"
        php artisan up --quiet 2>/dev/null
        exit 1
    fi

    php artisan up --quiet 2>/dev/null
    log_info "Maintenance mode dinonaktifkan."
    log_step "Mengirim file backup ke VPS Baru (${NEW_VPS_IP})..."

    log_info "Mengirim panel_db_backup.sql..."
    if sshpass -p "$NEW_VPS_PASS" scp \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=60 \
        -P "$NEW_VPS_PORT" \
        /root/panel_db_backup.sql \
        "${NEW_VPS_USER}@${NEW_VPS_IP}:/root/"; then
        log_info "panel_db_backup.sql berhasil dikirim."
    else
        log_error "Gagal mengirim panel_db_backup.sql!"
        cleanup_env
        exit 1
    fi

    log_info "Mengirim panel_files_backup.tar.gz (mungkin memakan waktu)..."
    if sshpass -p "$NEW_VPS_PASS" scp \
        -o StrictHostKeyChecking=no \
        -o ServerAliveInterval=60 \
        -P "$NEW_VPS_PORT" \
        /root/panel_files_backup.tar.gz \
        "${NEW_VPS_USER}@${NEW_VPS_IP}:/root/"; then
        log_info "panel_files_backup.tar.gz berhasil dikirim."
    else
        log_error "Gagal mengirim panel_files_backup.tar.gz!"
        cleanup_env
        exit 1
    fi

    cleanup_env

    log_section
    echo -e "\n  ${GREEN}${BOLD}✅  BACKUP & TRANSFER SELESAI!${NC}\n"
    echo -e "  File backup sudah terkirim ke VPS Baru ${CYAN}(${NEW_VPS_IP})${NC}."
    echo -e "\n  ${BOLD}Sekarang jalankan script ini di VPS Baru dan pilih ${GREEN}[2] RESTORE${NC}.\n"
    log_section
}

# ============================================================
#   OPSI 2: RESTORE + AUTO INSTALL & SETUP DI VPS BARU
# ============================================================
run_restore() {
    log_section
    log_step "Memulai proses RESTORE di VPS Baru..."
    log_section

    log_step "Memeriksa file backup..."
    local missing_files=()
    [ ! -f "/root/panel_files_backup.tar.gz" ] && missing_files+=("panel_files_backup.tar.gz")
    [ ! -f "/root/panel_db_backup.sql" ]       && missing_files+=("panel_db_backup.sql")

    if [ ${#missing_files[@]} -gt 0 ]; then
        log_error "File backup tidak ditemukan di /root/:"
        for f in "${missing_files[@]}"; do
            echo -e "    ${RED}✗${NC} $f"
        done
        log_warn "Pastikan sudah menjalankan opsi BACKUP di VPS lama terlebih dahulu."
        exit 1
    fi
    log_info "Semua file backup ditemukan."

    install_dependencies

    log_step "Setup Database..."
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Masukkan password ROOT MySQL di VPS BARU ini: ${NC}"
    read -s MYSQL_ROOT_PASS
    echo ""

    if ! MYSQL_PWD="$MYSQL_ROOT_PASS" mysql -u root -e "SELECT 1;" &>/dev/null; then
        log_error "Password MySQL root salah atau MySQL tidak berjalan!"
        exit 1
    fi
    log_info "Koneksi MySQL OK."

    log_step "Mengekstrak file panel ke /var/www/pterodactyl..."
    mkdir -p /var/www/pterodactyl
    if tar -xzf /root/panel_files_backup.tar.gz -C / > /dev/null 2>&1; then
        log_info "File panel berhasil diekstrak."
    else
        log_error "Gagal mengekstrak file backup!"
        exit 1
    fi

    cd /var/www/pterodactyl || { log_error "Gagal masuk ke /var/www/pterodactyl!"; exit 1; }
    if [ ! -f ".env" ]; then
        log_error "File .env tidak ditemukan setelah ekstrak!"
        exit 1
    fi

    DB_DATABASE=$(grep -w "^DB_DATABASE" .env | cut -d '=' -f2- | tr -d ' \r')
    DB_USERNAME=$(grep -w "^DB_USERNAME" .env | cut -d '=' -f2- | tr -d ' \r')
    DB_PASSWORD=$(grep -w "^DB_PASSWORD" .env | cut -d '=' -f2- | tr -d ' \r')

    log_info "Database target: ${DB_DATABASE}"

    log_info "Membuat database '${DB_DATABASE}'..."
    MYSQL_PWD="$MYSQL_ROOT_PASS" mysql -u root \
        -e "CREATE DATABASE IF NOT EXISTS \`$DB_DATABASE\`;" 2>/dev/null

    log_info "Merestore database dari backup..."
    if MYSQL_PWD="$MYSQL_ROOT_PASS" mysql -u root "$DB_DATABASE" \
        < /root/panel_db_backup.sql 2>/dev/null; then
        log_info "Database berhasil direstore!"
    else
        log_error "Gagal merestore database!"
        exit 1
    fi

    log_info "Membuat user database '${DB_USERNAME}'..."
    MYSQL_PWD="$MYSQL_ROOT_PASS" mysql -u root -e "
        CREATE USER IF NOT EXISTS '${DB_USERNAME}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${DB_DATABASE}\`.* TO '${DB_USERNAME}'@'127.0.0.1' WITH GRANT OPTION;
        FLUSH PRIVILEGES;
    " 2>/dev/null \
        && log_info "User database OK." \
        || log_warn "User DB mungkin sudah ada, lanjut..."

    log_step "Memperbarui permissions dan dependencies..."
    find storage bootstrap/cache -type d -exec chmod 755 {} \; 2>/dev/null
    find storage bootstrap/cache -type f -exec chmod 644 {} \; 2>/dev/null
    chown -R www-data:www-data /var/www/pterodactyl
    log_info "Permissions diperbarui."

    export COMPOSER_ALLOW_SUPERUSER=1
    log_info "Menjalankan composer install..."
    composer install --no-dev --optimize-autoloader --quiet 2>/dev/null \
        && log_info "Composer install selesai." \
        || log_warn "Composer install ada masalah, lanjut..."

    log_step "Membersihkan cache dan mengaktifkan panel..."
    php artisan view:clear   --quiet 2>/dev/null && log_info "View cache dibersihkan."
    php artisan config:clear --quiet 2>/dev/null && log_info "Config cache dibersihkan."
    php artisan cache:clear  --quiet 2>/dev/null && log_info "App cache dibersihkan."
    php artisan migrate --force --quiet 2>/dev/null && log_info "Migrasi database dijalankan."
    php artisan up           --quiet 2>/dev/null && log_info "Panel diaktifkan."

    setup_nginx
    setup_cron_and_worker

    log_step "Memastikan semua service berjalan..."
    systemctl restart nginx        2>/dev/null && log_info "Nginx berjalan."
    systemctl restart mariadb      2>/dev/null && log_info "MariaDB berjalan."
    systemctl restart redis-server 2>/dev/null && log_info "Redis berjalan."

    local vps_ip
    vps_ip=$(curl -s --connect-timeout 5 --max-time 10 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    local domain
    local app_url
    app_url=$(grep -w "^APP_URL" .env 2>/dev/null | cut -d '=' -f2- | tr -d ' \r')
    domain=$(echo "$app_url" | sed 's|https\?://||')

    echo ""
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} APP_URL saat ini: ${CYAN}${app_url}${NC}\n"
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Apakah ingin mengubah APP_URL? [y/N]: ${NC}"
    read -r CHANGE_URL
    if [[ "$CHANGE_URL" =~ ^[Yy]$ ]]; then
        echo -ne "  ${YELLOW}[?]${NC}${BOLD} Masukkan APP_URL baru (contoh: https://panel.domain.com): ${NC}"
        read -r NEW_APP_URL
        if [ -n "$NEW_APP_URL" ]; then
            sed -i "s|^APP_URL=.*|APP_URL=${NEW_APP_URL}|" .env
            app_url="$NEW_APP_URL"
            domain=$(echo "$app_url" | sed 's|https\?://||')
            php artisan config:clear --quiet 2>/dev/null
            log_info "APP_URL diperbarui ke: ${NEW_APP_URL}"
        fi
    fi

    cleanup_env

    log_section
    echo -e "\n  ${GREEN}${BOLD}✅  RESTORE SELESAI! PANEL SIAP PAKAI! 🚀${NC}\n"
    echo -e "  ${BOLD}Info VPS Baru:${NC}"
    echo -e "  ${YELLOW}  ▸${NC} IP VPS Baru  : ${CYAN}${vps_ip}${NC}"
    echo -e "  ${YELLOW}  ▸${NC} Domain Panel : ${CYAN}${domain}${NC}"
    echo -e "\n  ${BOLD}Yang perlu kamu lakukan HANYA 1:${NC}"
    echo -e "  ${YELLOW}  ▸${NC} Arahkan ${BOLD}A Record DNS/Cloudflare${NC} domain ${CYAN}${domain}${NC}"
    echo -e "    ke IP ${CYAN}${vps_ip}${NC}"
    echo -e "\n  ${BOLD}(Opsional) Pasang SSL:${NC}"
    echo -e "  ${CYAN}  apt install certbot python3-certbot-nginx -y${NC}"
    echo -e "  ${CYAN}  certbot --nginx -d ${domain}${NC}\n"
    echo -e "  ${BOLD}Log tersimpan di:${NC} ${CYAN}${LOG_FILE}${NC}\n"
    echo -e "  Nginx, MariaDB, Redis, Cronjob & Worker sudah jalan otomatis. ✅\n"
    log_section
}

# ============================================================
#   OPSI 3: HAPUS BACKUP DI VPS LAMA
# ============================================================
run_cleanup() {
    log_section
    log_step "Memeriksa file backup di VPS ini..."
    log_section

    local files=(
        "/root/panel_db_backup.sql"
        "/root/panel_files_backup.tar.gz"
    )
    local found=()

    for f in "${files[@]}"; do
        if [ -f "$f" ]; then
            local size
            size=$(du -sh "$f" | cut -f1)
            found+=("$f")
            log_info "Ditemukan: ${YELLOW}$f${NC} (${size})"
        fi
    done

    if [ ${#found[@]} -eq 0 ]; then
        log_warn "Tidak ada file backup yang ditemukan di /root/."
        log_warn "Mungkin sudah dihapus atau belum pernah dibuat."
        return
    fi

    echo ""
    echo -ne "  ${RED}[?]${NC}${BOLD} Yakin ingin menghapus ${#found[@]} file backup di atas? [y/N]: ${NC}"
    read -r CONFIRM

    if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_step "Menghapus file backup..."
        for f in "${found[@]}"; do
            rm -f "$f" && log_info "Dihapus: $f" || log_error "Gagal menghapus: $f"
        done
        log_section
        echo -e "\n  ${GREEN}${BOLD}🗑️   CLEANUP SELESAI!${NC}"
        echo -e "  Semua file backup telah dihapus dari VPS ini.\n"
        log_section
    else
        echo ""
        log_warn "Dibatalkan. Tidak ada file yang dihapus."
    fi
}

# ============================================================
#   OPSI 4: INSTALL PANEL 
# ============================================================
run_install_panel() {
    log_section
    log_step "Install Pterodactyl Panel (Fresh Install)"
    log_section

    if [ -d "/var/www/pterodactyl" ]; then
        log_warn "Folder /var/www/pterodactyl sudah ada!"
        echo -ne "  ${YELLOW}[?]${NC}${BOLD} Panel mungkin sudah terinstall. Lanjutkan? [y/N]: ${NC}"
        read -r CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            log_warn "Dibatalkan."
            return
        fi
    fi

    ensure_pkg "curl" "curl"

    log_info "Menjalankan Pterodactyl Installer..."
    log_info "Ikuti instruksi di layar untuk menyelesaikan instalasi."
    echo ""

    bash <(curl -s https://pterodactyl-installer.se)

    log_section
    echo -e "\n  ${GREEN}${BOLD}✅  INSTALL PANEL SELESAI!${NC}"
    echo -e "  Cek panel kamu di browser.${NC}\n"
    log_section
}

# ============================================================
#   OPSI 5: CEK SPESIFIKASI VPS
# ============================================================
run_benchmark() {
    log_section
    log_step "Benchmark & Cek Spesifikasi VPS"
    log_section

    ensure_pkg "wget" "wget"

    log_info "Menjalankan bench.sh — ini bisa memakan waktu beberapa menit..."
    echo ""

    wget -qO- bench.sh | bash

    log_section
    echo -e "\n  ${GREEN}${BOLD}✅  BENCHMARK SELESAI!${NC}\n"
    log_section
}

# ============================================================
#   OPSI 6: PASANG THEMA PTERODACTYL
# ============================================================
run_install_theme() {
    log_section
    log_step "Pasang Thema Pterodactyl"
    log_section

    if [ ! -d "/var/www/pterodactyl" ]; then
        log_error "Folder /var/www/pterodactyl tidak ditemukan!"
        log_warn "Install panel terlebih dahulu sebelum memasang thema."
        return
    fi

    ensure_pkg "curl" "curl"

    log_info "Menjalankan installer Thema Pterodactyl..."
    log_info "Ikuti instruksi di layar untuk menyelesaikan instalasi."
    echo ""

    bash <(curl -s https://raw.githubusercontent.com/SankaVollereii/Thema-Pterodactyl/main/install.sh)

    log_section
    echo -e "\n  ${GREEN}${BOLD}✅  THEMA BERHASIL DIPASANG!${NC}"
    echo -e "  Refresh browser untuk melihat perubahan.\n"
    log_section
}

# ============================================================
#   OPSI 7: INSTALL CLOUDFLARED TUNNEL
# ============================================================
run_install_cloudflared() {
    log_section
    log_step "Install Cloudflare Tunnel (cloudflared)"
    log_section

    if command -v cloudflared &>/dev/null; then
        log_info "cloudflared sudah terinstall ($(cloudflared --version 2>&1 | head -1))."
        echo -ne "  ${YELLOW}[?]${NC}${BOLD} Install ulang? [y/N]: ${NC}"
        read -r CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            log_warn "Dibatalkan."
        else
            log_info "Menginstall ulang cloudflared..."
            if command -v apt-get &>/dev/null; then
                curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg > /dev/null 2>&1
                echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflared.list
                apt-get update -qq > /dev/null 2>&1
                apt-get install -y -qq cloudflared > /dev/null 2>&1
            elif command -v yum &>/dev/null; then
                yum install -y -q cloudflared > /dev/null 2>&1 || {
                    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
                    chmod +x /usr/local/bin/cloudflared
                }
            fi
            log_info "cloudflared berhasil diinstall ulang."
        fi
    else
        log_info "Menginstall cloudflared..."
        ensure_pkg "curl" "curl"

        if command -v apt-get &>/dev/null; then
            curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg > /dev/null 2>&1
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflared.list
            apt-get update -qq > /dev/null 2>&1
            apt-get install -y -qq cloudflared > /dev/null 2>&1
        elif command -v yum &>/dev/null; then
            yum install -y -q cloudflared > /dev/null 2>&1 || {
                curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
                chmod +x /usr/local/bin/cloudflared
            }
        else
            curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
            chmod +x /usr/local/bin/cloudflared
        fi

        if command -v cloudflared &>/dev/null; then
            log_info "cloudflared terinstall ($(cloudflared --version 2>&1 | head -1))."
        else
            log_error "Gagal menginstall cloudflared!"
            return
        fi
    fi

    echo ""
    log_step "Setup Cloudflare Tunnel..."
    echo -e "  ${YELLOW}[?]${NC}${BOLD} Masukkan token Cloudflare Tunnel:${NC}"
    echo -e "  ${CYAN}    Bisa paste token langsung atau perintah lengkap seperti:${NC}"
    echo -e "  ${CYAN}    sudo cloudflared service install eyJhIjo...${NC}"
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Token: ${NC}"
    read -r CF_INPUT

    if [ -z "$CF_INPUT" ]; then
        log_warn "Token kosong, skip setup tunnel."
        return
    fi

    local CF_TOKEN
    CF_TOKEN=$(echo "$CF_INPUT" | grep -oP 'eyJ[A-Za-z0-9_-]+' | head -1)

    if [ -z "$CF_TOKEN" ]; then
        log_error "Token tidak valid! Pastikan token dimulai dengan 'eyJ...'."
        return
    fi

    log_info "Token terdeteksi: ${CF_TOKEN:0:20}..."

    cloudflared service install "$CF_TOKEN" 2>/dev/null && {
        systemctl enable cloudflared --quiet 2>/dev/null
        systemctl start cloudflared 2>/dev/null
        log_info "Cloudflare Tunnel berhasil disetup & dijalankan."
    } || {
        log_warn "cloudflared service mungkin sudah ada, mencoba restart..."
        systemctl restart cloudflared 2>/dev/null
    }

    log_section
    echo -e "\n  ${GREEN}${BOLD}✅  CLOUDFLARED TUNNEL AKTIF!${NC}"
    echo -e "  Cek status: ${CYAN}systemctl status cloudflared${NC}\n"
    log_section
}

# ============================================================
#   OPSI 8: FIREWALL SETUP
# ============================================================
run_firewall() {
    log_section
    log_step "Firewall — Buka Port"
    log_section

    local FW_CMD=""
    if command -v ufw &>/dev/null; then
        FW_CMD="ufw"
        if ! ufw status | grep -q "active" 2>/dev/null; then
            log_warn "UFW belum aktif."
            echo -ne "  ${YELLOW}[?]${NC}${BOLD} Aktifkan UFW sekarang? [y/N]: ${NC}"
            read -r ENABLE_UFW
            if [[ "$ENABLE_UFW" =~ ^[Yy]$ ]]; then
                ufw --force enable > /dev/null 2>&1
                ufw allow 22/tcp > /dev/null 2>&1
                log_info "UFW diaktifkan (port 22/tcp otomatis dibuka)."
            else
                log_warn "UFW tidak diaktifkan, lanjut..."
            fi
        fi
    elif command -v firewall-cmd &>/dev/null; then
        FW_CMD="firewall-cmd"
    else
        log_error "Tidak ada firewall yang terdeteksi (ufw/firewall-cmd)!"
        log_info "Install UFW dengan: apt install ufw -y"
        return
    fi

    log_info "Firewall terdeteksi: ${BOLD}${FW_CMD}${NC}"

    while true; do
        echo ""
        echo -ne "  ${YELLOW}[?]${NC}${BOLD} Masukkan port yang ingin dibuka (contoh: 9002): ${NC}"
        read -r FW_PORT

        if [ -z "$FW_PORT" ]; then
            log_warn "Selesai, kembali ke menu."
            break
        fi

        if ! [[ "$FW_PORT" =~ ^[0-9]+$ ]] || [ "$FW_PORT" -lt 1 ] || [ "$FW_PORT" -gt 65535 ]; then
            log_error "Port tidak valid: $FW_PORT (harus 1-65535)"
            continue
        fi

        echo -e "  ${BOLD}Pilih protokol:${NC}"
        echo -e "  ${GREEN}[1]${NC} TCP saja"
        echo -e "  ${GREEN}[2]${NC} UDP saja"
        echo -e "  ${GREEN}[3]${NC} TCP + UDP (keduanya)"
        echo -ne "  ${BOLD}Pilih [1/2/3]: ${NC}"
        read -r FW_PROTO

        local protos=()
        case "$FW_PROTO" in
            1) protos=("tcp") ;;
            2) protos=("udp") ;;
            3) protos=("tcp" "udp") ;;
            *)
                log_error "Pilihan tidak valid!"
                continue
                ;;
        esac

        for proto in "${protos[@]}"; do
            if [ "$FW_CMD" = "ufw" ]; then
                ufw allow "${FW_PORT}/${proto}" > /dev/null 2>&1 \
                    && log_info "Port ${GREEN}${FW_PORT}/${proto}${NC} berhasil dibuka." \
                    || log_error "Gagal membuka port ${FW_PORT}/${proto}!"
            elif [ "$FW_CMD" = "firewall-cmd" ]; then
                firewall-cmd --permanent --add-port="${FW_PORT}/${proto}" > /dev/null 2>&1 \
                    && log_info "Port ${GREEN}${FW_PORT}/${proto}${NC} berhasil dibuka." \
                    || log_error "Gagal membuka port ${FW_PORT}/${proto}!"
            fi
        done

        if [ "$FW_CMD" = "firewall-cmd" ]; then
            firewall-cmd --reload > /dev/null 2>&1
        fi

        echo -ne "\n  ${YELLOW}[?]${NC}${BOLD} Buka port lain? [y/N]: ${NC}"
        read -r AGAIN
        if [[ ! "$AGAIN" =~ ^[Yy]$ ]]; then
            break
        fi
    done

    echo ""
    log_step "Status Firewall:"
    if [ "$FW_CMD" = "ufw" ]; then
        ufw status numbered 2>/dev/null
    elif [ "$FW_CMD" = "firewall-cmd" ]; then
        firewall-cmd --list-all 2>/dev/null
    fi

    log_section
    echo -e "\n  ${GREEN}${BOLD}✅  FIREWALL SETUP SELESAI!${NC}\n"
    log_section
}

# ============================================================
#   OPSI 9: SETUP SWAP
# ============================================================
run_swap() {
    log_section
    log_step "Setup Swap Memory"
    log_section

    local current_swap
    current_swap=$(free -m | awk '/^Swap:/ {print $2}')
    local total_ram
    total_ram=$(free -m | awk '/^Mem:/ {print $2}')

    log_info "RAM     : ${BOLD}${total_ram}MB${NC}"
    log_info "Swap    : ${BOLD}${current_swap}MB${NC}"

    if [ "$current_swap" -gt 0 ]; then
        log_warn "Swap sudah aktif (${current_swap}MB)."
        echo -ne "  ${YELLOW}[?]${NC}${BOLD} Hapus swap lama dan buat baru? [y/N]: ${NC}"
        read -r CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            log_warn "Dibatalkan."
            return
        fi
        log_info "Menonaktifkan swap lama..."
        swapoff -a 2>/dev/null
        rm -f /swapfile 2>/dev/null
        sed -i '/\/swapfile/d' /etc/fstab 2>/dev/null
        log_info "Swap lama dihapus."
    fi

    local recommended
    if [ "$total_ram" -le 1024 ]; then
        recommended="2G"
    elif [ "$total_ram" -le 2048 ]; then
        recommended="2G"
    elif [ "$total_ram" -le 4096 ]; then
        recommended="4G"
    else
        recommended="4G"
    fi

    echo ""
    echo -e "  ${BOLD}Ukuran swap yang direkomendasikan:${NC}"
    echo -e "  ${CYAN}  ▸${NC} RAM ${total_ram}MB → Swap ${BOLD}${recommended}${NC}"
    echo ""
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Ukuran swap [${recommended}]: ${NC}"
    read -r SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-$recommended}

    if [[ ! "$SWAP_SIZE" =~ ^[0-9]+[GgMm]$ ]]; then
        log_error "Format tidak valid! Gunakan format: 2G, 4G, 512M, dll."
        return
    fi

    local avail_disk
    avail_disk=$(df -BM / | awk 'NR==2 {print $4}' | tr -d 'M')
    local swap_mb
    if [[ "$SWAP_SIZE" =~ [Gg]$ ]]; then
        swap_mb=$(( ${SWAP_SIZE%[Gg]} * 1024 ))
    else
        swap_mb=${SWAP_SIZE%[Mm]}
    fi

    if [ "$swap_mb" -gt "$avail_disk" ]; then
        log_error "Disk tidak cukup! Tersedia: ${avail_disk}MB, diminta: ${swap_mb}MB"
        return
    fi

    log_step "Membuat swap ${SWAP_SIZE}..."

    log_info "Mengalokasikan file swap..."
    fallocate -l "$SWAP_SIZE" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="$swap_mb" status=progress 2>/dev/null
    chmod 600 /swapfile
    log_info "File swap dibuat."

    log_info "Memformat swap..."
    mkswap /swapfile > /dev/null 2>&1
    log_info "Mengaktifkan swap..."
    swapon /swapfile

    if ! grep -q '/swapfile' /etc/fstab 2>/dev/null; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        log_info "Swap ditambahkan ke /etc/fstab (persist setelah reboot)."
    fi

    local swappiness
    swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null)
    if [ "$swappiness" -gt 30 ]; then
        sysctl vm.swappiness=10 > /dev/null 2>&1
        if ! grep -q 'vm.swappiness' /etc/sysctl.conf 2>/dev/null; then
            echo 'vm.swappiness=10' >> /etc/sysctl.conf
        fi
        log_info "Swappiness diatur ke 10 (default: ${swappiness})."
    fi

    echo ""
    log_step "Status Swap:"
    free -h | head -1
    free -h | grep -i swap

    log_section
    echo -e "\n  ${GREEN}${BOLD}✅  SWAP ${SWAP_SIZE} BERHASIL DISETUP!${NC}"
    echo -e "  Swap aktif dan persist setelah reboot.\n"
    log_section
}

# ============================================================
#   OPSI 10: DOCKER CLEANER
# ============================================================
run_docker_clean() {
    log_section
    log_step "Docker Cleaner — Hapus Resource Tidak Terpakai"
    log_section

    if ! command -v docker &>/dev/null; then
        log_error "Docker tidak terinstall di VPS ini!"
        return
    fi

    log_info "Docker terdeteksi: $(docker --version 2>&1)"

    log_step "Penggunaan disk Docker saat ini:"
    docker system df 2>/dev/null
    echo ""

    local containers images volumes
    containers=$(docker ps -a -q --filter "status=exited" --filter "status=created" 2>/dev/null | wc -l)
    images=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)
    volumes=$(docker volume ls -f "dangling=true" -q 2>/dev/null | wc -l)

    log_info "Container berhenti : ${BOLD}${containers}${NC}"
    log_info "Image dangling     : ${BOLD}${images}${NC}"
    log_info "Volume tidak pakai : ${BOLD}${volumes}${NC}"

    if [ "$containers" -eq 0 ] && [ "$images" -eq 0 ] && [ "$volumes" -eq 0 ]; then
        local total_reclaimable
        total_reclaimable=$(docker system df 2>/dev/null | awk 'NR>1 {print $NF}' | grep -cv '0B' || true)
        if [ "$total_reclaimable" -eq 0 ]; then
            log_info "Docker sudah bersih, tidak ada yang perlu dihapus."
            return
        fi
    fi

    echo ""
    echo -e "  ${RED}${BOLD}⚠️  PERINGATAN:${NC} Ini akan menghapus SEMUA:"
    echo -e "  ${YELLOW}  ▸${NC} Container yang berhenti"
    echo -e "  ${YELLOW}  ▸${NC} Image yang tidak dipakai"
    echo -e "  ${YELLOW}  ▸${NC} Network yang tidak dipakai"
    echo -e "  ${YELLOW}  ▸${NC} Build cache"
    echo ""
    echo -ne "  ${RED}[?]${NC}${BOLD} Lanjutkan cleanup? [y/N]: ${NC}"
    read -r CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_warn "Dibatalkan."
        return
    fi

    log_step "Menjalankan docker system prune..."
    docker system prune -a -f 2>&1

    echo ""
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Hapus juga volume yang tidak terpakai? [y/N]: ${NC}"
    read -r PRUNE_VOL
    if [[ "$PRUNE_VOL" =~ ^[Yy]$ ]]; then
        log_info "Menghapus volume tidak terpakai..."
        docker volume prune -f 2>&1
    fi

    echo ""
    log_step "Penggunaan disk Docker setelah cleanup:"
    docker system df 2>/dev/null

    log_section
    echo -e "\n  ${GREEN}${BOLD}✅  DOCKER CLEANUP SELESAI!${NC}\n"
    log_section
}

# ============================================================
#   MAIN MENU
# ============================================================
main() {
    show_banner
    check_root

    echo -e "  ${BOLD}Pilih mode yang sesuai dengan VPS kamu:${NC}\n"
    echo -e "  ${CYAN}━━━━━━━━━━━━ MIGRASI ━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}[1]${NC} 📤  ${BOLD}BACKUP${NC}   — Jalankan di VPS LAMA (auto kirim ke VPS Baru)"
    echo -e "  ${GREEN}[2]${NC} 📥  ${BOLD}RESTORE${NC}  — Jalankan di VPS BARU (auto install & setup semua)"
    echo -e "  ${RED}[3]${NC} 🗑️   ${BOLD}CLEANUP${NC}  — Bersihkan file backup di VPS"
    echo ""
    echo -e "  ${CYAN}━━━━━━━━━━━━ TOOLS ━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}[4]${NC} 🛠️   ${BOLD}INSTALL PANEL${NC}   — Install Pterodactyl Panel (fresh)"
    echo -e "  ${GREEN}[5]${NC} 📊  ${BOLD}CEK SPEK VPS${NC}   — Benchmark spesifikasi VPS"
    echo -e "  ${GREEN}[6]${NC} 🎨  ${BOLD}PASANG THEMA${NC}   — Install thema Pterodactyl"
    echo -e "  ${GREEN}[7]${NC} ☁️   ${BOLD}CLOUDFLARED${NC}    — Install & setup Cloudflare Tunnel"
    echo -e "  ${GREEN}[8]${NC} 🔥  ${BOLD}FIREWALL${NC}       — Buka port (UFW/firewall-cmd)"
    echo -e "  ${GREEN}[9]${NC} 💾  ${BOLD}SETUP SWAP${NC}     — Tambah RAM virtual (swap memory)"
    echo -e "  ${GREEN}[10]${NC} 🐳 ${BOLD}DOCKER CLEAN${NC}  — Hapus docker yang tidak terpakai"
    echo ""
    echo -e "  ${RED}[0]${NC} ❌  Keluar\n"
    echo -ne "  ${BOLD}Pilih opsi [0-10]: ${NC}"
    read -r OPTION

    timer_start

    case "$OPTION" in
        1)  run_backup              ;;
        2)  run_restore             ;;
        3)  run_cleanup             ;;
        4)  run_install_panel       ;;
        5)  run_benchmark           ;;
        6)  run_install_theme       ;;
        7)  run_install_cloudflared ;;
        8)  run_firewall            ;;
        9)  run_swap                ;;
        10) run_docker_clean        ;;
        0)
            echo -e "\n  ${YELLOW}Keluar. Sampai jumpa!${NC}\n"
            exit 0
            ;;
        *)
            log_error "Opsi tidak valid!"
            exit 1
            ;;
    esac

    timer_show
}

main "$@"