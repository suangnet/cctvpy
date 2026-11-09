# Deploy & Remote Control CCTV via SSH (Windows → Windows)

Target: `user@100.90.80.80` (via Tailscale)

---

## Langkah 0: Registrasi SSH Key (Login Tanpa Password)

### 1. Buat SSH Key di Komputer Lokal (jika belum ada)

Jalankan di terminal lokal:

```powershell
ssh-keygen -t ed25519
```

Tekan Enter untuk lokasi default (`~/.ssh/id_ed25519`) dan passphrase (bisa dikosongkan).

---

### 2. Daftarkan Public Key ke Windows 11 Target

#### Kasus A: User Biasa (Non-Administrator)

**Cara 1 (Otomatis dari Komputer Lokal via SSH/PowerShell):**

```powershell
Get-Content ~/.ssh/id_ed25519.pub | ssh user@100.90.80.80 "powershell -Command `"New-Item -ItemType Directory -Force -Path `"`$HOME\.ssh`" | Out-Null; Add-Content -Path `"`$HOME\.ssh\authorized_keys`" -Value `$input`""
```

**Cara 2 (Manual Langsung di Komputer Windows 11 Target):**

1. Buka PowerShell biasa (sebagai user tersebut) di Windows 11 target.
2. Buat folder `.ssh` dan file `authorized_keys`:

   ```powershell
   # Buat folder .ssh jika belum ada
   New-Item -ItemType Directory -Force -Path "$HOME\.ssh" | Out-Null

   # Buat file authorized_keys jika belum ada
   New-Item -ItemType File -Force -Path "$HOME\.ssh\authorized_keys" | Out-Null
   ```

3. Buka dan tempelkan public key (misal menggunakan Notepad):

   ```powershell
   notepad "$HOME\.ssh\authorized_keys"
   ```

   _Paste_ isi `id_ed25519.pub` ke Notepad, lalu Save (`Ctrl + S`) dan Close.

   _(Atau langsung via PowerShell satu baris):_

   ```powershell
   Add-Content -Path "$HOME\.ssh\authorized_keys" -Value "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... user@client"
   ```

4. **PENTING: Atur Hak Akses (Permissions / ACL)**
   Windows OpenSSH akan menolak autentikasi jika file `authorized_keys` bisa diakses oleh akun lain. Kunci permission hanya untuk user Anda dan SYSTEM:
   ```powershell
   # Putus inheritance dan batasi izin hanya untuk user aktif & SYSTEM
   icacls.exe "$HOME\.ssh\authorized_keys" /inheritance:r /grant:r "$($env:USERNAME):(R,W)" /grant:r "SYSTEM:(F)"
   ```

#### Kasus B: User Administrator (Default di kebanyakan Windows 11)

Windows OpenSSH secara default mengabaikan `~/.ssh/authorized_keys` jika akun termasuk grup `Administrators`.

Pilih salah satu solusi di bawah:

**Opsi 1 (Disarankan — Samakan standar Linux/OpenSSH):**

1. Buka PowerShell (Run as Administrator) di Windows 11 target.
2. Edit file konfigurasi `C:\ProgramData\ssh\sshd_config`:
   Beri tanda komentar (`#`) pada 2 baris paling bawah:
   ```
   #Match Group administrators
   #       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
   ```
3. Restart OpenSSH service di target:
   ```powershell
   Restart-Service sshd
   ```
4. Setelah itu, ikuti perintah **Kasus A** di atas (`~/.ssh/authorized_keys` akan aktif untuk semua user).

**Opsi 2 (Tanpa ubah sshd_config):**
Jalankan di PowerShell (Admin) di Windows 11 target:

```powershell
# Buat file administrators_authorized_keys jika belum ada
New-Item -ItemType File -Force -Path "C:\ProgramData\ssh\administrators_authorized_keys" | Out-Null

# Masukkan public key Anda ke file tersebut
Add-Content -Path "C:\ProgramData\ssh\administrators_authorized_keys" -Value "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... user@client"

# Atur ACL permission wajib (hanya SYSTEM dan Administrators)
icacls.exe "C:\ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
```

---

## Langkah 1: Copy Project ke Komputer Target (SCP)

Jalankan di **PowerShell lokal** (komputer CCTV sumber):

```powershell
# PENTING: Pastikan folder target sudah ada dulu
# (Default shell OpenSSH Windows adalah cmd.exe, gunakan mkdir bawaan cmd)
ssh user@100.90.80.80 "if not exist C:\CCTV mkdir C:\CCTV"

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
