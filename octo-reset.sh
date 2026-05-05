#!/bin/bash
echo "=== Octo Audio Reset ==="

# 1. Kill everything
echo "Killing old processes..."
pkill -f audio_streamer.py 2>/dev/null || true
pkill -9 pulseaudio 2>/dev/null || true
sleep 2

# 2. Start ONE PulseAudio with fixed socket
echo "Starting PulseAudio..."
mkdir -p /tmp/octo-pulse
PULSE_RUNTIME_PATH=/tmp/octo-pulse \
  pulseaudio --start --exit-idle-time=-1 --daemonize=yes \
  --log-target=file:/tmp/octo-pulse.log
sleep 2

export PULSE_SERVER=unix:/tmp/octo-pulse/native

# 3. Verify it's running
if ! pactl info > /dev/null 2>&1; then
  echo "ERROR: PulseAudio failed to start!"
  cat /tmp/octo-pulse.log
  exit 1
fi
echo "PulseAudio running at $PULSE_SERVER"

# 4. Load octo-sink ONCE
pactl load-module module-null-sink \
  sink_name=octo-sink \
  sink_properties=device.description=OctoAudioSink
pactl set-default-sink octo-sink
echo "octo-sink loaded. Sinks:"
pactl list short sinks

# 5. Write env file so all apps can source it
echo "export PULSE_SERVER=unix:/tmp/octo-pulse/native" > /tmp/octo-env.sh
echo "export PULSE_SINK=octo-sink" >> /tmp/octo-env.sh

# 6. Restart Firefox with correct PulseAudio
echo "Restarting Firefox..."
DISPLAY=:1 pkill firefox 2>/dev/null || true
sleep 1
DISPLAY=:1 PULSE_SERVER=unix:/tmp/octo-pulse/native firefox &

# 7. Start audio streamer
echo "Starting audio streamer..."
PULSE_SERVER=unix:/tmp/octo-pulse/native \
  python3 /workspaces/Octo/audio_streamer.py --port 8000 &
sleep 2

echo ""
echo "=== Done! ==="
echo "Open https://r4xpvwhppx4-8000.app.github.dev on your phone"
echo "Play a YouTube video in Firefox inside VNC"
echo "Check sink-inputs:"
pactl list short sink-inputs
