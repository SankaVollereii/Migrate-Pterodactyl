# 🦅 Pterodactyl Auto Migration

> Migrasi Pterodactyl Panel dari VPS Lama ke VPS Baru.
> Satu script — semua otomatis. **Terima jadi.**

![Version](https://img.shields.io/badge/version-2.1.0-blue?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)
![OS](https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian%20%7C%20CentOS-orange?style=flat-square)

---

## ✨ Fitur

- ✅ Backup database & file panel otomatis
- ✅ Auto kirim backup ke VPS Baru via SCP
- ✅ Auto install semua dependencies
- ✅ Auto setup Nginx, Cronjob & Queue Worker
- ✅ Restore database + buat ulang user DB
- ✅ Composer install, clear cache, migrate DB
- ✅ Hapus file backup (opsi 3)
- ✅ Support **Ubuntu, Debian & CentOS/RHEL**
- ✅ Password MySQL aman (tidak muncul di `ps`)
- ✅ Output terminal berwarna & informatif

---

## 🚀 Quick Start

### 1️⃣ Di VPS Lama — Backup

```bash
git clone https://github.com/SankaVollereii/Migrate-Pterodactyl.git
cd Migrate-Pterodactyl
chmod +x migrate.sh
sudo bash migrate.sh
```

Pilih **[1] BACKUP**, lalu masukkan info VPS Baru.

**Apa yang dilakukan script:**

1. Install `sshpass` otomatis
2. Minta input IP, port SSH, username, password VPS Baru
3. Test koneksi SSH
4. Baca `.env` lalu backup database
5. Backup folder `/var/www/pterodactyl`
6. Kirim otomatis ke VPS Baru via SCP

---

### 2️⃣ Di VPS Baru — Restore

```bash
git clone https://github.com/SankaVollereii/Migrate-Pterodactyl.git
cd Migrate-Pterodactyl
chmod +x migrate.sh
sudo bash migrate.sh
```

Pilih **[2] RESTORE**, lalu masukkan password root MySQL.

**Apa yang dilakukan script:**

1. Cek file backup ada
2. Install Nginx, PHP, MariaDB, Redis, Composer
3. Minta password root MySQL (1x saja)
4. Ekstrak file panel
5. Restore database & buat user DB
6. Update permissions & `composer install`
7. Clear cache & jalankan migrasi
8. Setup Nginx config
9. Setup Cronjob & Queue Worker (pteroq)
10. Restart semua service

---

### 3️⃣ Setelah Restore — Arahkan DNS

Cukup **1 langkah** saja: arahkan A Record domain ke IP VPS Baru.

| Record | Value |
|--------|-------|
| **A** | IP VPS Baru (ditampilkan di akhir script) |

**Opsional — Pasang SSL:**

```bash
apt install certbot python3-certbot-nginx -y
certbot --nginx -d namadomain.com
```

**Panel langsung bisa diakses.** 🎉

---

## ⚡ Input yang Dibutuhkan

| Langkah | Input |
|---------|-------|
| **Backup** (VPS Lama) | IP, Port, User, Pass SSH |
| **Restore** (VPS Baru) | Password root MySQL |
| **Hapus Backup** | Konfirmasi y/N |

> Semua selain itu: **otomatis.**

---

## 🗑️ Hapus Backup (Opsional)

Jalankan di **VPS Lama** setelah restore berhasil:

```bash
sudo bash migrate.sh
# Pilih [3] HAPUS BACKUP
```

---

## 🐛 Troubleshooting

### ❌ Koneksi SSH gagal saat backup

- Pastikan port SSH VPS Baru terbuka
- Default port: `22`
- Cek firewall: `ufw status` atau `firewall-cmd --list-all`

### ❌ Password MySQL root tidak diketahui

```bash
sudo mysql
ALTER USER 'root'@'localhost' IDENTIFIED BY 'passwordbaru';
FLUSH PRIVILEGES;
exit;
```

### ❌ Panel tidak muncul setelah DNS diarahkan

```bash
# Cek Nginx
systemctl status nginx

# Cek error log
tail -f /var/log/nginx/pterodactyl.app-error.log
```

### ❌ Queue Worker tidak jalan

```bash
systemctl status pteroq
systemctl restart pteroq
```

### ❌ PHP tidak terdeteksi (CentOS/RHEL)

Script otomatis menambah repo Remi. Jika gagal, install manual:

```bash
yum install -y epel-release
yum install -y https://rpms.remirepo.net/enterprise/remi-release-$(rpm -E %rhel).rpm
yum module enable -y php:remi-8.3
```

---

## 🖥️ OS yang Didukung

| OS | Status |
|-----|--------|
| Ubuntu 20.04+ | ✅ Supported |
| Debian 11+ | ✅ Supported |
| CentOS 8+ / RHEL | ✅ Supported |
| AlmaLinux / Rocky | ✅ Supported |

---

## 📄 Lisensi

MIT License — bebas digunakan dan dimodifikasi.

---

> Script ini tidak berafiliasi dengan proyek resmi [Pterodactyl](https://pterodactyl.io).
> Gunakan dengan risiko sendiri.
>
> **Made with ❤️ by [SankaVollereii](https://github.com/SankaVollereii)**