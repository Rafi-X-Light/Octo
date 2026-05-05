#!/usr/bin/env python3
import argparse
import glob
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

AUDIO_PAGE = """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Octo VNC Audio Stream</title>
  <style>
    body { font-family: system-ui, sans-serif; padding: 1.5rem; background: #0f172a; color: #e2e8f0; }
    .card { background: #111827; border-radius: 1rem; padding: 1.25rem; box-shadow: 0 8px 30px rgba(15,23,42,.35); max-width: 600px; margin: 2rem auto; }
    h1 { margin-top: 0; }
    audio { width: 100%; }
    .status { padding: 0.5rem; border-radius: 0.5rem; margin: 1rem 0; }
    .ok { background: #065f46; color: #d1fae5; }
    .err { background: #991b1b; color: #fee2e2; }
  </style>
</head>
<body>
  <div class="card">
    <h1>🔊 Octo VNC Audio</h1>
    <p>Audio is streamed from the VNC desktop session.</p>
    <div id="status" class="status err">⚠️ Connecting to audio stream...</div>
    <audio id="audio" controls preload="auto" autoplay>
      <source src="/stream" type="audio/webm; codecs=opus">
      Your browser does not support the audio stream.
    </audio>
    <p style="font-size:0.85rem;opacity:0.7">If silent: open VNC desktop, play audio there, and select <b>OctoAudioSink</b> as output device.</p>
  </div>
  <script>
    const audio = document.getElementById('audio');
    const status = document.getElementById('status');
    let retryCount = 0;
    function tryPlay() {
      audio.play().then(() => {
        status.className = 'status ok';
        status.textContent = '✅ Audio connected and playing';
        retryCount = 0;
      }).catch((e) => {
        status.className = 'status err';
        if (retryCount < 3) {
          retryCount++;
          status.textContent = '⚠️ Click play to start audio (browser autoplay blocked)';
        } else {
          status.textContent = '❌ Audio stream error - is the server running?';
        }
      });
    }
    audio.addEventListener('canplay', tryPlay);
    audio.addEventListener('error', () => {
      status.className = 'status err';
      status.textContent = '❌ Audio stream error - is the server running?';
    });
    // Force reload stream on error
    audio.addEventListener('stalled', () => {
      setTimeout(() => {
        audio.load();
      }, 2000);
    });
  </script>
</body>
</html>
"""

def find_pulse_socket():
    # First priority: Our fixed Octo PulseAudio socket
    octo_socket = "/tmp/octo-pulse/native"
    if os.path.exists(octo_socket):
        return f"unix:{octo_socket}"
    # Second priority: Environment variable
    if os.environ.get("PULSE_SERVER"):
        return os.environ["PULSE_SERVER"]
    # Third priority: Standard XDG runtime path
    uid = os.getuid()
    xdg = f"/run/user/{uid}/pulse/native"
    if os.path.exists(xdg):
        return f"unix:{xdg}"
    # Fallback: Any other PulseAudio socket
    matches = glob.glob("/tmp/pulse-*/native")
    if matches:
        return f"unix:{matches[0]}"
    return None

def pactl(*args, pulse_server=None):
    env = os.environ.copy()
    if pulse_server:
        env["PULSE_SERVER"] = pulse_server
    return subprocess.check_output(["pactl"] + list(args), text=True, env=env)

def find_monitor_source(pulse_server=None):
    try:
        info = pactl("info", pulse_server=pulse_server)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError("PulseAudio is not running") from exc
    sources = pactl("list", "short", "sources", pulse_server=pulse_server).splitlines()
    monitor_candidates = [l.split("\t")[1] for l in sources if len(l.split("\t")) > 1 and l.split("\t")[1].endswith(".monitor")]
    if "octo-sink.monitor" in monitor_candidates:
        return "octo-sink.monitor"
    for line in info.splitlines():
        if line.startswith("Default Sink:"):
            sink = line.split(":", 1)[1].strip()
            exact = f"{sink}.monitor"
            if exact in monitor_candidates:
                return exact
    if monitor_candidates:
        return monitor_candidates[0]
    raise RuntimeError("No PulseAudio monitor source found")

class AudioHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
            self.end_headers()
            self.wfile.write(AUDIO_PAGE.encode("utf-8"))
            return
        if self.path == "/stream":
            self.send_response(200)
            self.send_header("Content-Type", "audio/webm; codecs=opus")
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            self.stream_audio()
            return
        self.send_error(404, "Not Found")

    def stream_audio(self):
        env = os.environ.copy()
        if self.server.pulse_server:
            env["PULSE_SERVER"] = self.server.pulse_server
        
        # Use WebM container with Opus - browsers handle this much better for live streaming
        cmd = [
            "ffmpeg", "-hide_banner", "-loglevel", "error",
            "-fflags", "nobuffer", "-flags", "low_delay",
            "-f", "pulse", "-fragment_size", "256",
            "-i", self.server.monitor_source,
            "-ac", "2", "-ar", "48000",
            "-c:a", "libopus", "-b:a", "128k",
            "-frame_duration", "10", "-application", "audio",
            "-f", "webm",
            "pipe:1",
        ]
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        except FileNotFoundError:
            self.send_error(500, "ffmpeg not found")
            return
        try:
            while True:
                chunk = proc.stdout.read(4096)
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    break
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()

    def log_message(self, format, *args):
        return

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    pulse_server = find_pulse_socket()
    if pulse_server:
        os.environ["PULSE_SERVER"] = pulse_server
        print(f"PulseAudio socket: {pulse_server}")
    else:
        print("WARNING: PulseAudio socket not found", file=sys.stderr)

    monitor_source = os.environ.get("PULSE_SOURCE") or find_monitor_source(pulse_server)
    print(f"Monitor source: {monitor_source}")

    class CustomServer(ThreadingHTTPServer):
        pass

    server = CustomServer(("0.0.0.0", args.port), AudioHandler)
    server.monitor_source = monitor_source
    server.pulse_server = pulse_server
    print(f"Starting audio stream on http://0.0.0.0:{args.port}/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
