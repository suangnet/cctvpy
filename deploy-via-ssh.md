# Deploy & Remote Control CCTV via SSH (Windows to Windows)

> **Note:** Replace `user` with your target account username and `<target_ip>` with your target machine IP address (e.g., LAN IP `192.168.8.100` or Tailscale IP `100.x.y.z`).

---

## Step 0: Register SSH Key (Passwordless Login)

### 1. Generate SSH Key on Local Machine (if not already present)

Run in local PowerShell:

```powershell
ssh-keygen -t ed25519
```

Press Enter to accept the default file location (`~/.ssh/id_ed25519`) and passphrase (can be empty).

---

### 2. Add Public Key to Target Windows 11

#### Case A: Standard User (Non-Administrator)

**Method 1 (Automatic from local terminal via SSH/PowerShell):**

```powershell
Get-Content ~/.ssh/id_ed25519.pub | ssh user@<target_ip> "powershell -Command `"New-Item -ItemType Directory -Force -Path `"`$HOME\.ssh`" | Out-Null; Add-Content -Path `"`$HOME\.ssh\authorized_keys`" -Value `$input`""
```

**Method 2 (Manual on target Windows 11):**

1. Open PowerShell on the target computer under your user account.
2. Create the `.ssh` directory and `authorized_keys` file:

   ```powershell
   New-Item -ItemType Directory -Force -Path "$HOME\.ssh" | Out-Null
   New-Item -ItemType File -Force -Path "$HOME\.ssh\authorized_keys" | Out-Null
   ```

3. Paste your public key into the file (for example, with Notepad):

   ```powershell
   notepad "$HOME\.ssh\authorized_keys"
   ```

   Paste the contents of `id_ed25519.pub`, save (`Ctrl + S`), and close.

   Or append directly via PowerShell in a single line:

   ```powershell
   Add-Content -Path "$HOME\.ssh\authorized_keys" -Value "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... user@client"
   ```

4. **Required: Configure File Access Permissions (ACL)**
   Windows OpenSSH denies key-based authentication if `authorized_keys` is accessible by other non-system users. Restrict permissions to your current user and SYSTEM:

   ```powershell
   icacls.exe "$HOME\.ssh\authorized_keys" /inheritance:r /grant:r "$($env:USERNAME):(R,W)" /grant:r "SYSTEM:(F)"
   ```

#### Case B: Administrator User (Default on most Windows 11 installations)

Windows OpenSSH ignores `~/.ssh/authorized_keys` by default for users in the `Administrators` group.

Select one of the solutions below:

**Option 1 (Recommended: Standardize with OpenSSH defaults):**

1. Open PowerShell (Run as Administrator) on target Windows 11.
2. Edit `C:\ProgramData\ssh\sshd_config` and comment out the last two lines:

   ```text
   #Match Group administrators
   #       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
   ```

3. Restart the OpenSSH service on target:

   ```powershell
   Restart-Service sshd
   ```

4. Follow **Case A** above (`~/.ssh/authorized_keys` will now be active for all accounts).

**Option 2 (Without editing sshd_config):**

Run in PowerShell (Admin) on target Windows 11:

```powershell
New-Item -ItemType File -Force -Path "C:\ProgramData\ssh\administrators_authorized_keys" | Out-Null
Add-Content -Path "C:\ProgramData\ssh\administrators_authorized_keys" -Value "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5... user@client"
icacls.exe "C:\ProgramData\ssh\administrators_authorized_keys" /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
```

---

## Step 1: Copy Project to Target Machine (SCP)

Run from local PowerShell:

```powershell
# Ensure destination folder exists
ssh user@<target_ip> "if not exist C:\CCTV mkdir C:\CCTV"

# Copy required bin folder and start_cctv.bat script
scp -r C:\CCTV\bin C:\CCTV\start_cctv.bat user@<target_ip>:C:/CCTV/
```

> **Why only specific files?** Runtime folders like `tmp` and `log` are generated automatically upon server launch. `README.md` is not required on the target machine.

---

## Step 2: Connect via SSH

```powershell
ssh user@<target_ip>
```

---

## Step 3: Install Dependencies on Target Machine

After connecting via SSH, run:

```powershell
pip install flask opencv-python
```

---

## Step 4: Start, Stop, and Status Management (via SSH)

The control panel script ([`start_cctv.bat`](start_cctv.bat)) supports both interactive mode and direct one-line CLI arguments:

### Method 1: Direct CLI Flags (Recommended for SSH Automation)

Run commands directly from your local terminal:

```powershell
# Check server status
ssh user@<target_ip> "C:\CCTV\start_cctv.bat --status"

# Run server in the background
ssh user@<target_ip> "C:\CCTV\start_cctv.bat --background"

# Stop server gracefully
ssh user@<target_ip> "C:\CCTV\start_cctv.bat --stop"

# Capture a camera snapshot
ssh user@<target_ip> "C:\CCTV\start_cctv.bat --snapshot"
```

### Method 2: Interactive Menu

1. Connect to target machine via SSH:
   ```powershell
   ssh user@<target_ip>
   ```
2. Run the control panel script:
   ```cmd
   C:\CCTV\start_cctv.bat
   ```
3. The menu displays the current status (`RUNNING` or `STOPPED`).
4. Select option **2** to start the background server or option **3** to stop it.

---

## Viewing Camera Stream

Once the server is running on `<target_ip>`, open a browser on any machine within the same local network or Tailscale mesh:

| URL                              | Description                       |
| -------------------------------- | --------------------------------- |
| `http://<target_ip>:5000/`       | Web viewer UI with auto-reconnect |
| `http://<target_ip>:5000/stream` | Raw multipart MJPEG video stream  |
| `http://<target_ip>:5000/status` | Server status JSON                |

---

## Background Autostart on Boot (Optional, via SSH)

The server runs silently in the background without a terminal window using `pythonw.exe`. Select one of the following autostart options:

### Option A: Automatic CLI Flags (Recommended, No Admin Required)

Run directly through SSH:

```powershell
# Enable silent background autostart (creates startup shortcut targeting pythonw.exe)
ssh user@<target_ip> "C:\CCTV\start_cctv.bat --enable-autostart"

# Disable autostart
ssh user@<target_ip> "C:\CCTV\start_cctv.bat --disable-autostart"
```

> Starts silently in the background whenever the user logs into Windows. Equivalent to options **5** and **6** in the interactive menu.

### Option B: Windows Scheduled Task (Requires Admin Privileges)

```powershell
# Enable (uses pythonw and AtLogOn trigger to preserve desktop camera access)
$action = New-ScheduledTaskAction `
  -Execute "pythonw" `
  -Argument "bin\cctv.py" `
  -WorkingDirectory "C:\CCTV"

$trigger = New-ScheduledTaskTrigger -AtLogOn

$settings = New-ScheduledTaskSettingsSet `
  -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
  -RestartCount 3 `
  -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask `
  -TaskName "CCTV_Server" `
  -Action $action `
  -Trigger $trigger `
  -RunLevel Highest `
  -Force

Start-ScheduledTask -TaskName "CCTV_Server"
```

```powershell
# Disable
Unregister-ScheduledTask -TaskName "CCTV_Server" -Confirm:$false
```
