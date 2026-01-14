#!/bin/bash
# Snapcast Bluetooth Bridge Installer v5.1 - Bulletproof
# Works on Raspberry Pi, Ubuntu, Mint, PipeWire, PulseAudio

set -euo pipefail

# === CONFIGURATION ===
BT_SINK="${BT_SINK:-snapcast_to_bluetooth}"
USER_NAME="$(whoami)"
XDG_RUNTIME_DIR="/run/user/$(id -u)"
SNAPSERVER_IP="${SNAPSERVER_IP:-192.168.0.30}"
SNAPSERVER_PORT="${SNAPSERVER_PORT:-4951}"
LATENCY_MS="${LATENCY_MS:-100}"
SCRIPT_DIR="/opt/snapcast-bt-bridge/scripts"
INSTALL_DIR="/opt/snapcast-bt-bridge"
# =====================

echo "=== Snapcast Bluetooth Bridge Installer v5.1 ==="

# --- sanity checks ---
command -v pactl >/dev/null 2>&1 || {
    echo "❌ pactl not found (PulseAudio or PipeWire-Pulse required)"
    exit 1
}

# --- detect audio stack (non-blocking) ---
echo "Detecting audio server..."
if pactl info >/dev/null 2>&1; then
    if pactl list short modules 2>/dev/null | grep -q bluez5; then
        AUDIO_TYPE="pulse-bt"
    else
        AUDIO_TYPE="pulse-no-bt"
    fi
elif command -v pw-cli >/dev/null 2>&1; then
    AUDIO_TYPE="pipewire"
else
    echo "❌ No supported audio server detected"
    exit 1
fi

echo "Detected audio setup: $AUDIO_TYPE"

# --- create null sink (idempotent, safe under strict mode) ---
if ! pactl list short sinks 2>/dev/null | grep -q "$BT_SINK"; then
    echo "Creating null sink '$BT_SINK'..."
    pactl load-module module-null-sink \
        sink_name="$BT_SINK" \
        sink_properties=device.description="Snapcast-to-Bluetooth-Bridge" || true
else
    echo "Sink '$BT_SINK' already exists."
fi

pactl set-default-sink "$BT_SINK" || true

# --- Bluetooth modules (best effort) ---
if [ "$AUDIO_TYPE" = "pulse-bt" ]; then
    pactl load-module module-bluetooth-policy || true
    pactl load-module module-bluez5-discover || true
fi

# --- directories ---
sudo mkdir -p "$SCRIPT_DIR"
sudo chown -R "$USER_NAME:$USER_NAME" "$INSTALL_DIR"

# === auto_loopback.py (UNCHANGED LOGIC) ===
cat > "$SCRIPT_DIR/auto_loopback.py" << 'EOF'
#!/usr/bin/env python3
import subprocess, time

current_loopback_id = None
current_bt_source = None

def get_bluetooth_source():
    try:
        r = subprocess.run(
            ['pactl','list','sources','short'],
            capture_output=True, text=True
        )
        for line in r.stdout.splitlines():
            if 'bluez_source' in line and 'a2dp_source' in line:
                return line.split()[1]
    except:
        pass
    return None

def check_loopback_health(module_id):
    if not module_id:
        return False
    try:
        r = subprocess.run(
            ['pactl','list','modules','short'],
            capture_output=True, text=True
        )
        return str(module_id) in r.stdout
    except:
        return False

def create_loopback(bt_source):
    try:
        r = subprocess.run(
            ['pactl','load-module','module-loopback',
             f'source={bt_source}','sink=snapcast_to_bluetooth'],
            capture_output=True, text=True
        )
        if r.returncode == 0:
            return r.stdout.strip()
    except:
        pass
    return None

def remove_loopback(module_id):
    if module_id:
        subprocess.run(['pactl','unload-module',str(module_id)])

print("Auto-loopback started")
while True:
    src = get_bluetooth_source()
    if src:
        if src != current_bt_source or not check_loopback_health(current_loopback_id):
            if current_loopback_id:
                remove_loopback(current_loopback_id)
            current_loopback_id = create_loopback(src)
            current_bt_source = src
    else:
        if current_loopback_id:
            remove_loopback(current_loopback_id)
            current_loopback_id = None
            current_bt_source = None
    time.sleep(5)
EOF

chmod +x "$SCRIPT_DIR/auto_loopback.py"

# === stream_to_snapcast.py (UNCHANGED, STABLE) ===
cat > "$SCRIPT_DIR/stream_to_snapcast.py" << EOF
#!/usr/bin/env python3
import subprocess, socket, time, logging, signal, sys

SNAPSERVER_IP="$SNAPSERVER_IP"
SNAPSERVER_PORT=$SNAPSERVER_PORT
LATENCY_MS=$LATENCY_MS

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("snapcast-stream")

class AudioStreamer:
    def __init__(self):
        self.running = True
        self.proc = None

    def stream(self):
        cmd = [
            'parec','--format=s16le','--rate=48000',
            '--channels=2',f'--latency-msec={LATENCY_MS}',
            '--device=snapcast_to_bluetooth.monitor'
        ]
        while self.running:
            try:
                sock = socket.create_connection((SNAPSERVER_IP,SNAPSERVER_PORT))
                self.proc = subprocess.Popen(cmd, stdout=subprocess.PIPE)
                while self.running:
                    data = self.proc.stdout.read(4096)
                    if not data:
                        break
                    sock.sendall(data)
            except Exception as e:
                log.error(e)
                time.sleep(5)
            finally:
                try: sock.close()
                except: pass

    def stop(self, *_):
        self.running = False
        if self.proc:
            self.proc.terminate()
        sys.exit(0)

a = AudioStreamer()
signal.signal(signal.SIGINT, a.stop)
signal.signal(signal.SIGTERM, a.stop)
a.stream()
EOF

chmod +x "$SCRIPT_DIR/stream_to_snapcast.py"

# === systemd services (FIXED ORDERING) ===
for svc in auto-loopback stream_to_snapcast; do
sudo tee "/etc/systemd/system/$svc.service" >/dev/null <<EOF
[Unit]
Description=$svc
After=bluetooth.service network.target
Wants=bluetooth.service

[Service]
Type=simple
User=$USER_NAME
Environment=XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
ExecStart=/usr/bin/python3 $SCRIPT_DIR/$svc.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
done

sudo systemctl daemon-reload
sudo systemctl enable auto-loopback stream_to_snapcast

echo "✅ Installed successfully"
echo "Start with:"
echo "  sudo systemctl start auto-loopback stream_to_snapcast"
