#!/usr/bin/env bash
set -euo pipefail

TMP_LOG_DIR="/tmp/octo-rdp"
mkdir -p "$TMP_LOG_DIR"
PLAYIT_BIN="./playit"
BORE_BIN="./bore"

log() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $*"
}

start_xrdp() {
  log "🚀 Starting RDP with Audio Support..."

  sudo pkill -9 xrdp 2>/dev/null || true
  sudo pkill -9 xrdp-sesman 2>/dev/null || true
  sudo rm -f /var/run/xrdp/*.pid 2>/dev/null || true
  sleep 2

  sudo sed -i 's/port=3390/port=3389/' /etc/xrdp/xrdp.ini || true
  sudo sed -i 's/rdpsnd=false/rdpsnd=true/' /etc/xrdp/xrdp.ini || true

  if ! pulseaudio --check >/dev/null 2>&1; then
    log "Starting PulseAudio..."
    pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1 || true
    sleep 1
  fi

  if ! pgrep -x "xfce4-session" >/dev/null 2>&1; then
    log "Starting XFCE desktop..."
    DISPLAY=:10 startxfce4 >/dev/null 2>&1 &
    sleep 3
  fi

  log "Starting xrdp services..."
  sudo service xrdp-sesman start >/dev/null 2>&1 || sudo /usr/sbin/xrdp-sesman >/dev/null 2>&1 || true
  sleep 1
  sudo service xrdp start >/dev/null 2>&1 || sudo /usr/sbin/xrdp >/dev/null 2>&1 || true
  sleep 2

  if pgrep -x "xrdp" >/dev/null 2>&1; then
    log "✅ xrdp is running on port 3389"
    ss -tlnp | grep 3389 || true
  else
    log "❌ Failed to start xrdp"
    exit 1
  fi
}

start_playit_agent() {
  if ! [[ -x "$PLAYIT_BIN" ]]; then
    return 1
  fi

  if ! pgrep -f "playit start" >/dev/null 2>&1; then
    log "Starting playit agent..."
    setsid "$PLAYIT_BIN" start > "$TMP_LOG_DIR/playit.log" 2>&1 < /dev/null &
    sleep 8
  fi

  if ! pgrep -f "playit start" >/dev/null 2>&1; then
    log "⚠️ playit agent did not start correctly."
    return 1
  fi

  log "Preparing playit TCP tunnel for RDP..."
  if "$PLAYIT_BIN" tunnels prepare tcp 1 --name octo-rdp > "$TMP_LOG_DIR/playit-prepare.log" 2>&1; then
    log "✅ playit tunnel created. See $TMP_LOG_DIR/playit-prepare.log for details."
    return 0
  fi

  log "⚠️ playit tunnel creation failed; see $TMP_LOG_DIR/playit-prepare.log"
  return 1
}

start_bore_tunnel() {
  if ! [[ -x "$BORE_BIN" ]]; then
    log "❌ bore not found, downloading..."
    cd /tmp
    curl -sL https://github.com/ekzhang/bore/releases/download/v0.5.1/bore-v0.5.1-x86_64-unknown-linux-musl.tar.gz -o bore.tar.gz
    tar -xzf bore.tar.gz
    cp /tmp/bore-v0.5.1-x86_64-unknown-linux-musl/bore "$BORE_BIN"
    chmod +x "$BORE_BIN"
  fi

  log "Starting bore tunnel for external RDP access..."
  setsid "$BORE_BIN" local 3389 --to bore.pub > "$TMP_LOG_DIR/bore.log" 2>&1 < /dev/null &
  sleep 3
  log "✅ bore tunnel launched in background. Check $TMP_LOG_DIR/bore.log for the external address."
}

start_xrdp

echo ""
echo "========================================="
echo "RDP Connection Details:"
echo "  Host: localhost:3389"
echo "  Port: 3389"
echo "  Username: root"
echo "  Password: (your system password)"
echo "========================================="
echo ""
echo "🔊 Audio support enabled via PipeWire-xrdp"
echo "   Make sure to select xrdp-sink as audio output in your RDP client"
echo ""

if start_playit_agent; then
  echo "🔗 playit proxy tunnel is active. Check $TMP_LOG_DIR/playit-prepare.log for the public address."
else
  echo "🔗 Falling back to bore tunnel for external access."
  start_bore_tunnel
fi
