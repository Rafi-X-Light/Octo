#!/bin/bash

# VNC + Browser Audio Setup Script
AUDIO_PORT=8000
VNC_PORT=6080
VNC_DISPLAY=":1"
VNC_PASSWORD="${VNC_PASSWORD:-octo2026}"

cleanup() {
  printf '\n🧹 Cleaning up...\n'
  kill "${AUDIO_PID:-0}" 2>/dev/null || true
  pkill -f "websockify" 2>/dev/null || true
  vncserver -kill :1 >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "🚀 Starting VNC Desktop + Audio Stream..."
echo ""

# Clean up old sessions
echo "Cleaning up old VNC sessions..."
vncserver -kill :1 >/dev/null 2>&1 || true
pkill -f "websockify" >/dev/null 2>&1 || true
pkill -f "audio_streamer.py" >/dev/null 2>&1 || true
fuser -k 5901/tcp 2>/dev/null || true
fuser -k ${VNC_PORT}/tcp 2>/dev/null || true
rm -f /tmp/.X11-unix/X1 /tmp/.X1-lock 2>/dev/null || true
sleep 2

# Configure VNC password
echo "🔐 Configuring VNC password..."
mkdir -p "$HOME/.vnc"
echo "$VNC_PASSWORD" | vncpasswd -f > "$HOME/.vnc/passwd"
chmod 600 "$HOME/.vnc/passwd"
echo "🔑 VNC password set to '$VNC_PASSWORD' (override with VNC_PASSWORD=...)"

# Start PulseAudio
echo "🔊 Starting PulseAudio..."
if command -v pulseaudio >/dev/null 2>&1; then
  if ! pulseaudio --check >/dev/null 2>&1; then
    pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1 || true
    sleep 1
  fi
  if ! pactl info >/dev/null 2>&1; then
    echo "⚠️  PulseAudio did not start properly. Audio may not work."
  fi
  echo "🔊 Loading virtual audio sink..."
  pactl load-module module-null-sink sink_name=octo-sink sink_properties=device.description=OctoAudioSink 2>/dev/null || true
  pactl set-default-sink octo-sink 2>/dev/null || true
  if ! pactl list short sources | grep -q "octo-sink.monitor"; then
    echo "⚠️  Virtual audio sink monitor not found. Audio may not work."
  else
    echo "✅ Virtual audio sink loaded: octo-sink.monitor"
  fi
else
  echo "❌ pulseaudio is not installed. Install it for sound support."
fi

# Start VNC server
echo "📺 Starting VNC server on port 5901..."
vncserver ${VNC_DISPLAY} -geometry 1280x720 -depth 24 -localhost no >/tmp/octo-vnc.log 2>&1 || true
sleep 3
if ! ss -tlnp | grep -q ":5901 "; then
  echo "⚠️  VNC server may not have started. Check /tmp/octo-vnc.log"
  tail -10 /tmp/octo-vnc.log
fi

# Start desktop environment
echo "🖥️  Starting XFCE4 desktop..."
DISPLAY=${VNC_DISPLAY} startxfce4 >/dev/null 2>&1 &
sleep 4

# Start audio streamer
echo "🎧 Starting audio stream on port ${AUDIO_PORT}..."
export PULSE_SINK=octo-sink
if [ -f "$(pwd)/audio_streamer.py" ]; then
  python3 "$(pwd)/audio_streamer.py" --port "${AUDIO_PORT}" >/tmp/octo-audio.log 2>&1 &
  AUDIO_PID=$!
  sleep 2
  if ! kill -0 "${AUDIO_PID}" 2>/dev/null; then
    echo "⚠️  Audio streamer failed to start. Check /tmp/octo-audio.log"
    tail -10 /tmp/octo-audio.log
  else
    echo "✅ Audio streamer running (PID ${AUDIO_PID})"
  fi
else
  echo "⚠️  audio_streamer.py not found, skipping audio."
  AUDIO_PID=0
fi

# Start noVNC
echo "🌐 Starting noVNC on port ${VNC_PORT}..."
websockify --daemon --log-file=/tmp/octo-websockify.log "${VNC_PORT}" localhost:5901 --web=/usr/share/novnc/
sleep 2
if ! ss -tlnp | grep -q ":${VNC_PORT} "; then
  echo "⚠️  noVNC/websockify may not be listening on port ${VNC_PORT}"
else
  echo "✅ noVNC listening on port ${VNC_PORT}"
fi

# Create a public tunnel via localhost.run
echo "🔗 Creating public tunnel via localhost.run..."
echo ""
ssh -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes -R 80:localhost:${VNC_PORT} -R 8000:localhost:${AUDIO_PORT} nokey@localhost.run

echo ""
echo "✅ Setup complete!"
echo "Your VNC desktop is available via the remote link shown above."
echo "Open http://<remote-host>:8000/ for the audio stream."
echo "If audio is silent, make sure Firefox inside the remote desktop is playing sound."
