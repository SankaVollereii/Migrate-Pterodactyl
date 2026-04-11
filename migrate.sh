#!/bin/bash

# ============================================================
#   Auto Script Migrasi Pterodactyl Panel
#   GitHub  : https://github.com/SankaVollereii/Migrate-Pterodactyl
#   Version : 2.3.0 — Fully Automated + Volumes + SSL
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
    echo -e "${BOLD}  Auto Script Migrasi Pterodactyl Panel v2.3.0${NC}"
    echo -e "  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

log_info()    { echo -e "  ${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "  ${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "  ${RED}[✗]${NC} $1"; }
log_step()    { echo -e "\n  ${CYAN}${BOLD}[>>]${NC}${BOLD} $1${NC}"; }
log_section() { echo -e "\n  ${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

trap 'log_error "Error pada line $LINENO"; exit 1' ERR

LOG_FILE="/root/Migrate-Pterodactyl/migrate.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
exec > >(tee "$LOG_FILE") 2>&1

validate_ip() {
    local ip="$1"
    if [ -z "$ip" ]; then log_error "IP tidak boleh kosong!"; return 1; fi
    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ ! "$ip" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        log_error "Format IP/hostname tidak valid: $ip"; return 1
    fi
    return 0
}

cleanup_env() { unset MYSQL_PWD MYSQL_ROOT_PASS DB_PASSWORD NEW_VPS_PASS 2>/dev/null || true; }

START_TIME=0
timer_start() { START_TIME=$(date +%s); }
timer_show() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - START_TIME))
    local mins=$((elapsed / 60)) secs=$((elapsed % 60))
    [ $mins -gt 0 ] && log_info "Waktu: ${BOLD}${mins}m ${secs}s${NC}" || log_info "Waktu: ${BOLD}${secs}s${NC}"
}

check_root() {
    [ "$EUID" -ne 0 ] && { log_error "Harus dijalankan sebagai root!"; exit 1; }
}

detect_os() {
    if command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt-get"; PKG_UPDATE="apt-get update -qq"; PKG_INSTALL="apt-get install -y -qq"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"; PKG_UPDATE="yum update -y -q"; PKG_INSTALL="yum install -y -q"
    else
        log_error "Package manager tidak dikenali!"; exit 1
    fi
}

ensure_pkg() {
    local cmd="$1" pkg="$2"
    if ! command -v "$cmd" &>/dev/null; then
        log_info "Menginstall ${pkg}..."
        $PKG_INSTALL "$pkg" > /dev/null 2>&1 && log_info "${pkg} terinstall." || { log_error "Gagal install ${pkg}!"; exit 1; }
    fi
}

# ============================================================
#   INSTALL / UPGRADE PHP KE 8.2+
# ============================================================
install_php() {
    local target_ver="8.2"
    if command -v php &>/dev/null; then
        local current_ver
        current_ver=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
        if awk "BEGIN{exit !($current_ver >= 8.2)}"; then
            log_info "PHP ${current_ver} sudah >= 8.2, skip."; PHP_VER="$current_ver"; return 0
        fi
        log_warn "PHP ${current_ver} terlalu lama, upgrade ke ${target_ver}..."
    fi

    if [ "$PKG_MANAGER" = "apt-get" ]; then
        if ! apt-cache show "php${target_ver}" &>/dev/null 2>&1; then
            ensure_pkg "add-apt-repository" "software-properties-common"
            add-apt-repository -y ppa:ondrej/php > /dev/null 2>&1 || {
                ensure_pkg "curl" "curl"
                curl -sSL https://packages.sury.org/php/apt.gpg | apt-key add - > /dev/null 2>&1
                echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
            }
            $PKG_UPDATE > /dev/null 2>&1
        fi
        $PKG_INSTALL "php${target_ver}" "php${target_ver}-cli" "php${target_ver}-fpm" \
            "php${target_ver}-mysql" "php${target_ver}-mbstring" "php${target_ver}-xml" \
            "php${target_ver}-bcmath" "php${target_ver}-curl" "php${target_ver}-zip" \
            "php${target_ver}-gd" "php${target_ver}-common" "php${target_ver}-redis" > /dev/null 2>&1
    fi

    command -v update-alternatives &>/dev/null && update-alternatives --set php /usr/bin/php${target_ver} > /dev/null 2>&1 || true
    systemctl enable "php${target_ver}-fpm" --quiet 2>/dev/null || true
    systemctl restart "php${target_ver}-fpm" 2>/dev/null || true
    PHP_VER="$target_ver"
    log_info "PHP ${target_ver} terinstall."
}

# ============================================================
#   INSTALL DOCKER
# ============================================================
install_docker() {
    if command -v docker &>/dev/null; then
        log_info "Docker sudah ada, skip."
        systemctl enable docker --quiet 2>/dev/null || true
        systemctl start docker 2>/dev/null || true
        return 0
    fi
    log_info "Menginstall Docker..."
    ensure_pkg "curl" "curl"
    curl -sSL https://get.docker.com | bash > /dev/null 2>&1
    systemctl enable docker --quiet 2>/dev/null
    systemctl start docker 2>/dev/null
    command -v docker &>/dev/null && log_info "Docker terinstall." || { log_error "Docker gagal!"; exit 1; }
}

# ============================================================
#   INSTALL WINGS
# ============================================================
install_wings() {
    log_step "Menginstall Pterodactyl Wings..."
    install_docker
    mkdir -p /etc/pterodactyl

    if [ ! -f "/usr/local/bin/wings" ]; then
        log_info "Mendownload Wings..."
        ensure_pkg "curl" "curl"
        curl -L -o /usr/local/bin/wings \
            "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" > /dev/null 2>&1
        chmod u+x /usr/local/bin/wings
        log_info "Wings terdownload."
    else
        log_info "Wings sudah ada, skip download."
    fi

    local service_file="/etc/systemd/system/wings.service"
    if [ ! -f "$service_file" ]; then
        cat > "$service_file" <<'WINGSEOF'
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
WINGSEOF
        systemctl daemon-reload 2>/dev/null
        systemctl enable wings --quiet 2>/dev/null
        log_info "Wings service dibuat."
    else
        log_info "Wings service sudah ada."
    fi

    if [ ! -f "/etc/pterodactyl/config.yml" ]; then
        log_warn "config.yml belum ada — masuk Panel → Admin → Nodes → Configuration → copy ke /etc/pterodactyl/config.yml"
    else
        systemctl restart wings 2>/dev/null && log_info "Wings berjalan." || log_warn "Wings gagal, cek: journalctl -u wings -n 30"
    fi
}

# ============================================================
#   SETUP SSL PANEL (Nginx)
# ============================================================
setup_ssl() {
    local domain="$1" email="$2"
    [ -z "$domain" ] || [ "$domain" = "_" ] && { log_warn "Domain tidak valid, skip SSL."; return; }

    log_step "Setup SSL panel: ${domain}"
    ! command -v certbot &>/dev/null && { detect_os; $PKG_INSTALL certbot python3-certbot-nginx > /dev/null 2>&1; }

    if [ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]; then
        log_info "SSL ${domain} sudah ada."; return 0
    fi

    if certbot --nginx -d "$domain" --non-interactive --agree-tos -m "$email" > /dev/null 2>&1; then
        log_info "SSL panel ${domain} berhasil!"
    else
        log_warn "Nginx installer gagal, coba standalone..."
        systemctl stop nginx 2>/dev/null || true
        certbot certonly --standalone -d "$domain" --non-interactive --agree-tos -m "$email" > /dev/null 2>&1 \
            && log_info "SSL certonly ${domain} berhasil!" \
            || log_warn "SSL gagal, pasang manual nanti."
        systemctl start nginx 2>/dev/null || true
    fi

    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx' >> /var/log/certbot-renew.log 2>&1") | crontab -
        log_info "Auto-renew SSL terjadwal jam 03:00 setiap hari."
    fi
}

# ============================================================
#   SETUP SSL WINGS/NODE (standalone)
# ============================================================
setup_ssl_wings() {
    local node_domain="$1" email="$2"
    [ -z "$node_domain" ] && { log_warn "Domain node kosong, skip."; return; }

    log_step "Setup SSL Wings/Node: ${node_domain}"
    ! command -v certbot &>/dev/null && { detect_os; $PKG_INSTALL certbot > /dev/null 2>&1; }

    if [ -f "/etc/letsencrypt/live/${node_domain}/fullchain.pem" ]; then
        log_info "SSL ${node_domain} sudah ada."; return 0
    fi

    log_info "Stop Wings & Nginx sementara..."
    systemctl stop wings 2>/dev/null || true
    systemctl stop nginx 2>/dev/null || true

    certbot certonly --standalone -d "$node_domain" --non-interactive --agree-tos -m "$email" > /dev/null 2>&1 \
        && log_info "SSL Wings ${node_domain} berhasil!" \
        || log_warn "SSL Wings gagal, cek DNS dulu."

    systemctl start nginx 2>/dev/null || true
    systemctl start wings 2>/dev/null || true

    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --pre-hook 'systemctl stop wings' --post-hook 'systemctl start wings && systemctl reload nginx' >> /var/log/certbot-renew.log 2>&1") | crontab -
        log_info "Auto-renew SSL Wings terjadwal jam 03:00."
    fi
}

# ============================================================
#   INSTALL DEPENDENCIES
# ============================================================
install_dependencies() {
    log_step "Mengecek & menginstall dependencies..."
    detect_os
    $PKG_UPDATE > /dev/null 2>&1

    if ! command -v nginx &>/dev/null; then
        $PKG_INSTALL nginx > /dev/null 2>&1
        systemctl enable nginx --quiet 2>/dev/null; systemctl start nginx 2>/dev/null
        log_info "Nginx terinstall."
    else log_info "Nginx sudah ada, skip."; fi

    if ! command -v mysql &>/dev/null; then
        $PKG_INSTALL mariadb-server mariadb-client > /dev/null 2>&1
        systemctl enable mariadb --quiet 2>/dev/null; systemctl start mariadb 2>/dev/null
        log_info "MariaDB terinstall."
    else log_info "MariaDB sudah ada, skip."; fi

    if ! command -v redis-cli &>/dev/null; then
        $PKG_INSTALL redis-server > /dev/null 2>&1
        systemctl enable redis-server --quiet 2>/dev/null; systemctl start redis-server 2>/dev/null
        log_info "Redis terinstall."
    else log_info "Redis sudah ada, skip."; fi

    install_php
    install_docker

    if ! command -v composer &>/dev/null; then
        ensure_pkg "curl" "curl"
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer > /dev/null 2>&1
        log_info "Composer terinstall."
    else log_info "Composer sudah ada, skip."; fi

    ensure_pkg "tar" "tar"
    ensure_pkg "unzip" "unzip"
    ensure_pkg "sshpass" "sshpass"

    log_info "Semua dependencies siap."
}

# ============================================================
#   SETUP NGINX
# ============================================================
setup_nginx() {
    log_step "Setup Nginx untuk Pterodactyl..."

    local php_ver
    php_ver=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
    local php_socket="/run/php/php${php_ver}-fpm.sock"

    if [ ! -S "$php_socket" ]; then
        local found_socket
        found_socket=$(find /run/php/ -name "php*-fpm.sock" 2>/dev/null | grep -v "php7\|php8.0\|php8.1" | head -1)
        [ -z "$found_socket" ] && found_socket=$(find /run/php/ -name "php*-fpm.sock" 2>/dev/null | head -1)
        [ -n "$found_socket" ] && php_socket="$found_socket"
        log_info "PHP-FPM socket: ${php_socket}"
    fi

    local nginx_conf
    [ -d "/etc/nginx/sites-available" ] && nginx_conf="/etc/nginx/sites-available/pterodactyl.conf" \
        || nginx_conf="/etc/nginx/conf.d/pterodactyl.conf"

    local domain
    domain=$(grep -w "^APP_URL" /var/www/pterodactyl/.env 2>/dev/null \
        | cut -d '=' -f2- | tr -d ' \r"'"'" | sed 's|https\?://||')
    domain=${domain:-"_"}

    if [ -f "$nginx_conf" ]; then
        local current_socket
        current_socket=$(grep "fastcgi_pass" "$nginx_conf" | grep -oP 'unix:[^;]+' | head -1 | sed 's/unix://')
        if [ "$current_socket" != "$php_socket" ]; then
            sed -i "s|fastcgi_pass unix:.*fpm.sock;|fastcgi_pass unix:${php_socket};|g" "$nginx_conf"
            nginx -t > /dev/null 2>&1 && systemctl reload nginx 2>/dev/null
            log_info "Nginx socket diperbarui → ${php_socket}"
        else
            log_info "Nginx sudah up-to-date, skip."
        fi
        return
    fi

    cat > "$nginx_conf" <<NGINXEOF
server {
    listen 80;
    server_name ${domain};

    root /var/www/pterodactyl/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / { try_files \$uri \$uri/ /index.php?\$query_string; }
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;
    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:${php_socket};
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

    location ~ /\.ht { deny all; }
}
NGINXEOF

    [ -d "/etc/nginx/sites-enabled" ] && {
        ln -sf "$nginx_conf" /etc/nginx/sites-enabled/pterodactyl.conf 2>/dev/null
        rm -f /etc/nginx/sites-enabled/default 2>/dev/null
    }
    nginx -t > /dev/null 2>&1 && systemctl reload nginx 2>/dev/null
    log_info "Nginx config dibuat untuk: ${domain}"
}

# ============================================================
#   SETUP CRONJOB & QUEUE WORKER
# ============================================================
setup_cron_and_worker() {
    log_step "Setup Cronjob & Queue Worker..."

    if ! crontab -l 2>/dev/null | grep -q "pterodactyl/artisan schedule:run"; then
        (crontab -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -
        log_info "Cronjob ditambahkan."
    else log_info "Cronjob sudah ada, skip."; fi

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
        log_info "Queue Worker (pteroq) disetup & dijalankan."
    else
        systemctl restart pteroq 2>/dev/null
        log_info "Queue Worker di-restart."
    fi
}

# ============================================================
#   OPSI 1: BACKUP + STREAM KE VPS BARU
# ============================================================
run_backup() {
    log_section
    log_step "BACKUP di VPS Lama..."
    log_section

    detect_os
    ensure_pkg "sshpass" "sshpass"

    [ ! -d "/var/www/pterodactyl" ] && { log_error "/var/www/pterodactyl tidak ditemukan!"; exit 1; }
    cd /var/www/pterodactyl || exit 1

    log_step "Informasi VPS Baru..."
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} IP VPS Baru: ${NC}"; read -r NEW_VPS_IP
    validate_ip "$NEW_VPS_IP" || exit 1
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Port SSH [22]: ${NC}"; read -r NEW_VPS_PORT; NEW_VPS_PORT=${NEW_VPS_PORT:-22}
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Username [root]: ${NC}"; read -r NEW_VPS_USER; NEW_VPS_USER=${NEW_VPS_USER:-root}
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Password SSH: ${NC}"; read -s NEW_VPS_PASS; echo ""
    [ -z "$NEW_VPS_PASS" ] && { log_error "Password kosong!"; exit 1; }

    echo ""
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Backup juga file server (volumes Docker)? [Y/n]: ${NC}"
    read -r BACKUP_VOLUMES; BACKUP_VOLUMES=${BACKUP_VOLUMES:-Y}

    log_step "Test koneksi SSH..."
    sshpass -p "$NEW_VPS_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        -p "$NEW_VPS_PORT" "${NEW_VPS_USER}@${NEW_VPS_IP}" "echo ok" &>/dev/null \
        || { log_error "Tidak bisa terhubung ke VPS Baru!"; exit 1; }
    log_info "Koneksi SSH OK."

    php artisan down --quiet 2>/dev/null && log_info "Maintenance mode aktif." || log_warn "Lanjut..."

    [ ! -f ".env" ] && { log_error ".env tidak ditemukan!"; php artisan up --quiet 2>/dev/null; exit 1; }

    DB_HOST=$(grep -w "^DB_HOST" .env | cut -d '=' -f2- | tr -d ' \r"'"'")
    DB_PORT=$(grep -w "^DB_PORT" .env | cut -d '=' -f2- | tr -d ' \r"'"'"); DB_PORT=${DB_PORT:-3306}
    DB_DATABASE=$(grep -w "^DB_DATABASE" .env | cut -d '=' -f2- | tr -d ' \r"'"'")
    DB_USERNAME=$(grep -w "^DB_USERNAME" .env | cut -d '=' -f2- | tr -d ' \r"'"'")
    DB_PASSWORD=$(grep -w "^DB_PASSWORD" .env | cut -d '=' -f2- | tr -d ' \r"'"'")

    log_step "Backup database..."
    MYSQL_PWD="$DB_PASSWORD" mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USERNAME" \
        "$DB_DATABASE" > /root/panel_db_backup.sql 2>/dev/null \
        && log_info "DB backup: $(du -sh /root/panel_db_backup.sql | cut -f1)" \
        || { log_error "Gagal backup DB!"; php artisan up --quiet 2>/dev/null; exit 1; }

    log_step "Backup panel files..."
    tar -czf /root/panel_files_backup.tar.gz /var/www/pterodactyl 2>/dev/null \
        && log_info "Panel files: $(du -sh /root/panel_files_backup.tar.gz | cut -f1)" \
        || { log_error "Gagal backup files!"; php artisan up --quiet 2>/dev/null; exit 1; }

    php artisan up --quiet 2>/dev/null; log_info "Maintenance mode off."

    log_step "Kirim DB backup..."
    sshpass -p "$NEW_VPS_PASS" scp -o StrictHostKeyChecking=no -o ServerAliveInterval=60 \
        -P "$NEW_VPS_PORT" /root/panel_db_backup.sql "${NEW_VPS_USER}@${NEW_VPS_IP}:/root/" \
        && log_info "DB backup terkirim." || { log_error "Gagal kirim DB!"; cleanup_env; exit 1; }

    log_step "Kirim panel files..."
    sshpass -p "$NEW_VPS_PASS" scp -o StrictHostKeyChecking=no -o ServerAliveInterval=60 \
        -P "$NEW_VPS_PORT" /root/panel_files_backup.tar.gz "${NEW_VPS_USER}@${NEW_VPS_IP}:/root/" \
        && log_info "Panel files terkirim." || { log_error "Gagal kirim files!"; cleanup_env; exit 1; }

    if [[ "$BACKUP_VOLUMES" =~ ^[Yy]$ ]]; then
        if [ -d "/var/lib/pterodactyl/volumes" ] && [ "$(ls -A /var/lib/pterodactyl/volumes 2>/dev/null)" ]; then
            log_step "Stream volumes ke VPS Baru (langsung, hemat storage)..."
            log_warn "Ukuran: $(du -sh /var/lib/pterodactyl/volumes/ 2>/dev/null | cut -f1) — proses bisa lama."

            local wings_was_running=false
            systemctl is-active --quiet wings 2>/dev/null && wings_was_running=true
            [ "$wings_was_running" = true ] && systemctl stop wings 2>/dev/null && log_info "Wings dihentikan sementara."

            if tar -czf - /var/lib/pterodactyl/volumes/ 2>/dev/null | \
                sshpass -p "$NEW_VPS_PASS" ssh \
                    -o StrictHostKeyChecking=no \
                    -o ServerAliveInterval=60 \
                    -o ServerAliveCountMax=10 \
                    -p "$NEW_VPS_PORT" \
                    "${NEW_VPS_USER}@${NEW_VPS_IP}" \
                    "mkdir -p /var/lib/pterodactyl && tar -xzf - -C /"; then
                log_info "Volumes berhasil di-stream ke VPS Baru!"
                log_info "Jalankan di VPS Baru: chown -R root:root /var/lib/pterodactyl/volumes/"
            else
                log_warn "Stream volumes gagal/sebagian. Cek manual di VPS baru."
            fi

            [ "$wings_was_running" = true ] && systemctl start wings 2>/dev/null && log_info "Wings dijalankan kembali."
        else
            log_warn "Folder volumes kosong, skip."
        fi
    else
        log_warn "Skip backup volumes (pilihan user)."
    fi

    cleanup_env
    log_section
    echo -e "\n  ${GREEN}${BOLD}✅  BACKUP & TRANSFER SELESAI!${NC}"
    echo -e "  Sekarang jalankan script di VPS Baru → pilih ${GREEN}[2] RESTORE${NC}.\n"
    log_section
}

# ============================================================
#   OPSI 2: RESTORE
# ============================================================
run_restore() {
    log_section
    log_step "RESTORE di VPS Baru..."
    log_section

    local missing_files=()
    [ ! -f "/root/panel_files_backup.tar.gz" ] && missing_files+=("panel_files_backup.tar.gz")
    [ ! -f "/root/panel_db_backup.sql" ]       && missing_files+=("panel_db_backup.sql")
    if [ ${#missing_files[@]} -gt 0 ]; then
        log_error "File backup tidak ditemukan:"
        for f in "${missing_files[@]}"; do echo -e "    ${RED}✗${NC} $f"; done
        exit 1
    fi
    log_info "File backup ditemukan."

    install_dependencies

    log_step "Setup Database..."
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Password ROOT MySQL: ${NC}"; read -s MYSQL_ROOT_PASS; echo ""

    mysql_cmd() {
        [ -z "$MYSQL_ROOT_PASS" ] && mysql -u root "$@" || MYSQL_PWD="$MYSQL_ROOT_PASS" mysql -u root "$@"
    }

    if ! MYSQL_PWD="$MYSQL_ROOT_PASS" mysql -u root -e "SELECT 1;" &>/dev/null; then
        if mysql -u root -e "SELECT 1;" &>/dev/null; then
            log_warn "MySQL unix_socket auth."; MYSQL_ROOT_PASS=""
        else
            log_error "Password MySQL salah!"; exit 1
        fi
    fi
    log_info "MySQL OK."

    log_step "Ekstrak panel files..."
    mkdir -p /var/www/pterodactyl
    tar -xzf /root/panel_files_backup.tar.gz -C / > /dev/null 2>&1 \
        && log_info "Files diekstrak." || { log_error "Gagal ekstrak!"; exit 1; }

    cd /var/www/pterodactyl || exit 1
    [ ! -f ".env" ] && { log_error ".env tidak ditemukan!"; exit 1; }

    local app_url_raw
    app_url_raw=$(grep -w "^APP_URL" .env | cut -d '=' -f2- | tr -d ' \r')
    if [[ "$app_url_raw" == \"*\" ]] || [[ "$app_url_raw" == \'*\' ]]; then
        local app_url_clean
        app_url_clean=$(echo "$app_url_raw" | tr -d '"'"'")
        sed -i "s|^APP_URL=.*|APP_URL=${app_url_clean}|" .env
        log_info "APP_URL diperbaiki: ${app_url_clean}"
    fi

    DB_DATABASE=$(grep -w "^DB_DATABASE" .env | cut -d '=' -f2- | tr -d ' \r"'"'")
    DB_USERNAME=$(grep -w "^DB_USERNAME" .env | cut -d '=' -f2- | tr -d ' \r"'"'")
    DB_PASSWORD=$(grep -w "^DB_PASSWORD" .env | cut -d '=' -f2- | tr -d ' \r"'"'")

    mysql_cmd -e "CREATE DATABASE IF NOT EXISTS \`$DB_DATABASE\`;" 2>/dev/null
    mysql_cmd "$DB_DATABASE" < /root/panel_db_backup.sql 2>/dev/null \
        && log_info "Database direstore!" || { log_error "Gagal restore DB!"; exit 1; }
    mysql_cmd -e "
        CREATE USER IF NOT EXISTS '${DB_USERNAME}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
        GRANT ALL PRIVILEGES ON \`${DB_DATABASE}\`.* TO '${DB_USERNAME}'@'127.0.0.1' WITH GRANT OPTION;
        FLUSH PRIVILEGES;
    " 2>/dev/null && log_info "User DB OK." || log_warn "User DB mungkin sudah ada."

    log_step "Permissions & Composer..."
    find storage bootstrap/cache -type d -exec chmod 755 {} \; 2>/dev/null
    find storage bootstrap/cache -type f -exec chmod 644 {} \; 2>/dev/null
    chown -R www-data:www-data /var/www/pterodactyl

    export COMPOSER_ALLOW_SUPERUSER=1
    if ! composer install --no-dev --optimize-autoloader --quiet 2>/dev/null; then
        log_error "Composer GAGAL:"
        composer install --no-dev --optimize-autoloader 2>&1 | tail -20
        exit 1
    fi
    log_info "Composer selesai."

    log_step "Clear cache & aktifkan panel..."
    systemctl restart redis-server 2>/dev/null || true
    php artisan view:clear   --quiet 2>/dev/null && log_info "View cache clear."
    php artisan config:clear --quiet 2>/dev/null && log_info "Config cache clear."
    php artisan cache:clear  --quiet 2>/dev/null && log_info "App cache clear."
    php artisan migrate --force --quiet 2>/dev/null && log_info "Migrasi DB selesai."
    php artisan up --quiet 2>/dev/null && log_info "Panel aktif."

    setup_nginx
    setup_cron_and_worker
    install_wings

    systemctl restart nginx        2>/dev/null && log_info "Nginx berjalan."
    systemctl restart mariadb      2>/dev/null && log_info "MariaDB berjalan."
    systemctl restart redis-server 2>/dev/null && log_info "Redis berjalan."
    systemctl restart docker       2>/dev/null && log_info "Docker berjalan."

    local vps_ip
    vps_ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    local app_url
    app_url=$(grep -w "^APP_URL" .env | cut -d '=' -f2- | tr -d ' \r"'"'")
    local domain; domain=$(echo "$app_url" | sed 's|https\?://||')

    echo ""
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} APP_URL: ${CYAN}${app_url}${NC} — Ubah? [y/N]: ${NC}"
    read -r CHANGE_URL
    if [[ "$CHANGE_URL" =~ ^[Yy]$ ]]; then
        echo -ne "  ${YELLOW}[?]${NC}${BOLD} APP_URL baru: ${NC}"; read -r NEW_APP_URL
        if [ -n "$NEW_APP_URL" ]; then
            sed -i "s|^APP_URL=.*|APP_URL=${NEW_APP_URL}|" .env
            app_url="$NEW_APP_URL"; domain=$(echo "$app_url" | sed 's|https\?://||')
            php artisan config:clear --quiet 2>/dev/null
            log_info "APP_URL → ${NEW_APP_URL}"
        fi
    fi

    echo ""
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Pasang SSL panel (${domain})? [Y/n]: ${NC}"
    read -r DO_SSL; DO_SSL=${DO_SSL:-Y}
    local SSL_EMAIL=""
    if [[ "$DO_SSL" =~ ^[Yy]$ ]]; then
        echo -ne "  ${YELLOW}[?]${NC}${BOLD} Email SSL: ${NC}"; read -r SSL_EMAIL
        [ -n "$SSL_EMAIL" ] && setup_ssl "$domain" "$SSL_EMAIL"
    fi

    echo ""
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Pasang SSL Wings/Node? [Y/n]: ${NC}"
    read -r DO_SSL_WINGS; DO_SSL_WINGS=${DO_SSL_WINGS:-Y}
    if [[ "$DO_SSL_WINGS" =~ ^[Yy]$ ]]; then
        echo -ne "  ${YELLOW}[?]${NC}${BOLD} Domain node (contoh: node.domain.com): ${NC}"; read -r NODE_DOMAIN
        if [ -n "$NODE_DOMAIN" ]; then
            local node_email="${SSL_EMAIL}"
            [ -z "$node_email" ] && { echo -ne "  ${YELLOW}[?]${NC}${BOLD} Email SSL node: ${NC}"; read -r node_email; }
            setup_ssl_wings "$NODE_DOMAIN" "$node_email"
        fi
    fi

    [ -f "/etc/pterodactyl/config.yml" ] && systemctl restart wings 2>/dev/null && log_info "Wings berjalan."

    cleanup_env
    log_section
    echo -e "\n  ${GREEN}${BOLD}✅  RESTORE SELESAI! 🚀${NC}\n"
    echo -e "  ${YELLOW}▸${NC} IP VPS   : ${CYAN}${vps_ip}${NC}"
    echo -e "  ${YELLOW}▸${NC} Panel    : ${CYAN}${app_url}${NC}"
    echo -e "\n  ${BOLD}⚠️  Wings:${NC} Panel → Admin → Nodes → Configuration"
    echo -e "  Copy config → ${CYAN}/etc/pterodactyl/config.yml${NC} → ${CYAN}systemctl restart wings${NC}\n"
    echo -e "  Log: ${CYAN}${LOG_FILE}${NC}\n"
    log_section
}

# ============================================================
#   OPSI 3: CLEANUP
# ============================================================
run_cleanup() {
    log_section; log_step "Cleanup file backup..."; log_section

    local files=("/root/panel_db_backup.sql" "/root/panel_files_backup.tar.gz" "/root/pterodactyl_volumes_backup.tar.gz")
    local found=()
    for f in "${files[@]}"; do
        [ -f "$f" ] && { found+=("$f"); log_info "Ditemukan: ${YELLOW}$f${NC} ($(du -sh "$f" | cut -f1))"; }
    done

    [ ${#found[@]} -eq 0 ] && { log_warn "Tidak ada file backup."; return; }

    echo -ne "\n  ${RED}[?]${NC}${BOLD} Hapus ${#found[@]} file? [y/N]: ${NC}"; read -r CONFIRM
    [[ "$CONFIRM" =~ ^[Yy]$ ]] && {
        for f in "${found[@]}"; do rm -f "$f" && log_info "Dihapus: $f"; done
        echo -e "\n  ${GREEN}${BOLD}🗑️  CLEANUP SELESAI!${NC}\n"
    } || log_warn "Dibatalkan."
}

# ============================================================
#   OPSI 4: MIGRASI DOMAIN
# ============================================================
run_migrate_domain() {
    log_section; log_step "Migrasi Domain Panel"; log_section

    [ ! -d "/var/www/pterodactyl" ] && { log_error "Panel tidak ditemukan!"; return; }
    cd /var/www/pterodactyl || return
    [ ! -f ".env" ] && { log_error ".env tidak ditemukan!"; return; }

    local current_url
    current_url=$(grep -w "^APP_URL" .env | cut -d '=' -f2- | tr -d ' \r"'"'")
    log_info "APP_URL saat ini: ${BOLD}${current_url}${NC}"

    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Domain baru: ${NC}"; read -r NEW_DOMAIN
    [ -z "$NEW_DOMAIN" ] && { log_error "Domain kosong!"; return; }

    echo -e "  ${GREEN}[1]${NC} https://  ${GREEN}[2]${NC} http://"
    echo -ne "  ${BOLD}Pilih [1/2]: ${NC}"; read -r PROTO_CHOICE
    local new_url
    [ "$PROTO_CHOICE" = "2" ] && new_url="http://${NEW_DOMAIN}" || new_url="https://${NEW_DOMAIN}"

    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Lanjutkan? [y/N]: ${NC}"; read -r CONFIRM
    [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && { log_warn "Dibatalkan."; return; }

    sed -i "s|^APP_URL=.*|APP_URL=${new_url}|" .env

    for conf in /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/conf.d/pterodactyl.conf; do
        [ -f "$conf" ] && {
            sed -i "s|server_name .*|server_name ${NEW_DOMAIN};|" "$conf"
            nginx -t > /dev/null 2>&1 && systemctl reload nginx 2>/dev/null
            log_info "Nginx diperbarui."; break
        }
    done

    php artisan config:clear --quiet 2>/dev/null
    php artisan cache:clear  --quiet 2>/dev/null
    php artisan view:clear   --quiet 2>/dev/null
    chown -R www-data:www-data /var/www/pterodactyl 2>/dev/null

    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Pasang SSL untuk ${NEW_DOMAIN}? [y/N]: ${NC}"; read -r SETUP_SSL
    [[ "$SETUP_SSL" =~ ^[Yy]$ ]] && {
        echo -ne "  ${YELLOW}[?]${NC}${BOLD} Email SSL: ${NC}"; read -r SSL_EMAIL
        setup_ssl "$NEW_DOMAIN" "$SSL_EMAIL"
    }

    local vps_ip
    vps_ip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    echo -e "\n  ${GREEN}${BOLD}✅  DOMAIN BERHASIL DIGANTI!${NC}"
    echo -e "  ${CYAN}${new_url}${NC} → IP: ${CYAN}${vps_ip}${NC}\n"
}

# ============================================================
#   OPSI 5: INSTALL PANEL
# ============================================================
run_install_panel() {
    [ -d "/var/www/pterodactyl" ] && {
        echo -ne "  ${YELLOW}[?]${NC}${BOLD} Panel mungkin sudah ada. Lanjutkan? [y/N]: ${NC}"; read -r C
        [[ ! "$C" =~ ^[Yy]$ ]] && { log_warn "Dibatalkan."; return; }
    }
    ensure_pkg "curl" "curl"
    bash <(curl -s https://pterodactyl-installer.se)
    echo -e "\n  ${GREEN}${BOLD}✅  INSTALL SELESAI!${NC}\n"
}

# ============================================================
#   OPSI 6: SETUP SWAP
# ============================================================
run_swap() {
    log_section; log_step "Setup Swap Memory"; log_section

    local current_swap total_ram
    current_swap=$(free -m | awk '/^Swap:/ {print $2}')
    total_ram=$(free -m | awk '/^Mem:/ {print $2}')
    log_info "RAM: ${total_ram}MB | Swap: ${current_swap}MB"

    if [ "$current_swap" -gt 0 ]; then
        echo -ne "  ${YELLOW}[?]${NC}${BOLD} Swap aktif. Buat ulang? [y/N]: ${NC}"; read -r C
        [[ ! "$C" =~ ^[Yy]$ ]] && { log_warn "Dibatalkan."; return; }
        swapoff -a 2>/dev/null; rm -f /swapfile 2>/dev/null
        sed -i '/\/swapfile/d' /etc/fstab 2>/dev/null
    fi

    local recommended; [ "$total_ram" -le 2048 ] && recommended="2G" || recommended="4G"
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Ukuran swap [${recommended}]: ${NC}"; read -r SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-$recommended}
    [[ ! "$SWAP_SIZE" =~ ^[0-9]+[GgMm]$ ]] && { log_error "Format tidak valid! (2G/4G/512M)"; return; }

    fallocate -l "$SWAP_SIZE" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="${SWAP_SIZE%[GgMm]}" status=progress
    chmod 600 /swapfile; mkswap /swapfile > /dev/null 2>&1; swapon /swapfile
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

    local swappiness; swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null)
    [ "$swappiness" -gt 30 ] && {
        sysctl vm.swappiness=10 > /dev/null 2>&1
        grep -q 'vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
        log_info "Swappiness → 10"
    }
    free -h | grep -i swap
    echo -e "\n  ${GREEN}${BOLD}✅  SWAP ${SWAP_SIZE} AKTIF!${NC}\n"
}

# ============================================================
#   OPSI 7: PASANG THEMA
# ============================================================
run_install_theme() {
    [ ! -d "/var/www/pterodactyl" ] && { log_error "Panel belum terinstall!"; return; }
    ensure_pkg "curl" "curl"
    bash <(curl -s https://raw.githubusercontent.com/SankaVollereii/Thema-Pterodactyl/main/install.sh)
    echo -e "\n  ${GREEN}${BOLD}✅  THEMA TERPASANG!${NC}\n"
}

# ============================================================
#   OPSI 8: CLOUDFLARED
# ============================================================
run_install_cloudflared() {
    log_section; log_step "Cloudflare Tunnel"; log_section
    ensure_pkg "curl" "curl"

    if ! command -v cloudflared &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg > /dev/null 2>&1
            echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" > /etc/apt/sources.list.d/cloudflared.list
            apt-get update -qq > /dev/null 2>&1; apt-get install -y -qq cloudflared > /dev/null 2>&1
        else
            curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
            chmod +x /usr/local/bin/cloudflared
        fi
        log_info "cloudflared terinstall."
    else log_info "cloudflared sudah ada."; fi

    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Token Tunnel: ${NC}"; read -r CF_INPUT
    [ -z "$CF_INPUT" ] && { log_warn "Token kosong."; return; }

    local CF_TOKEN; CF_TOKEN=$(echo "$CF_INPUT" | grep -oP 'eyJ[A-Za-z0-9_-]+' | head -1)
    [ -z "$CF_TOKEN" ] && { log_error "Token tidak valid!"; return; }

    cloudflared service install "$CF_TOKEN" 2>/dev/null && {
        systemctl enable cloudflared --quiet 2>/dev/null; systemctl start cloudflared 2>/dev/null
        log_info "Tunnel aktif."
    } || systemctl restart cloudflared 2>/dev/null

    echo -e "\n  ${GREEN}${BOLD}✅  CLOUDFLARED AKTIF!${NC}\n"
}

# ============================================================
#   OPSI 9: FIREWALL
# ============================================================
run_firewall() {
    log_section; log_step "Firewall — Buka Port"; log_section

    local FW_CMD=""
    command -v ufw &>/dev/null && FW_CMD="ufw" || command -v firewall-cmd &>/dev/null && FW_CMD="firewall-cmd"
    [ -z "$FW_CMD" ] && { log_error "Tidak ada firewall!"; return; }

    [ "$FW_CMD" = "ufw" ] && ! ufw status | grep -q "active" && {
        echo -ne "  ${YELLOW}[?]${NC}${BOLD} Aktifkan UFW? [y/N]: ${NC}"; read -r E
        [[ "$E" =~ ^[Yy]$ ]] && { ufw --force enable > /dev/null 2>&1; ufw allow 22/tcp > /dev/null 2>&1; log_info "UFW aktif."; }
    }

    while true; do
        echo -ne "\n  ${YELLOW}[?]${NC}${BOLD} Port (kosong=selesai): ${NC}"; read -r FW_PORT
        [ -z "$FW_PORT" ] && break
        ! [[ "$FW_PORT" =~ ^[0-9]+$ ]] || [ "$FW_PORT" -lt 1 ] || [ "$FW_PORT" -gt 65535 ] && { log_error "Port tidak valid!"; continue; }
        echo -e "  ${GREEN}[1]${NC} TCP  ${GREEN}[2]${NC} UDP  ${GREEN}[3]${NC} TCP+UDP"
        echo -ne "  ${BOLD}Pilih: ${NC}"; read -r FW_PROTO
        local protos=()
        case "$FW_PROTO" in 1) protos=("tcp");; 2) protos=("udp");; 3) protos=("tcp" "udp");; *) log_error "Tidak valid!"; continue;; esac
        for proto in "${protos[@]}"; do
            [ "$FW_CMD" = "ufw" ] && ufw allow "${FW_PORT}/${proto}" > /dev/null 2>&1 && log_info "Port ${FW_PORT}/${proto} dibuka."
            [ "$FW_CMD" = "firewall-cmd" ] && firewall-cmd --permanent --add-port="${FW_PORT}/${proto}" > /dev/null 2>&1 && log_info "Port ${FW_PORT}/${proto} dibuka."
        done
        [ "$FW_CMD" = "firewall-cmd" ] && firewall-cmd --reload > /dev/null 2>&1
        echo -ne "  Buka lagi? [y/N]: "; read -r A; [[ ! "$A" =~ ^[Yy]$ ]] && break
    done
    echo -e "\n  ${GREEN}${BOLD}✅  FIREWALL SELESAI!${NC}\n"
}

# ============================================================
#   OPSI 10: DOCKER CLEAN
# ============================================================
run_docker_clean() {
    log_section; log_step "Docker Cleaner"; log_section
    ! command -v docker &>/dev/null && { log_error "Docker tidak ada!"; return; }
    docker system df 2>/dev/null
    echo -ne "\n  ${RED}[?]${NC}${BOLD} Lanjutkan? [y/N]: ${NC}"; read -r C
    [[ ! "$C" =~ ^[Yy]$ ]] && { log_warn "Dibatalkan."; return; }
    docker system prune -a -f 2>&1
    echo -ne "  Hapus volume? [y/N]: "; read -r V; [[ "$V" =~ ^[Yy]$ ]] && docker volume prune -f 2>&1
    docker system df 2>/dev/null
    echo -e "\n  ${GREEN}${BOLD}✅  DOCKER CLEAN SELESAI!${NC}\n"
}

# ============================================================
#   OPSI 11: WIREGUARD
# ============================================================
run_wireguard() {
    ensure_pkg "curl" "curl"
    bash <(curl -sL https://raw.githubusercontent.com/angristan/wireguard-install/master/wireguard-install.sh)
    echo -e "\n  ${GREEN}${BOLD}✅  WIREGUARD SELESAI!${NC}\n"
}

# ============================================================
#   OPSI 12: BENCHMARK
# ============================================================
run_benchmark() {
    ensure_pkg "wget" "wget"
    wget -qO- bench.sh | bash
}

# ============================================================
#   OPSI 13: SETUP SSL MANUAL
# ============================================================
run_setup_ssl_manual() {
    log_section; log_step "Setup SSL Manual (Certbot)"; log_section

    detect_os
    ! command -v certbot &>/dev/null && { $PKG_INSTALL certbot python3-certbot-nginx > /dev/null 2>&1; log_info "Certbot terinstall."; }

    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Domain: ${NC}"; read -r SSL_DOMAIN
    [ -z "$SSL_DOMAIN" ] && { log_error "Domain kosong!"; return; }
    echo -ne "  ${YELLOW}[?]${NC}${BOLD} Email: ${NC}"; read -r SSL_EMAIL
    [ -z "$SSL_EMAIL" ] && { log_error "Email kosong!"; return; }

    echo -e "  ${GREEN}[1]${NC} Panel (Nginx)  ${GREEN}[2]${NC} Wings/Node (standalone)"
    echo -ne "  ${BOLD}Pilih [1/2]: ${NC}"; read -r SSL_TYPE

    [ "$SSL_TYPE" = "2" ] && setup_ssl_wings "$SSL_DOMAIN" "$SSL_EMAIL" || setup_ssl "$SSL_DOMAIN" "$SSL_EMAIL"
}

# ============================================================
#   MAIN MENU
# ============================================================
main() {
    show_banner
    check_root

    echo -e "  ${BOLD}Pilih mode yang sesuai:${NC}\n"
    echo -e "  ${CYAN}━━━━━━━━━━━━ MIGRASI ━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}[1]${NC} 📤  ${BOLD}BACKUP${NC}       — VPS LAMA → stream ke VPS Baru (+ volumes opsional)"
    echo -e "  ${GREEN}[2]${NC} 📥  ${BOLD}RESTORE${NC}      — VPS BARU → install & setup semua otomatis"
    echo -e "  ${RED}[3]${NC} 🗑️   ${BOLD}CLEANUP${NC}      — Hapus file backup"
    echo -e "  ${GREEN}[4]${NC} 🌐  ${BOLD}GANTI DOMAIN${NC} — Migrasi domain panel"
    echo ""
    echo -e "  ${CYAN}━━━━━━━━━━━━ TOOLS ━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}[5]${NC}  🛠️  ${BOLD}INSTALL PANEL${NC} — Fresh install Pterodactyl"
    echo -e "  ${GREEN}[6]${NC}  💾  ${BOLD}SETUP SWAP${NC}    — Tambah swap memory"
    echo -e "  ${GREEN}[7]${NC}  🎨  ${BOLD}PASANG THEMA${NC}  — Install thema Pterodactyl"
    echo -e "  ${GREEN}[8]${NC}  ☁️   ${BOLD}CLOUDFLARED${NC}   — Cloudflare Tunnel"
    echo -e "  ${GREEN}[9]${NC}  🔥  ${BOLD}FIREWALL${NC}      — Buka port UFW"
    echo -e "  ${GREEN}[10]${NC} 🐳  ${BOLD}DOCKER CLEAN${NC}  — Bersihkan Docker"
    echo -e "  ${GREEN}[11]${NC} 🔐  ${BOLD}WIREGUARD${NC}     — WireGuard VPN"
    echo -e "  ${GREEN}[12]${NC} 📊  ${BOLD}CEK SPEK${NC}      — Benchmark VPS"
    echo -e "  ${GREEN}[13]${NC} 🔒  ${BOLD}SETUP SSL${NC}     — Pasang SSL + auto-renew"
    echo ""
    echo -e "  ${RED}[0]${NC} ❌  Keluar\n"
    echo -ne "  ${BOLD}Pilih [0-13]: ${NC}"
    read -r OPTION

    timer_start

    case "$OPTION" in
        1)  run_backup              ;;
        2)  run_restore             ;;
        3)  run_cleanup             ;;
        4)  run_migrate_domain      ;;
        5)  run_install_panel       ;;
        6)  run_swap                ;;
        7)  run_install_theme       ;;
        8)  run_install_cloudflared ;;
        9)  run_firewall            ;;
        10) run_docker_clean        ;;
        11) run_wireguard           ;;
        12) run_benchmark           ;;
        13) run_setup_ssl_manual    ;;
        0)  echo -e "\n  ${YELLOW}Keluar. Sampai jumpa!${NC}\n"; exit 0 ;;
        *)  log_error "Opsi tidak valid!"; exit 1 ;;
    esac

    timer_show
}

main "$@"
