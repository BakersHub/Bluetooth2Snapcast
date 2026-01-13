# Bluetooth to Snapcast Bridge (Raspberry Pi & Ubuntu Linux)

## 🎯 Project Objective - Fully Automatic Setup

**One-time setup, zero maintenance Bluetooth audio bridge**

### Quick Start (Raspberry Pi)
1. **Flash fresh Raspberry Pi OS Lite 32-bit**
2. **Run**: `scp Installer.sh pi@192.168.0.233:~/ && ssh pi@192.168.0.233 "chmod +x Installer.sh && ./Installer.sh"`
3. **Reboot** with `sudo reboot`
4. **That's it!**

### Quick Start (Ubuntu Linux)
1. **On Ubuntu system**: `./scripts/universal-setup.sh`
2. **Run scripts manually** in separate terminals:
   - `python3 /opt/snapcast-bt-bridge/scripts/auto_loopback.py &`
   - `python3 /opt/snapcast-bt-bridge/scripts/stream_to_snapcast.py &`
3. **That's it!**

### How It Works (Fully Automatic)
- ✅ **Plug in Pi** → boots up and ready
- ✅ **Pair phone once** → auto-connects every time after
- ✅ **Play music** → automatically routes to Snapcast server
- ✅ **No manual commands** ever needed

The `auto-loopback` service constantly monitors for Bluetooth connections and creates the audio routing automatically. Your phone becomes a wireless audio source for your entire Snapcast multi-room audio system.

---

## Overview

This project turns a Raspberry Pi or Ubuntu Linux system into a Bluetooth A2DP receiver that forwards audio to your Snapcast server.

**Audio Flow:**
```
Android Phone → Bluetooth A2DP → Raspberry Pi/Ubuntu → TCP Stream → Snapcast Server → All Speakers
```

**Configuration:**
- **Device**: Acts as Bluetooth audio receiver (A2DP sink)
- **Snapcast Server**: `192.168.0.30:4951` (configure in `Installer.sh` or `stream_to_snapcast.py`)
- **Audio Format**: 48kHz, 16-bit, stereo
- **Pairing**: Automatic (Pi) or manual (Ubuntu), no PIN required

## Architecture

```
Phone (Bluetooth Source)
    ↓ A2DP (aptX/SBC codec)
Raspberry Pi/Ubuntu (PulseAudio + BlueZ)
    ↓ TCP Stream (s16le, 48kHz, 2ch)
Snapcast Server (192.168.0.30:4951)
    ↓ Snapcast Protocol
All Connected Speakers
```

## Requirements

### Hardware
- Raspberry Pi 3B+ or newer (with built-in Bluetooth) **OR** Ubuntu Linux system with Bluetooth adapter
- Android phone or Bluetooth audio source
- Network connection to Snapcast server

### Software
- **Raspberry Pi**: Raspberry Pi OS Lite 32-bit (fresh install) - automatically installs: bluetooth, bluez, pulseaudio, python3
- **Ubuntu Linux**: Ubuntu 20.04+ with PulseAudio - automatically installs: bluetooth, bluez, pulseaudio, python3

## Installation (Raspberry Pi - Automated)

Run the `Installer.sh` script on a freshly flashed Raspberry Pi:

```bash
# From your computer
scp Installer.sh pi@192.168.0.233:~/ && ssh pi@192.168.0.233 "chmod +x Installer.sh && ./Installer.sh"
```

The script automatically:
- Installs all required packages
- Disables PipeWire (uses PulseAudio instead)
- Configures Bluetooth as A2DP receiver
- Sets up automatic pairing (no PIN)
- Creates auto-loopback service
- Starts streaming to Snapcast server

**Configuration**: Edit the Snapcast server IP in the script before running (default: 192.168.0.30:4951)

**Important**: Reboot after installation with `sudo reboot`

## Installation (Ubuntu Linux - Universal Setup)

Run the `scripts/universal-setup.sh` script on your Ubuntu system:

```bash
./scripts/universal-setup.sh
```

The script automatically detects your audio setup (PulseAudio or PipeWire) and:
- Creates the Snapcast null sink (`snapcast_to_bluetooth`)
- Sets it as the default sink
- Loads Bluetooth modules (if PulseAudio with Bluetooth support)
- Prepares for manual script operation

**Manual pairing**: Use `bluetoothctl` to pair your device:
```bash
bluetoothctl
power on
scan on
pair <MAC_ADDRESS>
trust <MAC_ADDRESS>
connect <MAC_ADDRESS>
```

**Manual operation**: Run the scripts in separate terminals:
- `python3 /opt/snapcast-bt-bridge/scripts/auto_loopback.py &` (monitors Bluetooth connections)
- `python3 /opt/snapcast-bt-bridge/scripts/stream_to_snapcast.py &` (streams audio to Snapcast)

**Configuration**: Edit the Snapcast server IP in `stream_to_snapcast.py` (default: 192.168.0.30:4951)

## Snapcast Server Setup

Your Snapcast server must have this source configured:

```ini
[stream]
source = tcp://0.0.0.0:4951?name=BLUETOOTH&sampleformat=48000:16:2&mode=server
```

This makes the server listen for incoming TCP connections from the Raspberry Pi or Ubuntu system.

## Usage

### Raspberry Pi - Automatic Operation

#### First Time Setup
1. Flash Raspberry Pi OS Lite 32-bit
2. Run `Installer.sh` (see Installation above)
3. Wait for setup to complete (~5-10 minutes)
4. Reboot with `sudo reboot`
5. On your phone: Go to Bluetooth settings
6. Find and pair with the Bluetooth device (no PIN needed)
7. Play music on your phone

#### Daily Use
1. Power on Raspberry Pi (automatic startup)
2. Phone auto-connects when in range
3. Play music → automatically streams to all Snapcast speakers
4. That's it!

#### Services Running
- `bt-agent.service` - Automatic Bluetooth pairing
- `auto-loopback.service` - Automatic audio routing
- `snapcast-bt-stream.service` - TCP streaming to Snapcast server

Check status:
```bash
sudo systemctl status bt-agent auto-loopback snapcast-bt-stream
```

### Ubuntu Linux - Manual Operation

#### First Time Setup
1. Run `scripts/universal-setup.sh` (see Installation above)
2. Pair your Bluetooth device using `bluetoothctl` (see Installation above)
3. Open two terminals:
   - Terminal 1: `python3 /opt/snapcast-bt-bridge/scripts/auto_loopback.py &`
   - Terminal 2: `python3 /opt/snapcast-bt-bridge/scripts/stream_to_snapcast.py &`
4. Play music on your phone

#### Daily Use
1. Run the two Python scripts in separate terminals when needed
2. Phone auto-connects when in range (if previously paired)
3. Play music → streams to all Snapcast speakers
4. Close terminals when done

#### Scripts Running
- `auto_loopback.py` - Monitors Bluetooth connections and sets up audio routing
- `stream_to_snapcast.py` - Streams audio to Snapcast server

## Troubleshooting

### Phone won't pair
```bash
ssh pi@192.168.0.233
sudo systemctl restart bt-agent bluetooth
bluetoothctl discoverable on
```

### No audio streaming
```bash
# Check if Bluetooth source is detected
ssh pi@192.168.0.233 "pactl list sources short | grep bluez"

# Restart auto-loopback service
ssh pi@192.168.0.233 "sudo systemctl restart auto-loopback"
```

### Check logs
```bash
# Auto-loopback service
sudo journalctl -u auto-loopback -f

# Streaming service  
sudo journalctl -u snapcast-bt-stream -f

# Bluetooth pairing
sudo journalctl -u bt-agent -f
```

### Full restart
```bash
ssh pi@192.168.0.233
sudo systemctl restart bluetooth bt-agent auto-loopback snapcast-bt-stream
```

## Files

### Main Installation
- `Installer.sh` - **Raspberry Pi automated setup script**
- `scripts/universal-setup.sh` - **Universal setup for Linux systems**

### Working Configuration (from October 23, 2025)
- `configs/bluetooth/main.conf` - Bluetooth A2DP receiver configuration
- `configs/pulseaudio/system.pa` - PulseAudio Bluetooth modules
- `scripts/simple_agent.py` - Auto-pairing agent (no PIN)
- `scripts/stream_to_snapcast.py` - TCP audio streamer
- `scripts/auto_loopback.py` - Automatic audio routing
- `systemd/*.service` - Service files for automatic startup

### Documentation
- `SETUP_COMPLETE.md` - Technical documentation of working system
- `QUICK_START.md` - Daily usage guide
- `REFLASH_GUIDE.md` - Step-by-step reflash instructions
- `PROJECT_COMPLETE.md` - Complete project overview

### Legacy Files
- `install.sh` - Original installation script (deprecated)
- `fresh-install.sh` - Previous Raspberry Pi script (replaced by Installer.sh)
- `make-it-work.sh` - Simplified version (use Installer.sh instead)

## Technical Details

### Audio Pipeline
1. **Bluetooth A2DP**: Phone connects as audio source
2. **PulseAudio**: Receives Bluetooth audio via bluez5 modules
3. **module-loopback**: Routes `bluez_source` → `snapcast_to_bluetooth` sink
4. **parec**: Captures from `snapcast_to_bluetooth.monitor`
5. **TCP Stream**: Sends s16le/48kHz/2ch to Snapcast server
6. **Snapcast**: Distributes to all connected clients/speakers

### Key Components
- **PulseAudio** (not PipeWire - PipeWire is disabled)
- **BlueZ 5.82+** for Bluetooth stack
- **Python D-Bus** for automatic pairing
- **systemd** for service management

### Why PulseAudio instead of PipeWire?
PipeWire's Bluetooth A2DP sink support is incomplete on Raspberry Pi. PulseAudio has mature, stable Bluetooth modules that properly handle A2DP receiver mode.

## Success Indicators

✅ **Raspberry Pi**: Device boots and services start automatically  
✅ **Ubuntu**: Scripts run without errors in terminals  
✅ Phone pairs without PIN prompt  
✅ `pactl list sources short` shows `bluez_source...RUNNING`  
✅ `pactl list sinks short` shows `snapcast_to_bluetooth...RUNNING`  
✅ Music plays through all Snapcast speakers  
✅ Auto-reconnects when phone comes back in range

## License

MIT License - See LICENSE file for details.

## Credits

Tested and working configuration as of October 23, 2025  
**Raspberry Pi**: Raspberry Pi OS Lite 32-bit (Debian Bookworm/Trixie)  
**Ubuntu Linux**: Ubuntu 20.04+ with PulseAudio  
PulseAudio 17.0, BlueZ 5.82, Python 3.13