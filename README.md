# Windows Private CCTV Server

Server CCTV lokal berbasis Windows untuk streaming video langsung (MJPEG) melalui browser tanpa fitur perekaman disk. Dapat diakses melalui jaringan lokal (LAN/Wi-Fi) atau jarak jauh menggunakan Tailscale.

## Struktur Direktori

```text
C:\CCTV\
│   start_cctv.bat      # Panel kontrol CLI dan automasi
│
├───bin\
│       cctv.py         # Aplikasi server Python (Flask + OpenCV)
│
├───log\
│       cctv_server.log      # Log server (rotasi 5 MB x 2 berkas)
│       cctv_console_out.log # Saluran stdout mode background
│       cctv_console_err.log # Saluran stderr mode background
│
└───tmp\
        cctv.pid        # ID proses server aktif
        stop.marker     # Berkas penanda penghentian (graceful shutdown)
```

## Kemampuan Utama

- **Streaming browser tanpa dependensi klien**: Mengalirkan format MJPEG standar langsung ke peramban tanpa perlu memasang pemutar video terpisah.
- **Dukungan multi-backend kamera**: Membuka kamera melalui Media Foundation (MSMF) atau DirectShow (DSHOW), serta melakukan pemindaian otomatis index kamera (0, 1, atau 2).
- **Efisiensi daya dan pemrosesan**: Menghentikan proses kompresi JPEG jika tidak ada klien yang menonton, dan menunda pengiriman frame saat tab browser tidak aktif.
- **Operasi latar belakang terisolasi**: Berjalan sebagai proses mandiri (WMI) agar tetap aktif saat sesi SSH terputus.
- **Penghentian terkontrol (graceful shutdown)**: Menutup tangkapan kamera lewat berkas penanda agar lampu indikator mati dan perangkat keras terlepas bersih tanpa proses zombie.
- **Otomasi CLI dan SSH**: Seluruh fungsi panel dapat dipanggil langsung satu baris tanpa membuka antarmuka menu.
- **REST API**: Endpoint terintegrasi untuk pengambilan foto instan (JPEG) dan data status operasional (JSON).

## Kebutuhan Sistem

| Komponen       | Kebutuhan Minimum            | Rekomendasi                                      |
| -------------- | ---------------------------- | ------------------------------------------------ |
| Sistem Operasi | Windows 7 64-bit             | Windows 10/11 64-bit                             |
| Memori (RAM)   | 512 MB                       | 1 GB atau lebih                                  |
| Kamera         | Webcam USB eksternal         | Webcam bawaan laptop                             |
| Lingkungan     | Python 3.9                   | Python 3.12 atau lebih baru                      |
| Jaringan       | Jaringan lokal (LAN / Wi-Fi) | Tailscale terpasang di server dan klien pemantau |

## Persiapan

1. Pasang Python 3.9 atau yang lebih baru dari [python.org](https://www.python.org/downloads/). Pastikan opsi **Add Python to PATH** dicentang saat instalasi.
2. Di Windows 10 atau 11, buka **Settings > Privacy & security > Camera**, lalu pastikan opsi **Let desktop apps access your camera** dalam status **On**.
3. Jika menggunakan laptop yang layarnya sering ditutup, buka **Power Options** dan atur tindakan saat penutup layar ditutup (_When I close the lid_) ke **Do nothing**.
4. Pasang Tailscale pada komputer server dan perangkat pemantau jika ingin mengakses di luar jaringan lokal.

## Pemasangan & Menjalankan Server

### 1. Pasang Paket Dependensi

Buka terminal dan jalankan:

```cmd
pip install flask opencv-python
```

Untuk perangkat dengan sumber daya terbatas, `opencv-python-headless` dapat digunakan sebagai pengganti `opencv-python`.

### 2. Menjalankan Panel Kontrol

Klik ganda berkas [`start_cctv.bat`](start_cctv.bat) untuk membuka menu interaktif:

```text
==========================================
      CCTV SERVER CONTROL PANEL
==========================================

  STATUS: [ RUNNING ]
  AUTOSTART: [ DISABLED ]

==========================================
  1. Start CCTV Server (Normal)
  2. Start CCTV Server (Background)
  3. Stop CCTV Server
  4. Take Snapshot (Photo)
  5. Enable Autostart
  6. Disable Autostart
  7. View Logs
  8. Exit
==========================================
```

### 3. Operasi Langsung via CLI / SSH

Perintah dapat dijalankan langsung tanpa menu:

```cmd
start_cctv.bat --start        # Jalankan di jendela terminal baru
start_cctv.bat --background   # Jalankan tersembunyi di latar belakang
start_cctv.bat --status       # Cek status proses server
start_cctv.bat --snapshot     # Ambil foto seketika ke direktori log
start_cctv.bat --stop         # Hentikan proses server secara aman
```

Panduan lengkap instalasi tanpa monitor (headless) dan pengaturan SSH key tersedia di [`deploy-via-ssh.md`](deploy-via-ssh.md).

### 4. Konfigurasi Parameter (Opsional)

Server berjalan di port `5000` dengan batas 10 FPS secara default. Parameter ini dapat disesuaikan pada berkas [`start_cctv.bat`](start_cctv.bat) atau saat mengeksekusi skrip:

```cmd
python bin\cctv.py --port 8080 --fps 15 --quality 50 --width 1280 --height 720
```

## Mengakses Tampilan Kamera

Buka peramban di perangkat pemantau lalu buka alamat IP komputer server:

```text
http://<ip_target>:5000/
```

### Daftar Endpoint HTTP

| Endpoint    | Keterangan                                                            |
| ----------- | --------------------------------------------------------------------- |
| `/`         | Antarmuka web pemantau dengan rekoneksi otomatis                      |
| `/stream`   | Aliran murni multipart MJPEG                                          |
| `/snapshot` | Unduh satu frame gambar JPEG terkini                                  |
| `/status`   | Status server berformat JSON (uptime, kondisi kamera, penonton aktif) |

Contoh respon `/status`:

```json
{
  "status": "ok",
  "camera_ok": true,
  "uptime_seconds": 3600,
  "frame_age_seconds": 0.1,
  "active_viewers": 1
}
```
