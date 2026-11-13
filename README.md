# Windows Private CCTV Server

A lightweight Windows-based local CCTV server for live video streaming (MJPEG) directly through a web browser without disk recording. Accessible over local network (LAN/Wi-Fi) or remotely via Tailscale.

## Directory Structure

```text
C:\CCTV\
│   start_cctv.bat      # CLI control panel and automation script
│
├───bin\
│       cctv.py         # Python server application (Flask + OpenCV)
│
├───log\
│       cctv_server.log      # Application logs (rotating 5 MB x 2 files)
│       cctv_console_out.log # stdout redirect for background mode
│       cctv_console_err.log # stderr redirect for background mode
│
└───tmp\
        cctv.pid        # Active process PID file
        stop.marker     # Marker file for graceful shutdown
```

## Key Features

- **Browser streaming without client dependencies**: Streams standard multipart MJPEG directly to modern browsers without third-party video players.
- **Multi-backend camera support**: Opens cameras using Media Foundation (MSMF) or DirectShow (DSHOW), with automatic index fallback (probes index 0, 1, or 2).
- **Power and resource efficiency**: Pauses JPEG frame compression when no viewers are connected, and pauses frame transmission when the browser tab is hidden.
- **Isolated background execution**: Spawns as an independent background process via WMI and `pythonw.exe` to remain active even when SSH sessions disconnect.
- **Controlled graceful shutdown**: Releases camera hardware cleanly using a marker file to ensure indicator lights turn off and prevent zombie processes.
- **CLI and SSH automation**: All control panel operations can be run directly from one-line CLI commands without launching the interactive menu.
- **REST API**: Built-in endpoints for instant snapshot capture (JPEG) and operational health status (JSON).

## System Requirements

| Component        | Minimum Requirement         | Recommended                                      |
| ---------------- | --------------------------- | ------------------------------------------------ |
| Operating System | Windows 7 64-bit            | Windows 10/11 64-bit                             |
| Memory (RAM)     | 512 MB                      | 1 GB or more                                     |
| Camera           | External USB webcam         | Built-in laptop webcam                           |
| Environment      | Python 3.9                  | Python 3.12 or newer                             |
| Network          | Local network (LAN / Wi-Fi) | Tailscale installed on server and viewing device |

## Prerequisites

1. Install Python 3.9 or newer from [python.org](https://www.python.org/downloads/). Ensure **Add Python to PATH** is checked during setup.
2. On Windows 10 or 11, open **Settings > Privacy & security > Camera**, and verify that **Let desktop apps access your camera** is set to **On**.
3. If using a laptop with the lid closed, open **Power Options** and set **When I close the lid** to **Do nothing**.
4. Install Tailscale on both the server and monitoring devices for remote access outside the local network.

## Installation & Running the Server

### 1. Install Dependencies

Open a terminal and run:

```cmd
pip install flask opencv-python
```

For resource-constrained devices, `opencv-python-headless` can be installed instead of `opencv-python`.

### 2. Launch the Control Panel

Double-click [`start_cctv.bat`](start_cctv.bat) to open the interactive menu:

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

### 3. Direct CLI & SSH Commands

Run commands directly without entering the menu:

```cmd
start_cctv.bat --start               # Run in a new visible console window
start_cctv.bat --background          # Run hidden in background via pythonw
start_cctv.bat --status              # Check server process status
start_cctv.bat --snapshot            # Capture immediate photo to log folder
start_cctv.bat --stop                # Gracefully stop the server process
start_cctv.bat --enable-autostart    # Enable silent background autostart on login
start_cctv.bat --disable-autostart   # Disable login autostart
```

Detailed instructions for headless setup and SSH keys are available in [`deploy-via-ssh.md`](deploy-via-ssh.md).

### 4. Optional Configuration Flags

The server defaults to port `5000` at 10 FPS. Customize these parameters in [`start_cctv.bat`](start_cctv.bat) or by running the script directly:

```cmd
python bin\cctv.py --port 8080 --fps 15 --quality 50 --width 1280 --height 720
```

## Viewing Camera Stream

Open a web browser on any device in the network and navigate to the server's IP address:

```text
http://<ip_target>:5000/
```

### HTTP Endpoints

| Endpoint    | Description                                                |
| ----------- | ---------------------------------------------------------- |
| `/`         | Web viewer UI with auto-reconnect                          |
| `/stream`   | Raw multipart MJPEG video stream                           |
| `/snapshot` | Download the latest single JPEG frame                      |
| `/status`   | Server status JSON (uptime, camera health, active viewers) |

Sample `/status` JSON response:

```json
{
  "status": "ok",
  "camera_ok": true,
  "uptime_seconds": 3600,
  "frame_age_seconds": 0.1,
  "active_viewers": 1
}
```
