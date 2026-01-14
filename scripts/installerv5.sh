#!/bin/bash
# Snapcast Bluetooth Bridge Installer v5 - Bulletproof
# Works on Raspberry Pi, Ubuntu, Mint, and other Linux desktops

set -euo pipefail

# === CONFIGURATION ===
BT_SINK="${BT_SINK:-snapcast_to_bluetooth}"
USER_NAME="$(whoami)"
XDG_RUNTIME_DIR="/run/user/$(id -u)"
SNAPSERVER_IP="${SNAPSERVER_IP:-192.168.0.30}"
SNAPSERVER_PORT=${SNAPSERVER_PORT:-4951}
LATENCY_MS=${LATENCY_MS:-100}
SCRIPT_DIR="/opt/snapcast-bt-bridge/scripts"
# =====================

echo "=== Snapcast Bluetooth Bridge Installer v5 ==="

# Detect audio server
echo "Detecting audio server..."
if pactl info >/dev/null 2>&1; then
    if pactl list short modules | grep -q bluez5; then
        AUDIO_TYPE="pulse-bt"
    else
        AUDIO_TYPE="pulse-no-bt"
    fi
elif command -v pw-cli >/dev/null 2>&1; then
    AUDIO_TYPE="pipewire"
else
    echo "❌ No supported audio server detected (PulseAudio or PipeWire required)."
    exit 1
fi

echo "Detected audio setup: $AUDIO_TYPE"

# Create Snapcast null sink
if pactl list short sinks | grep -q "$BT_SINK"; then
    echo "Sink '$BT_SINK' already exists."
else
    echo "Creating null sink '$BT_SINK'..."
    pactl load-module module-null-sink sink_name="$BT_SINK" sink_properties=device.description="Snapcast-to-Bluetooth-Bridge" || true
fi

echo "Setting default sink to '$BT_SINK'..."
pactl set-default-sink "$BT_SINK" || true

if [ "$AUDIO_TYPE" = "pulse-bt" ]; then
    echo "Loading PulseAudio Bluetooth modules..."
    pactl load-module module-bluetooth-policy || true
    pactl load-module module-bluez5-discover || true
fi

# Create script directories
sudo mkdir -p "$SCRIPT_DIR"
sudo chown -R $USER_NAME:$USER_NAME /opt/snapcast-bt-bridge

# === Install auto_loopback.py ===
cat > "$SCRIPT_DIR/auto_loopback.py" << 'EOF'
#!/usr/bin/env python3
import subprocess, time

current_loopback_id = None
current_bt_source = None


def get_bluetooth_source():
    try:
        result = subprocess.run(['pactl','list','sources','short'], capture_output=True, text=True)
        for line in result.stdout.split('\n'):
            if 'bluez_source' in line and 'a2dp_source' in line:
                return line.split()[1]
    except:
        pass
    return None


def check_loopback_health(module_id):
    if not module_id:
        return False
    try:
        result = subprocess.run(['pactl','list','modules','short'], capture_output=True, text=True)
        return str(module_id) in result.stdout
    except:
        return False


def create_loopback(bt_source):
    try:
        result = subprocess.run(['pactl','load-module','module-loopback', f'source={bt_source}','sink=snapcast_to_bluetooth'], capture_output=True, text=True)
        if result.returncode==0:
            module_id=result.stdout.strip()
            print(f"Loopback created: {module_id}")
            return module_id
    except Exception as e:
        print(f"Error creating loopback: {e}")
    return None


def remove_loopback(module_id):
    if module_id:
        try:
            subprocess.run(['pactl','unload-module',str(module_id)])
            print(f"Removed loopback: {module_id}")
        except:
            pass


print("Auto-loopback with health monitoring started")
while True:
    bt_source = get_bluetooth_source()
    if bt_source:
        if current_bt_source != bt_source:
            print(f"New Bluetooth source: {bt_source}")
            if current_loopback_id:
                remove_loopback(current_loopback_id)
            current_loopback_id = create_loopback(bt_source)
            current_bt_source = bt_source
        elif not check_loopback_health(current_loopback_id):
            print(f"Loopback broken, recreating...")
            if current_loopback_id:
                remove_loopback(current_loopback_id)
            current_loopback_id = create_loopback(bt_source)
    else:
        if current_loopback_id:
            print("No Bluetooth source")
            remove_loopback(current_loopback_id)
            current_loopback_id = None
            current_bt_source = None
    time.sleep(5)
EOF

chmod +x "$SCRIPT_DIR/auto_loopback.py"

# === Install stream_to_snapcast.py ===
cat > "$SCRIPT_DIR/stream_to_snapcast.py" << EOF
#!/usr/bin/env python3
import subprocess, socket, time, logging, signal, sys

SNAPSERVER_IP="$SNAPSERVER_IP"
SNAPSERVER_PORT=$SNAPSERVER_PORT
LATENCY_MS=$LATENCY_MS

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class AudioStreamer:
    def __init__(self):
        self.running = True
        self.process = None

    def stream_audio(self):
        command=['parec','--format=s16le','--rate=48000','--channels=2',f'--latency-msec={LATENCY_MS}','--device=snapcast_to_bluetooth.monitor']
        while self.running:
            try:
                sock=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
                sock.connect((SNAPSERVER_IP,SNAPSERVER_PORT))
                logger.info(f"Connected to Snapcast at {SNAPSERVER_IP}:{SNAPSERVER_PORT}")
                self.process=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                while self.running:
                    data=self.process.stdout.read(4096)
                    if not data:
                        break
                    sock.sendall(data)
            except Exception as e:
                logger.error(f"Error: {e}")
                if self.process:
                    self.process.terminate()
                if self.running:
                    time.sleep(5)
            finally:
                try: sock.close()
                except: pass

    def cleanup(self):
        self.running=False
        if self.process: self.process.terminate()

    def signal_handler(self, signum, frame):
        self.cleanup()
        sys.exit(0)

def main():
    streamer=AudioStreamer()
    signal.signal(signal.SIGINT, streamer.signal_handler)
    signal.signal(signal.SIGTERM, streamer.signal_handler)
    streamer.stream_audio()

if __name__=="__main__":
    main()
EOF

chmod +x "$SCRIPT_DIR/stream_to_snapcast.py"

# === Create systemd services ===
for service_name in auto-loopback stream_to_snapcast; do
    sudo tee /etc/systemd/system/${service_name}.service > /dev/null << EOF
[Unit]
Description=${service_name}
After=bluetooth.service pulseaudio.service network.target
Wants=bluetooth.service pulseaudio.service

[Service]
Type=simple
User=$USER_NAME
Environment=XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
ExecStart=/usr/bin/python3 $SCRIPT_DIR/${service_name}.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable ${service_name}.service
done

echo "✅ Snapcast Bluetooth Bridge installed!"
echo "Use 'sudo systemctl start/stop auto-loopback.service' and 'sudo systemctl start/stop stream_to_snapcast.service' to toggle services."
echo "Reboot, pair your Bluetooth device, and play audio."
echo "Snapcast stream available on TCP ${SNAPSERVER_IP}:${SNAPSERVER_PORT}."
