# Deploy & Remote Control CCTV via SSH (Windows → Windows)

Target: `user@100.90.80.80` (via Tailscale)

---

## Langkah 1: Copy Project ke Komputer Target (SCP)

Jalankan di **PowerShell lokal** (komputer CCTV sumber):

```powershell
# PENTING: Pastikan folder target sudah ada dulu
# (Windows SSH default shell = PowerShell, jadi gunakan syntax PS)
ssh user@100.90.80.80 "New-Item -ItemType Directory -Force -Path C:\CCTV | Out-Null"

# Copy HANYA folder bin dan start_cctv.bat
scp -r C:\CCTV\bin C:\CCTV\start_cctv.bat user@100.90.80.80:C:/CCTV/
```

> **Kenapa hanya file tertentu?** Folder lain seperti `tmp` dan `log` akan dibuat secara otomatis oleh script, sedangkan `README.md` tidak dibutuhkan di komputer target.
>
> Masukkan password saat diminta.

---

## Langkah 2: Masuk via SSH

```powershell
ssh user@100.90.80.80
```

---

## Langkah 3: Install Dependencies di Komputer Target

Setelah masuk SSH, jalankan:

```powershell
pip install flask opencv-python
```

---

## Langkah 4: Operasi Start / Stop / Status (via SSH)

Skrip Control Panel (`start_cctv.bat`) dapat dioperasikan secara **interaktif** maupun langsung via **CLI flags satu baris** (sangat ideal untuk otomasi SSH):

### Cara 1: Langsung via Parameter CLI (Direkomendasikan via SSH)

Jalankan perintah langsung dari sesi SSH lokal tanpa harus membuka menu interaktif:

```powershell
# Cek status server
ssh user@100.90.80.80 "C:\CCTV\start_cctv.bat --status"

# Jalankan server secara tersembunyi di background
ssh user@100.90.80.80 "C:\CCTV\start_cctv.bat --background"

# Hentikan server secara graceful
ssh user@100.90.80.80 "C:\CCTV\start_cctv.bat --stop"

# Ambil foto snapshot langsung
ssh user@100.90.80.80 "C:\CCTV\start_cctv.bat --snapshot"
```

### Cara 2: Menu Interaktif

1.  Masuk melalui SSH ke komputer target:
    ```powershell
    ssh user@100.90.80.80
    ```
2.  Eksekusi file Control Panel secara langsung:
    ```cmd
    C:\CCTV\start_cctv.bat
    ```
3.  Menu antarmuka Control Panel akan muncul dan mendeteksi status terbaru (`RUNNING` / `STOPPED`).
4.  Pilih opsi **2** untuk _Start CCTV Server (Background)_ atau **3** untuk _Stop CCTV Server_ sesuai kebutuhan.

Skrip menggunakan **Smart Multi-Backend Camera (MSMF + DSHOW)** dan mekanisme _graceful shutdown_ (file `stop.marker`). Ini 100% andal menanggulangi bug _force kill_ di Windows 11, memastikan _stream_ berhenti rapi, proses tidak nyangkut (zombie), dan lampu indikator kamera mati dengan sempurna.

---

## Akses Live View dari Browser

Setelah server running di `100.90.80.80`, buka browser di komputer manapun yang terhubung Tailscale:

| URL                               | Fungsi                             |
| --------------------------------- | ---------------------------------- |
| `http://100.90.80.80:5000/`       | Halaman HTML dengan auto-reconnect |
| `http://100.90.80.80:5000/stream` | Raw MJPEG stream                   |
| `http://100.90.80.80:5000/status` | JSON status server                 |

---

## Autostart saat Boot (opsional, jalankan dari SSH)

Karena Control Panel (`start_cctv.bat`) tidak bisa dijalankan secara interaktif via SSH, gunakan salah satu cara berikut dari PowerShell SSH session:

### Cara A: Startup Folder (tanpa admin)

```powershell
# Enable autostart — copy start_cctv.bat ke Startup Folder user
$startup = [Environment]::GetFolderPath("Startup")
Copy-Item "C:\CCTV\start_cctv.bat" "$startup\start_cctv.bat" -Force
Write-Host "Autostart ENABLED: $startup\start_cctv.bat"
```

```powershell
# Disable autostart — hapus dari Startup Folder
$startup = [Environment]::GetFolderPath("Startup")
Remove-Item "$startup\start_cctv.bat" -ErrorAction SilentlyContinue
Write-Host "Autostart DISABLED"
```

> Menyala setelah user login. Ekuivalen dengan opsi **6/7** di Control Panel.

### Cara B: Scheduled Task (menyala sebelum login, butuh admin)

```powershell
# Enable
$action = New-ScheduledTaskAction `
  -Execute "python" `
  -Argument "bin\cctv.py" `
  -WorkingDirectory "C:\CCTV"

$trigger = New-ScheduledTaskTrigger -AtStartup

$settings = New-ScheduledTaskSettingsSet `
  -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
  -RestartCount 3 `
  -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask `
  -TaskName "CCTV_Server" `
  -Action $action `
  -Trigger $trigger `
  -Settings $settings `
  -RunLevel Highest `
  -Force

Start-ScheduledTask -TaskName "CCTV_Server"
```

```powershell
# Disable
Unregister-ScheduledTask -TaskName "CCTV_Server" -Confirm:$false
```
