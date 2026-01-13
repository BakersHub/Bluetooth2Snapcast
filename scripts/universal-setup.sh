#!/bin/bash
# Universal Snapcast Bluetooth Bridge Setup
# Works on Raspberry Pi (PulseAudio) and Linux desktops (PulseAudio/PipeWire)

set -e

# Configurable BT sink name
BT_SINK="${BT_SINK:-snapcast_to_bluetooth}"

echo "=== Universal Snapcast BT Bridge Setup ==="

# Detect audio server
if pactl info >/dev/null 2>&1; then
    # PulseAudio server running
    if pactl list short modules | grep -q bluez5; then
        AUDIO_TYPE="pulse-bt"       # PulseAudio with Bluetooth modules
    else
        AUDIO_TYPE="pulse-no-bt"    # PulseAudio, but no BT modules (desktop)
    fi
elif command -v pw-cli >/dev/null 2>&1; then
    AUDIO_TYPE="pipewire"           # PipeWire (modern desktop)
else
    echo "❌ No supported audio server detected (PulseAudio or PipeWire required)."
    exit 1
fi

echo "Detected audio setup: $AUDIO_TYPE"

# Create Snapcast null sink if it doesn't exist
if pactl list short sinks | grep -q "$BT_SINK"; then
    echo "Sink '$BT_SINK' already exists."
else
    echo "Creating null sink '$BT_SINK'..."
    pactl load-module module-null-sink \
        sink_name="$BT_SINK" \
        sink_properties=device.description="Snapcast-to-Bluetooth-Bridge"
fi

# Set default sink
echo "Setting default sink to '$BT_SINK'..."
pactl set-default-sink "$BT_SINK"

# Only load PulseAudio BT modules if they exist (Pi)
if [ "$AUDIO_TYPE" = "pulse-bt" ]; then
    echo "Loading PulseAudio Bluetooth modules..."
    pactl load-module module-bluetooth-policy || true
    pactl load-module module-bluez5-discover || true
fi

echo "✅ Setup complete!"
echo ""
echo "You can now run your bridge scripts:"
echo "  python3 /opt/snapcast-bt-bridge/scripts/auto_loopback.py &"
echo "  python3 /opt/snapcast-bt-bridge/scripts/stream_to_snapcast.py &"
echo ""
echo "If running on PipeWire, Bluetooth sources are handled automatically."
