# 🚀 QUICK DEPLOYMENT GUIDE

## Tested Working Configuration - October 24, 2025

---

## Method 1: Fresh Install (Recommended)

### Prerequisites
- Raspberry Pi 3B+ or newer
- Fresh Raspberry Pi OS Lite 32-bit SD card
- SSH enabled
- Network connection (WiFi or Ethernet)

### Steps

1. **Flash SD card** with Raspberry Pi OS Lite 32-bit

2. **Enable SSH**: Create empty file named `ssh` in boot partition

3. **Boot Pi** and find IP address

4. **Deploy**:
```bash
# Copy installation script
scp Installer.sh pi@<PI_IP>:~/

# Run it
ssh pi@<PI_IP> "chmod +x Installer.sh && ./Installer.sh"

# Reboot
ssh pi@<PI_IP> "sudo reboot"
```

5. **Done!** Wait 60 seconds, then pair your phone to "snap-bridge"

---

## Method 2: Restore from Backup

If you have the working config backup:

```bash
# Copy backup to Pi
scp snapcast-bt-working-config.tar.gz pi@<PI_IP>:~/

# Extract and restore
ssh pi@<PI_IP> "sudo tar xzf snapcast-bt-working-config.tar.gz -C /"

# Enable services
ssh pi@<PI_IP> "sudo systemctl daemon-reload && sudo systemctl enable bt-agent auto-loopback snapcast-bt-stream bluetooth"

# Reboot
ssh pi@<PI_IP> "sudo reboot"
```

---

## Snapcast Server Configuration

Add this to your Snapcast server config at **192.168.0.30**:

```yaml
streams: |
  source=tcp://0.0.0.0:4951?name=BLUETOOTH&sampleformat=48000:16:2&mode=server
buffer: 1000
codec: flac
```

**Important:** Update the IP in `Installer.sh` if your server is not at 192.168.0.30:
```python
sock.connect(('192.168.0.30', 4951))  # Change this IP
```

---

## Verification

### Check Services
```bash
ssh pi@<PI_IP> "systemctl status bt-agent auto-loopback snapcast-bt-stream"
```

All should show **active (running)** in green.

### Check Audio
```bash
ssh pi@<PI_IP> "pactl list sources short && echo '---' && pactl list sinks short"
```

You should see:
- `snapcast_to_bluetooth` sink
- `bluez_source.XX_XX_XX_XX_XX_XX.a2dp_source` (when phone connected)

### Check Bluetooth
```bash
ssh pi@<PI_IP> "bluetoothctl show"
```

Should show:
- `Discoverable: yes`
- `Powered: yes`

---

## Usage

### First Time
1. Power on Pi (wait 60 seconds for boot)
2. Open Bluetooth on your phone
3. Scan for devices
4. Tap "snap-bridge"
5. Connects automatically (no PIN)
6. Play music

### Daily Use
1. Phone auto-connects when in range
2. Play music
3. Audio automatically streams to all Snapcast speakers

---

## Troubleshooting

### Can't find "snap-bridge" in Bluetooth scan
```bash
ssh pi@<PI_IP> "sudo bluetoothctl discoverable on"
```

### Paired but no audio
```bash
# Check audio routing
ssh pi@<PI_IP> "pactl list sink-inputs"

# If loopback is on wrong sink:
ssh pi@<PI_IP> "pactl move-sink-input <ID> snapcast_to_bluetooth"
```

### Audio stops after pause/resume
This should be fixed with `set-default-sink`. If it still happens:
```bash
ssh pi@<PI_IP> "pactl set-default-sink snapcast_to_bluetooth"
```

### PipeWire started instead of PulseAudio
```bash
ssh pi@<PI_IP> "systemctl --user stop pipewire pipewire-pulse wireplumber"
ssh pi@<PI_IP> "pulseaudio --start"
```

---

## Performance

- **Pairing:** Instant (no PIN)
- **Connection:** 2-3 seconds
- **Latency:** ~3 seconds (music only, not for video)
- **Codec:** aptX (high quality)
- **CPU:** ~5% on Pi 3B+
- **Audio:** 48kHz, 16-bit, stereo

---

## Files Reference

| File | Purpose |
|------|---------|
| `Installer.sh` | **Use this!** Complete automated installer |
| `WORKING_CONFIG_BACKUP.md` | Detailed technical documentation |
| `snapcast-bt-working-config.tar.gz` | Backup of working Pi config |
| `DEPLOY.md` | This file - quick deployment guide |

---

## Network Setup

**Pi IP addresses (tested):**
- Ethernet: 192.168.0.232
- WiFi: 192.168.0.233

**Snapcast Server:** 192.168.0.30:4951

**Phone MAC:** 50:50:A4:26:07:CB (Dylan's S20 Ultra)

---

## What Gets Installed

- **Packages:** bluetooth, bluez, pulseaudio, pulseaudio-module-bluetooth, python3, python3-dbus, python3-gi
- **Services:** bt-agent, auto-loopback, snapcast-bt-stream
- **Audio:** PulseAudio (PipeWire disabled)
- **Scripts:** Auto-pairing agent, TCP streamer, audio router

---

## Customization

### Change Bluetooth Name
Edit in `Installer.sh`:
```bash
Name = snap-bridge  # Change this
```

### Change Snapcast Server IP
Edit in `Installer.sh`:
```python
sock.connect(('192.168.0.30', 4951))  # Change IP here
```

### Adjust Latency
Edit in `Installer.sh`:
```python
'--latency-msec=20'  # Lower = less latency, more dropouts
```

---

## Success Checklist

- [ ] Fresh Pi boots and accessible via SSH
- [ ] `Installer.sh` runs without errors
- [ ] Pi reboots successfully
- [ ] "snap-bridge" appears in Bluetooth scan
- [ ] Phone pairs without PIN
- [ ] Audio plays through Snapcast speakers
- [ ] Survives power cycle and reconnection

---

**Last Updated:** October 24, 2025  
**Version:** 2.0  
**Status:** ✅ Production Ready
