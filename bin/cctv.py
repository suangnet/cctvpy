import os
import sys
import cv2
import time
import atexit
import signal
import logging
import argparse
import threading
from datetime import datetime
from logging.handlers import RotatingFileHandler
from wsgiref.simple_server import make_server, WSGIServer
from socketserver import ThreadingMixIn
from flask import Flask, Response, jsonify, make_response

# ==========================================
# CONFIGURATION DEFAULTS
# ==========================================
DEFAULT_PORT = 5000
DEFAULT_FPS = 10
DEFAULT_QUALITY = 40
DEFAULT_WIDTH = 640
DEFAULT_HEIGHT = 480
DEFAULT_CAMERA = 0
# ==========================================


def parse_args():
    p = argparse.ArgumentParser(description="CCTV streaming server")
    p.add_argument("--port", type=int, default=DEFAULT_PORT)
    p.add_argument("--fps", type=int, default=DEFAULT_FPS)
    p.add_argument("--quality", type=int, default=DEFAULT_QUALITY)
    p.add_argument("--width", type=int, default=DEFAULT_WIDTH)
    p.add_argument("--height", type=int, default=DEFAULT_HEIGHT)
    p.add_argument("--camera", type=int, default=DEFAULT_CAMERA)
    return p.parse_args()


# ==========================================
# LOGGING (stdlib RotatingFileHandler)
# ==========================================
os.makedirs("log", exist_ok=True)
logger = logging.getLogger("cctv")
logger.setLevel(logging.INFO)
_handler = RotatingFileHandler(
    os.path.join("log", "cctv_server.log"),
    maxBytes=5 * 1024 * 1024,  # 5 MB
    backupCount=2,
)
_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
logger.addHandler(_handler)
# Also log to stderr so batch-mode redirect still works
logger.addHandler(logging.StreamHandler())


# ==========================================
# GLOBALS
# ==========================================
app = Flask(__name__)

latest_frame = None  # JPEG bytes
frame_lock = threading.Lock()
frame_event = threading.Event()  # set when a new frame is available
client_count = 0  # number of active streaming generators
client_lock = threading.Lock()
camera_ok = True  # flag: is camera currently readable?
start_time = time.time()
last_frame_time = 0.0  # timestamp of last successful frame


# ==========================================
# CAMERA MANAGEMENT
# ==========================================
camera = None  # cv2.VideoCapture, initialized in open_camera()


def open_camera(cfg):
    """Open (or re-open) the camera with configured settings."""
    global camera, camera_ok
    if camera is not None:
        try:
            camera.release()
        except Exception:
            pass
    cam = cv2.VideoCapture(cfg.camera)
    if cam.isOpened():
        cam.set(cv2.CAP_PROP_FRAME_WIDTH, cfg.width)
        cam.set(cv2.CAP_PROP_FRAME_HEIGHT, cfg.height)
        cam.set(cv2.CAP_PROP_FPS, cfg.fps)
        # ponytail: CAP_PROP_BUFFERSIZE may be unsupported on some drivers; harmless no-op
        cam.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        camera = cam
        camera_ok = True
        logger.info("Camera %d opened (%dx%d)", cfg.camera, cfg.width, cfg.height)
        return True
    else:
        camera = cam
        camera_ok = False
        logger.error("Failed to open camera %d", cfg.camera)
        return False


def cleanup():
    """Release camera and remove PID file on exit."""
    global camera
    if camera is not None:
        try:
            camera.release()
            logger.info("Camera released on shutdown")
        except Exception:
            pass
    # Remove stale PID file so the control panel doesn't see a ghost process
    pid_path = os.path.join("tmp", "cctv.pid")
    try:
        os.remove(pid_path)
    except OSError:
        pass


atexit.register(cleanup)


def _signal_handler(sig, frame):
    logger.info("Signal %s received, shutting down", sig)
    cleanup()
    sys.exit(0)


# Windows supports SIGINT and SIGTERM (SIGTERM via taskkill)
signal.signal(signal.SIGINT, _signal_handler)
signal.signal(signal.SIGTERM, _signal_handler)


# ==========================================
# CAPTURE THREAD
# ==========================================
def capture_thread(cfg):
    """
    Continuously captures frames from the webcam.
    - Throttles camera.read() itself to avoid wasting CPU on discarded frames.
    - Skips JPEG encoding when no clients are connected.
    - Auto-recovers from camera failures with exponential backoff.
    """
    global latest_frame, camera_ok, last_frame_time

    fail_count = 0
    max_backoff = 60.0
    cached_ts_str = ""
    cached_ts_sec = 0
    frame_interval = 1.0 / cfg.fps

    while True:
        # --- Throttle: sleep BEFORE read to avoid decoding frames we discard ---
        time.sleep(frame_interval)

        if camera is None or not camera.isOpened():
            # Camera lost — attempt recovery with backoff
            fail_count += 1
            backoff = min(0.5 * (2**fail_count), max_backoff)
            logger.warning(
                "Camera unavailable, retry in %.1fs (attempt %d)", backoff, fail_count
            )
            camera_ok = False
            time.sleep(backoff)
            open_camera(cfg)
            continue

        success, frame = camera.read()
        if not success:
            fail_count += 1
            if fail_count >= 5:
                # Persistent failure — try reopening
                backoff = min(0.5 * (2 ** min(fail_count, 10)), max_backoff)
                logger.warning(
                    "Camera read failed %dx, reopening in %.1fs", fail_count, backoff
                )
                camera_ok = False
                time.sleep(backoff)
                open_camera(cfg)
            else:
                time.sleep(0.1)
            continue

        # Success — reset failure counter
        fail_count = 0
        camera_ok = True
        last_frame_time = time.time()

        # --- Skip encoding when nobody is watching ---
        with client_lock:
            viewers = client_count
        if viewers == 0:
            continue

        # --- Timestamp overlay (cached per-second) ---
        now_sec = int(last_frame_time)
        if now_sec != cached_ts_sec:
            cached_ts_sec = now_sec
            cached_ts_str = datetime.now().strftime("%d/%m/%Y %H:%M:%S WITA")

        h, w = frame.shape[:2]
        # Drop shadow
        cv2.putText(
            frame,
            cached_ts_str,
            (11, h - 9),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (0, 0, 0),
            1,
            cv2.LINE_AA,
        )
        # Main text
        cv2.putText(
            frame,
            cached_ts_str,
            (10, h - 10),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (255, 255, 255),
            1,
            cv2.LINE_AA,
        )

        # --- JPEG encode ---
        ret, buffer = cv2.imencode(
            ".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), cfg.quality]
        )
        if ret:
            with frame_lock:
                latest_frame = buffer.tobytes()
            frame_event.set()


# ==========================================
# STREAM GENERATOR
# ==========================================
def generate_frames(fps_limit):
    """Yield JPEG frames as MJPEG multipart response. Uses Event to avoid busy-loop."""
    global client_count
    with client_lock:
        client_count += 1
    try:
        timeout = 2.0 / fps_limit  # slightly longer than frame interval
        while True:
            # Wait for a new frame instead of polling
            frame_event.wait(timeout=timeout)
            frame_event.clear()

            with frame_lock:
                frame_bytes = latest_frame
            if frame_bytes is not None:
                yield (
                    b"--frame\r\n"
                    b"Content-Type: image/jpeg\r\n\r\n" + frame_bytes + b"\r\n"
                )
    except GeneratorExit:
        pass
    finally:
        with client_lock:
            client_count -= 1


# ==========================================
# HTML PAGE WITH AUTO-RECONNECT
# ==========================================
HTML_PAGE = """<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>CCTV Live</title>
<style>
  body{margin:0;background:#111;display:flex;justify-content:center;align-items:center;height:100vh}
  img{max-width:100%;max-height:100vh}
  #status{position:fixed;top:8px;left:8px;color:#0f0;font:14px monospace;background:rgba(0,0,0,.6);padding:4px 8px;border-radius:4px}
  #status.err{color:#f44}
  #status.paused{color:#fd0}
</style>
</head><body>
<div id="status">LIVE</div>
<img id="feed" src="/stream" alt="CCTV">
<script>
const img=document.getElementById('feed'),st=document.getElementById('status');
let retryTimer;
img.onerror=()=>{st.textContent='RECONNECTING...';st.className='err';retryTimer=setTimeout(()=>{img.src='/stream?t='+Date.now()},3000)};
img.onload=()=>{st.textContent='LIVE';st.className=''};

// Pause stream when tab is inactive to save bandwidth
document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
        clearTimeout(retryTimer);
        img.src = ''; // Stops the MJPEG stream request
        st.textContent = 'PAUSED (Tab Inactive)';
        st.className = 'paused';
    } else {
        st.textContent = 'RESUMING...';
        st.className = '';
        img.src = '/stream?t=' + Date.now(); // Restart stream
    }
});
</script>
</body></html>"""


# ==========================================
# ROUTES
# ==========================================
@app.route("/")
def index():
    """HTML page with embedded MJPEG stream and auto-reconnect."""
    return HTML_PAGE, 200, {"Content-Type": "text/html"}


@app.route("/stream")
def video_feed():
    """Raw MJPEG stream endpoint."""
    cfg = app.config.get("cctv_cfg")
    return Response(
        generate_frames(cfg.fps), mimetype="multipart/x-mixed-replace; boundary=frame"
    )


@app.route("/snapshot")
def snapshot():
    """Return a single JPEG snapshot from the latest frame."""
    with frame_lock:
        frame_bytes = latest_frame

    if frame_bytes is None:
        return "No frame available", 503

    response = make_response(frame_bytes)
    response.headers.set("Content-Type", "image/jpeg")
    response.headers.set(
        "Content-Disposition", "attachment", filename=f"snapshot_{int(time.time())}.jpg"
    )
    return response


@app.route("/status")
def health():
    """Status endpoint for monitoring scripts."""
    with client_lock:
        viewers = client_count
    age = time.time() - last_frame_time if last_frame_time > 0 else -1
    return jsonify(
        {
            "status": "ok" if camera_ok else "camera_error",
            "camera_ok": camera_ok,
            "uptime_seconds": int(time.time() - start_time),
            "frame_age_seconds": round(age, 1),
            "active_viewers": viewers,
        }
    )


# ==========================================
# THREADED WSGI SERVER (stdlib, replaces Flask dev server)
# ==========================================
class ThreadedWSGIServer(ThreadingMixIn, WSGIServer):
    """Handle each request in a new thread — required for MJPEG streaming."""

    daemon_threads = True


# ==========================================
# MAIN
# ==========================================
if __name__ == "__main__":
    cfg = parse_args()
    app.config["cctv_cfg"] = cfg

    # Open camera before writing PID — if it fails, PID is still written
    # so the bat script can manage the process, but we log the error.
    open_camera(cfg)

    # Write PID only after we're actually starting
    os.makedirs("tmp", exist_ok=True)
    with open(os.path.join("tmp", "cctv.pid"), "w") as f:
        f.write(str(os.getpid()))

    # Start capture thread
    t = threading.Thread(target=capture_thread, args=(cfg,), daemon=True)
    t.start()

    logger.info(
        "CCTV server starting on 0.0.0.0:%d (FPS=%d, quality=%d)",
        cfg.port,
        cfg.fps,
        cfg.quality,
    )

    import _thread
    def check_stop_marker():
        while True:
            if os.path.exists(os.path.join("tmp", "stop.marker")):
                logger.info("Stop marker detected. Triggering shutdown...")
                _thread.interrupt_main()
                break
            time.sleep(1)
    
    threading.Thread(target=check_stop_marker, daemon=True).start()

    # Use stdlib threaded WSGI server instead of Flask dev server
    # ponytail: if concurrent viewers > ~10, consider waitress or gunicorn
    server = make_server("0.0.0.0", cfg.port, app, server_class=ThreadedWSGIServer)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("Keyboard interrupt, shutting down")
    finally:
        server.shutdown()
        cleanup()
