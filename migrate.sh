#!/bin/bash

# ============================================================
#   Auto Script Migrasi Pterodactyl Panel
#   GitHub  : https://github.com/SankaVollereii/Migrate-Pterodactyl
#   Version : 2.0.0 — Fully Automated
# ============================================================

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
    echo -e "${BOLD}  Auto Script Migrasi Pterodactyl Panel v2.0.0${NC}"
    echo -e "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# --- Fungsi Log ---
log_info()    { echo -e "  ${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "  ${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "  ${RED}[✗]${NC} $1"; }
log_step()    { echo -e "\n  ${CYAN}${BOLD}[>>]${NC}${BOLD} $1${NC}"; }
log_section() { echo -e "\n  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

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
            # PPA hanya tersedia di Ubuntu
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

    local nginx_conf="/etc/nginx/sites-available/pterodactyl.conf"

    local domain
    domain=$(grep -w "^APP_URL" /var/www/pterodactyl/.env 2>/dev/null \
        | cut -d '=' -f2 | tr -d ' \r' | sed 's|https\?://||')
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
        ln -sf "$nginx_conf" /etc/nginx/sites-enabled/pterodactyl.conf 2>/dev/null
        rm -f /etc/nginx/sites-enabled/default 2>/dev/null
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

    # Cronjob
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
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Port SSH VPS Baru [22]: ${NC}"
    read -r NEW_VPS_PORT
    NEW_VPS_PORT=${NEW_VPS_PORT:-22}
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Username SSH VPS Baru [root]: ${NC}"
    read -r NEW_VPS_USER
    NEW_VPS_USER=${NEW_VPS_USER:-root}
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Password SSH VPS Baru: ${NC}"
    read -s NEW_VPS_PASS
    echo ""

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
    export MYSQL_PWD="$DB_PASSWORD"
    if mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" \
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
        -P "$NEW_VPS_PORT" \
        /root/panel_db_backup.sql \
        "${NEW_VPS_USER}@${NEW_VPS_IP}:/root/"; then
        log_info "panel_db_backup.sql berhasil dikirim."
    else
        log_error "Gagal mengirim panel_db_backup.sql!"
        exit 1
    fi

    log_info "Mengirim panel_files_backup.tar.gz (mungkin memakan waktu)..."
    if sshpass -p "$NEW_VPS_PASS" scp \
        -o StrictHostKeyChecking=no \
        -P "$NEW_VPS_PORT" \
        /root/panel_files_backup.tar.gz \
        "${NEW_VPS_USER}@${NEW_VPS_IP}:/root/"; then
        log_info "panel_files_backup.tar.gz berhasil dikirim."
    else
        log_error "Gagal mengirim panel_files_backup.tar.gz!"
        exit 1
    fi

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
    domain=$(grep -w "^APP_URL" .env 2>/dev/null \
        | cut -d '=' -f2 | tr -d ' \r' | sed 's|https\?://||')

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
#   MAIN MENU
# ============================================================
main() {
    show_banner
    check_root

    echo -e "  ${BOLD}Pilih mode yang sesuai dengan VPS kamu:${NC}\n"
    echo -e "  ${GREEN}[1]${NC} 📤  ${BOLD}BACKUP${NC}  — Jalankan di VPS LAMA (auto kirim ke VPS Baru)"
    echo -e "  ${GREEN}[2]${NC} 📥  ${BOLD}RESTORE${NC} — Jalankan di VPS BARU (auto install & setup semua)"
    echo -e "  ${RED}[3]${NC} 🗑️   ${BOLD}HAPUS BACKUP${NC} — Bersihkan file backup di VPS LAMA"
    echo -e "  ${RED}[0]${NC} ❌  Keluar\n"
    echo -ne "  ${BOLD}Pilih opsi [1/2/3/0]: ${NC}"
    read -r OPTION

    case "$OPTION" in
        1) run_backup   ;;
        2) run_restore  ;;
        3) run_cleanup  ;;
        0)
            echo -e "\n  ${YELLOW}Keluar. Sampai jumpa!${NC}\n"
            exit 0
            ;;
        *)
            log_error "Opsi tidak valid!"
            exit 1
            ;;
    esac
}

main "$@"