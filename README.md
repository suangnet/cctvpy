# Windows PC as Private CCTV Server

Ubah PC/Laptop Windows menjadi server CCTV pribadi khusus untuk **pemantauan langsung (Live MJPEG streaming tanpa fitur perekaman)**. Aplikasi ini dirancang sangat ringan agar tetap berjalan lancar di sistem dengan _resource_ yang sangat minim. Akses aman via **LAN/Wi-Fi** atau jarak jauh via **Tailscale**.

> [!TIP]
> **Clean Architecture**: Folder diatur rapi (`bin`, `log`, `tmp`) agar _root directory_ bersih.

## Struktur Folder

```text
C:\CCTV\
│   start_cctv.bat      # Control Panel CLI (Jalankan file ini!)
│
├───bin\
│       cctv.py         # Inti dari server CCTV Python
│
├───log\
│       cctv_server.log # Log aplikasi (auto-rotate, max 5MB x 2 backup)
│       cctv_console.log # Output console saat mode background
│
└───tmp\
        cctv.pid        # (Terbuat otomatis, melacak ID proses)
        stop.marker     # (Terbuat sesaat untuk memicu graceful shutdown)
```

## Fitur Unggulan

- **Live Streaming MJPEG**: Tonton langsung dari browser tanpa aplikasi tambahan.
- **Smart Bandwidth Saving**: Stream _pause_ otomatis saat tab browser tidak aktif (pindah tab/minimize).
- **Auto-Recovery & Reconnect**: Coba sambung ulang otomatis jika stream klien atau sistem kamera terputus.
- **Low Resource Usage**: Menghemat CPU, sistem otomatis melakukan _skip encoding_ jika tidak ada penonton.
- **Graceful Shutdown**: Menggunakan metode `stop.marker` agar proses kamera tertutup sempurna tanpa _glitch_ / proses zombie di Windows 11.
- **Background Mode**: Berjalan tersembunyi via PowerShell (`Start-Process`), sangat ringan dan ideal untuk _autostart_.
- **Snapshot & Status API**: Ambil foto (JPEG) atau pantau status server via REST API.
- **Log Rotation**: Mencegah log file membengkak dan memenuhi ruang penyimpanan disk.

## Kebutuhan Sistem (Requirements)

| Komponen     | Minimum            | Rekomendasi                              |
| ------------ | ------------------ | ---------------------------------------- |
| **OS**       | Windows 7 (64-bit) | Windows 10/11 (64-bit)                   |
| **RAM**      | 512 MB             | 1 GB+                                    |
| **Kamera**   | Webcam USB         | Built-in webcam laptop                   |
| **Software** | Python 3.9+        | Python 3.12+                             |
| **Jaringan** | LAN / Wi-Fi        | Tailscale terinstal di Server & Pemantau |

## Persiapan Awal

1. **Install Python**: Unduh Python (versi 3.9+) dari [python.org](https://www.python.org/downloads/) dan pasang. **Sangat Penting:** Wajib centang **"Add Python to PATH"** saat instalasi!
2. **Install Tailscale**: Login dengan akun yang sama di PC Server dan perangkat pemantau. Catat IP Tailscale milik PC Server.
3. **Power Settings**: Ubah opsi _Lid closed_ ke **Do nothing** (di menu _Power Options_) agar laptop tidak _sleep_ saat layarnya ditutup.

## Instalasi & Penggunaan

### 1. Install Dependencies

Buka Command Prompt/Terminal, lalu jalankan:

```bash
pip install flask opencv-python
```

> [!TIP]
> Gunakan `opencv-python-headless` untuk menghemat sedikit RAM (tidak memuat dependensi GUI).

### 2. Jalankan Control Panel

Klik ganda **`start_cctv.bat`** untuk membuka menu interaktif berikut:

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

- **Autostart (Opsi 5):** Server otomatis menyala secara tersembunyi di _background_ setiap kali PC dihidupkan (tanpa butuh akses Admin).
- **Remote SSH:** _Control Panel_ ini 100% mendukung eksekusi jarak jauh (SSH) tanpa masalah _force-kill_. Detail baca `deploy-via-ssh.md`.

### 3. Konfigurasi Kustom (Opsional)

Secara bawaan, server berjalan di port `5000` dengan kamera utama (index `0`). Anda dapat mengubahnya dengan mengedit _flags_ CLI di dalam `start_cctv.bat`:
`python bin\cctv.py --port 8080 --fps 15 --quality 50 --width 1280 --height 720`

## Akses Live View (Dari Browser)

Buka browser di HP/PC pemantau, lalu masukkan URL:
`http://<IP_PC_SERVER>:<PORT>`

> **Contoh via Tailscale:** `http://100.90.80.70:5000`
> **Contoh via LAN/Wi-Fi:** `http://192.168.1.15:5000`

### Daftar API Endpoint

| Endpoint    | Keterangan                                                        |
| ----------- | ----------------------------------------------------------------- |
| `/`         | Halaman Web UI utama (mendukung streaming & auto-reconnect)       |
| `/stream`   | Raw MJPEG stream (cocok untuk integrasi ke aplikasi IoT/NVR lain) |
| `/snapshot` | Download single frame JPEG (_snapshot_) langsung dari memori      |
| `/status`   | Data monitoring JSON (uptime, kamera OK, jumlah penonton)         |

**Contoh Response `/status`:**

```json
{
  "status": "ok",
  "camera_ok": true,
  "uptime_seconds": 3600,
  "frame_age_seconds": 0.1,
  "active_viewers": 1
}
```
