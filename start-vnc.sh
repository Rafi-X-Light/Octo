#!/bin/bash

# Octo VNC + Audio Setup Script
AUDIO_PORT=8000
VNC_PORT=6080
VNC_DISPLAY=":1"
VNC_PASSWORD="${VNC_PASSWORD:-octo2026}"
PULSE_SOCKET="/tmp/octo-pulse/native"
PULSE_SERVER="unix:${PULSE_SOCKET}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cleanup() {
  printf '\n🧹 Cleaning up...\n'
  kill "${AUDIO_PID:-0}" 2>/dev/null || true
  pkill -f "websockify" 2>/dev/null || true
  vncserver -kill :1 >/dev/null 2>&1 || true
  PULSE_SERVER="$PULSE_SERVER" pulseaudio --kill 2>/dev/null || true
}
trap cleanup EXIT

echo "🚀 Starting Octo VNC Desktop + Audio..."
echo ""

# ── 1. Kill everything from previous runs ──────────────────────────────────
echo "🧹 Cleaning up old sessions..."
pkill -f "audio_streamer.py" 2>/dev/null || true
pkill -f "websockify" 2>/dev/null || true
pkill -9 pulseaudio 2>/dev/null || true
vncserver -kill :1 >/dev/null 2>&1 || true
fuser -k 5901/tcp 2>/dev/null || true
fuser -k ${VNC_PORT}/tcp 2>/dev/null || true
fuser -k ${AUDIO_PORT}/tcp 2>/dev/null || true
rm -f /tmp/.X11-unix/X1 /tmp/.X1-lock 2>/dev/null || true
sleep 2

# ── 2. Start ONE PulseAudio with a fixed socket path ──────────────────────
echo "🔊 Starting PulseAudio (fixed socket)..."
mkdir -p /tmp/octo-pulse
PULSE_RUNTIME_PATH=/tmp/octo-pulse \
  pulseaudio --start --exit-idle-time=-1 --daemonize=yes \
  --log-target=file:/tmp/octo-pulse.log 2>/dev/null || true
sleep 2

if ! PULSE_SERVER="$PULSE_SERVER" pactl info >/dev/null 2>&1; then
  echo "❌ PulseAudio failed to start! Log:"
  tail -20 /tmp/octo-pulse.log
  exit 1
fi
echo "✅ PulseAudio running at $PULSE_SOCKET"

# ── 3. Load octo-sink ONCE ────────────────────────────────────────────────
echo "🔊 Loading OctoAudioSink..."
PULSE_SERVER="$PULSE_SERVER" pactl load-module module-null-sink \
  sink_name=octo-sink \
  sink_properties=device.description=OctoAudioSink 2>/dev/null || true
PULSE_SERVER="$PULSE_SERVER" pactl set-default-sink octo-sink 2>/dev/null || true

if PULSE_SERVER="$PULSE_SERVER" pactl list short sources | grep -q "octo-sink.monitor"; then
  echo "✅ octo-sink.monitor ready"
else
  echo "⚠️  octo-sink.monitor not found, audio may not work"
fi

# ── 4. Configure VNC password + xstartup ──────────────────────────────────
echo "🔐 Configuring VNC..."
mkdir -p "$HOME/.vnc"
echo "$VNC_PASSWORD" | vncpasswd -f > "$HOME/.vnc/passwd"
chmod 600 "$HOME/.vnc/passwd"

# xstartup points XFCE at our fixed pulse socket
cat > "$HOME/.vnc/xstartup" <<XEOF
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export PULSE_SERVER="unix:/tmp/octo-pulse/native"
export PULSE_SINK=octo-sink
exec startxfce4
XEOF
chmod +x "$HOME/.vnc/xstartup"
echo "🔑 VNC password: $VNC_PASSWORD"

# ── 5. Start VNC server ────────────────────────────────────────────────────
echo "📺 Starting VNC server..."
vncserver ${VNC_DISPLAY} -geometry 1280x720 -depth 24 -localhost no \
  >/tmp/octo-vnc.log 2>&1 || true
sleep 3
if ! ss -tlnp | grep -q ":5901 "; then
  echo "⚠️  VNC may not have started. Check /tmp/octo-vnc.log"
  tail -10 /tmp/octo-vnc.log
else
  echo "✅ VNC server running on :5901"
fi

# ── 6. Launch Firefox with correct PulseAudio ─────────────────────────────
echo "🦊 Launching Firefox..."
DISPLAY=${VNC_DISPLAY} PULSE_SERVER="$PULSE_SERVER" PULSE_SINK=octo-sink \
  firefox >/dev/null 2>&1 &
sleep 3

# ── 7. Start audio streamer ────────────────────────────────────────────────
echo "🎧 Starting audio streamer on port ${AUDIO_PORT}..."
if [ -f "${SCRIPT_DIR}/audio_streamer.py" ]; then
  PULSE_SERVER="$PULSE_SERVER" PULSE_SINK=octo-sink \
    python3 "${SCRIPT_DIR}/audio_streamer.py" --port "${AUDIO_PORT}" \
    >/tmp/octo-audio.log 2>&1 &
  AUDIO_PID=$!
  sleep 2
  if kill -0 "${AUDIO_PID}" 2>/dev/null; then
    echo "✅ Audio streamer running (PID ${AUDIO_PID})"
  else
    echo "⚠️  Audio streamer failed! Log:"
    tail -10 /tmp/octo-audio.log
  fi
else
  echo "⚠️  audio_streamer.py not found"
  AUDIO_PID=0
fi

# ── 8. Start noVNC ────────────────────────────────────────────────────────
echo "🌐 Starting noVNC on port ${VNC_PORT}..."
websockify --daemon --log-file=/tmp/octo-websockify.log \
  "${VNC_PORT}" localhost:5901 --web=/usr/share/novnc/
sleep 2
if ss -tlnp | grep -q ":${VNC_PORT} "; then
  echo "✅ noVNC listening on port ${VNC_PORT}"
else
  echo "⚠️  noVNC not listening on port ${VNC_PORT}"
fi

# ── 9. Summary ────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "✅ Octo is running!"
echo "  🖥️  VNC desktop  → port ${VNC_PORT}"
echo "  🔊 Audio stream  → port ${AUDIO_PORT}"
echo "  🔑 VNC password  → ${VNC_PASSWORD}"
echo "════════════════════════════════════════"
echo ""
echo "👉 Make sure both ports are set to Public in VS Code Ports tab"
echo "👉 Open the port ${AUDIO_PORT} URL on your phone for audio"
echo "👉 Play a video in Firefox inside VNC — audio will stream to your phone"
echo ""

# Keep running (tunnel or just wait)
echo "🔗 Creating tunnel via localhost.run..."
ssh -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes \
  -R 80:localhost:${VNC_PORT} \
  -R 8000:localhost:${AUDIO_PORT} \
  nokey@localhost.run
