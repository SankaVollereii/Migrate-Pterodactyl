# 🦅 Pterodactyl Auto Migration & Tools

> Migrasi panel, install fresh, benchmark VPS, pasang thema.
> Satu script — **semua otomatis.** 

![Version](https://img.shields.io/badge/version-2.1.0-blue?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)
![OS](https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian%20%7C%20CentOS-orange?style=flat-square)

---

## ✨ Fitur

**Migrasi:**
- ✅ Backup database & file panel otomatis
- ✅ Auto kirim backup ke VPS Baru via SCP
- ✅ Auto install semua dependencies
- ✅ Auto setup Nginx, Cronjob & Queue Worker
- ✅ Restore database + buat ulang user DB
- ✅ Composer install, clear cache, migrate DB
- ✅ Hapus file backup (opsi 3)

**Tools:**
- 🛠️ Install Pterodactyl Panel 
- 📊 Benchmark & cek spesifikasi VPS
- 🎨 Pasang thema Pterodactyl

**Lainnya:**
- ✅ Support **Ubuntu, Debian & CentOS/RHEL**
- ✅ Password MySQL aman (tidak muncul di `ps`)
- ✅ Log tersimpan otomatis ke file
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

## ⚡ Semua Menu

| Opsi | Fungsi | Input |
|------|--------|-------|
| **[1] Backup** | Backup & kirim ke VPS Baru | IP, Port, User, Pass SSH |
| **[2] Restore** | Restore & setup di VPS Baru | Password root MySQL |
| **[3] Cleanup** | Hapus file backup | Konfirmasi y/N |
| **[4] Install Panel** | Install Pterodactyl fresh | Ikuti wizard |
| **[5] Cek Spek VPS** | Benchmark CPU, RAM, Disk, Network | Otomatis |
| **[6] Pasang Thema** | Install thema Pterodactyl | Ikuti wizard |
| **[7] Cloudflared** | Install & setup Cloudflare Tunnel | Token tunnel |
| **[8] Firewall** | Buka port (UFW/firewall-cmd) | Port + protokol |
| **[9] Setup Swap** | Tambah RAM virtual (swap) | Ukuran swap |
| **[10] Docker Clean** | Hapus docker tidak terpakai | Konfirmasi y/N |

> Semua dependency: **auto install.**

---

## 🛠️ Tools Tambahan

### Install Panel Fresh

```bash
sudo bash migrate.sh
# Pilih [4] INSTALL PANEL
```

Menggunakan [pterodactyl-installer.se](https://pterodactyl-installer.se) — ikuti instruksi di layar.

### Cek Spesifikasi VPS

```bash
sudo bash migrate.sh
# Pilih [5] CEK SPEK VPS
```

Menampilkan info CPU, RAM, Disk, I/O speed, dan network speed.

### Pasang Thema

```bash
sudo bash migrate.sh
# Pilih [6] PASANG THEMA
```

Menggunakan [Thema-Pterodactyl](https://github.com/SankaVollereii/Thema-Pterodactyl) — panel harus sudah terinstall.

### Cloudflare Tunnel

```bash
sudo bash migrate.sh
# Pilih [7] CLOUDFLARED
```

Install cloudflared & setup tunnel otomatis. Bisa paste token langsung atau perintah lengkap seperti:

```
sudo cloudflared service install eyJhIjo...
```

Script akan otomatis mengambil tokennya saja.

### Firewall — Buka Port

```bash
sudo bash migrate.sh
# Pilih [8] FIREWALL
```

Buka port dengan pilihan protokol:
- **[1]** TCP saja
- **[2]** UDP saja
- **[3]** TCP + UDP (keduanya)

Support UFW (Ubuntu/Debian) dan firewall-cmd (CentOS/RHEL). Bisa buka banyak port sekaligus.

### Setup Swap Memory

```bash
sudo bash migrate.sh
# Pilih [9] SETUP SWAP
```

Tambah RAM virtual pakai swap file. Berguna untuk VPS RAM kecil (1-2GB).
Script otomatis rekomendasi ukuran swap berdasarkan RAM, cek disk space, dan persist setelah reboot.

### Docker Cleaner

```bash
sudo bash migrate.sh
# Pilih [10] DOCKER CLEAN
```

Hapus semua container berhenti, image tidak terpakai, network, dan build cache.
Tampilkan disk usage sebelum & sesudah cleanup.

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
