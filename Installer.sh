#!/bin/bash
# Raspberry Pi Bluetooth to Snapcast Bridge - COMPLETE WORKING VERSION
# Tested October 24, 2025 - Fully automatic, zero manual intervention
# Flash fresh Raspberry Pi OS Lite 32-bit, then run this script ONCE

set -e

echo "=== Raspberry Pi Bluetooth to Snapcast Bridge v2 ==="
echo "Installing packages..."
sudo apt-get update
sudo apt-get install -y bluetooth bluez pulseaudio pulseaudio-module-bluetooth python3 python3-dbus python3-gi

echo "Stopping and masking PipeWire..."
systemctl --user stop pipewire pipewire-pulse wireplumber 2>/dev/null || true
systemctl --user mask pipewire pipewire-pulse wireplumber pipewire.socket pipewire-pulse.socket 2>/dev/null || true

echo "Configuring Bluetooth (with discoverability)..."
sudo tee /etc/bluetooth/main.conf > /dev/null << 'EOF'
[General]
Class = 0x200420
DiscoverableTimeout = 0
Discoverable = true
Pairable = yes
PairableTimeout = 0
Name = snap-bridge
Experimental = true

[Policy]
AutoEnable = true
ReconnectAttempts = 7
ReconnectIntervals = 1,2,4,8,16,32,64
EOF

echo "Creating directory..."
sudo mkdir -p /opt/snapcast-bt-bridge/scripts
sudo chown -R pi:pi /opt/snapcast-bt-bridge

echo "Installing auto-pairing agent (fixed D-Bus signatures)..."
cat > /opt/snapcast-bt-bridge/scripts/simple_agent.py << 'AGENTEOF'
#!/usr/bin/env python3
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

class AutoAcceptAgent(dbus.service.Object):
    @dbus.service.method('org.bluez.Agent1', in_signature='os', out_signature='')
    def AuthorizeService(self, device, uuid):
        print(f'AuthorizeService: {device} {uuid}')
        return

    @dbus.service.method('org.bluez.Agent1', in_signature='o', out_signature='')
    def RequestAuthorization(self, device):
        print(f'RequestAuthorization: {device}')
        return

    @dbus.service.method('org.bluez.Agent1', in_signature='o', out_signature='u')
    def RequestPasskey(self, device):
        print(f'RequestPasskey: {device}')
        return dbus.UInt32(0)

    @dbus.service.method('org.bluez.Agent1', in_signature='o', out_signature='s')
    def RequestPinCode(self, device):
        print(f'RequestPinCode: {device}')
        return '0000'

    @dbus.service.method('org.bluez.Agent1', in_signature='ou', out_signature='')
    def RequestConfirmation(self, device, passkey):
        print(f'RequestConfirmation: {device} {passkey}')
        return

    @dbus.service.method('org.bluez.Agent1', in_signature='', out_signature='')
    def Cancel(self):
        print('Cancel')

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
agent = AutoAcceptAgent(bus, '/test/agent')
obj = bus.get_object('org.bluez', '/org/bluez')
manager = dbus.Interface(obj, 'org.bluez.AgentManager1')
manager.RegisterAgent('/test/agent', 'NoInputNoOutput')
manager.RequestDefaultAgent('/test/agent')
print('Agent registered and running...')
GLib.MainLoop().run()
AGENTEOF

chmod +x /opt/snapcast-bt-bridge/scripts/simple_agent.py

echo "Installing streaming script (low latency: 20ms)..."
cat > /opt/snapcast-bt-bridge/scripts/stream_to_snapcast.py << 'STREAMEOF'
#!/usr/bin/env python3
import subprocess
import socket
import time
import logging
import signal
import sys

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class AudioStreamer:
    def __init__(self):
        self.running = True
        self.process = None

    def stream_audio(self):
        command = ['parec', '--format=s16le', '--rate=48000', '--channels=2', '--latency-msec=20', '--device=snapcast_to_bluetooth.monitor']
        
        while self.running:
            try:
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.connect(('192.168.0.30', 4951))
                logger.info("Connected to Snapcast")
                self.process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                
                while self.running:
                    data = self.process.stdout.read(4096)
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
                try:
                    sock.close()
                except:
                    pass

    def cleanup(self):
        self.running = False
        if self.process:
            self.process.terminate()

    def signal_handler(self, signum, frame):
        self.cleanup()
        sys.exit(0)

def main():
    streamer = AudioStreamer()
    signal.signal(signal.SIGINT, streamer.signal_handler)
    signal.signal(signal.SIGTERM, streamer.signal_handler)
    streamer.stream_audio()

if __name__ == "__main__":
    main()
STREAMEOF

chmod +x /opt/snapcast-bt-bridge/scripts/stream_to_snapcast.py

echo "Creating auto-loopback script..."
cat > /opt/snapcast-bt-bridge/scripts/auto_loopback.py << 'LOOPEOF'
#!/usr/bin/env python3
import subprocess
import time

current_loopback_id = None
current_bt_source = None

def get_bluetooth_source():
    try:
        result = subprocess.run(['pactl', 'list', 'sources', 'short'],
                              capture_output=True, text=True)
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
        result = subprocess.run(['pactl', 'list', 'modules', 'short'],
                              capture_output=True, text=True)
        return str(module_id) in result.stdout
    except:
        return False

def create_loopback(bt_source):
    try:
        result = subprocess.run(['pactl', 'load-module', 'module-loopback',
                          f'source={bt_source}', 'sink=snapcast_to_bluetooth'],
                          capture_output=True, text=True)
        if result.returncode == 0:
            module_id = result.stdout.strip()
            print(f"Loopback created: {module_id}")
            return module_id
    except Exception as e:
        print(f"Error: {e}")
    return None

def remove_loopback(module_id):
    if module_id:
        try:
            subprocess.run(['pactl', 'unload-module', str(module_id)])
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
LOOPEOF

chmod +x /opt/snapcast-bt-bridge/scripts/auto_loopback.py

echo "Creating systemd services..."
sudo tee /etc/systemd/system/bt-agent.service > /dev/null << 'EOF'
[Unit]
Description=Bluetooth Auto-Pairing Agent
After=bluetooth.service
Requires=bluetooth.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/snapcast-bt-bridge/scripts/simple_agent.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/snapcast-bt-stream.service > /dev/null << 'EOF'
[Unit]
Description=Bluetooth to Snapcast TCP Streamer
After=network.target pulseaudio.service bluetooth.service
Wants=pulseaudio.service bluetooth.service

[Service]
Type=simple
User=pi
Environment=XDG_RUNTIME_DIR=/run/user/1000
ExecStart=/usr/bin/python3 /opt/snapcast-bt-bridge/scripts/stream_to_snapcast.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/auto-loopback.service > /dev/null << 'EOF'
[Unit]
Description=Auto Bluetooth Loopback Creator
After=pulseaudio.service bluetooth.service
Wants=pulseaudio.service bluetooth.service

[Service]
Type=simple
User=pi
Environment=XDG_RUNTIME_DIR=/run/user/1000
ExecStart=/usr/bin/python3 /opt/snapcast-bt-bridge/scripts/auto_loopback.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "Configuring PulseAudio..."
sudo tee -a /etc/pulse/default.pa > /dev/null << 'EOF'

### Bluetooth modules
load-module module-bluetooth-policy
load-module module-bluetooth-discover autodetect_mtu=yes
load-module module-bluez5-discover autodetect_mtu=yes

### Snapcast sink
load-module module-null-sink sink_name=snapcast_to_bluetooth sink_properties=device.description="Snapcast-to-Bluetooth-Bridge"

### Set default sink to snapcast
set-default-sink snapcast_to_bluetooth
EOF

echo "Setting PulseAudio sample rate to 48000 Hz..."
sudo tee -a /etc/pulse/daemon.conf > /dev/null << 'EOF'
default-sample-rate = 48000
EOF

echo "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable bluetooth
sudo systemctl enable bt-agent
sudo systemctl enable snapcast-bt-stream
sudo systemctl enable auto-loopback

echo ""
echo "============================================"
echo "Installation complete!"
echo "============================================"
echo ""
echo "REBOOT NOW with: sudo reboot"
echo ""
echo "After reboot:"
echo "  1. Pair your phone to 'snap-bridge' (no PIN)"
echo "  2. Play music"
echo "  3. Audio streams to Snapcast server at 192.168.0.30:4951"
echo ""
echo "Check status: systemctl status bt-agent auto-loopback snapcast-bt-stream"
echo ""
