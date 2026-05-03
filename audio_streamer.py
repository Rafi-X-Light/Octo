#!/usr/bin/env python3
import argparse
import html
import os
import socketserver
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
    a, button { color: #7dd3fc; }
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
    <audio id="audio" controls preload="none">
      <source src="/stream" type="audio/ogg; codecs=opus">
      Your browser does not support the audio stream.
    </audio>
    <p style="font-size:0.85rem;opacity:0.7">If silent: open VNC desktop, play audio there, ensure volume is up, and select <b>OctoAudioSink</b> as output device.</p>
  </div>
  <script>
    const audio = document.getElementById('audio');
    const status = document.getElementById('status');
    function tryPlay() {
      audio.play().then(() => {
        status.className = 'status ok';
        status.textContent = '✅ Audio connected and playing';
      }).catch(() => {
        status.className = 'status err';
        status.textContent = '⚠️ Click play to start audio (browser autoplay blocked)';
      });
    }
    audio.addEventListener('canplay', tryPlay);
    audio.addEventListener('error', () => {
      status.className = 'status err';
      status.textContent = '❌ Audio stream error - is the server running?';
    });
  </script>
</body>
</html>
"""

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
            self.send_header("Content-Type", "audio/ogg")
            self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
            self.end_headers()
            self.stream_audio()
            return

        self.send_error(404, "Not Found")

    def stream_audio(self):
        monitor_source = self.server.monitor_source
        cmd = [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "warning",
            "-f",
            "pulse",
            "-i",
            monitor_source,
            "-ac",
            "2",
            "-ar",
            "48000",
            "-c:a",
            "libopus",
            "-b:a",
            "96k",
            "-f",
            "ogg",
            "pipe:1",
        ]

        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            return

        assert proc.stdout is not None
        try:
            while True:
                chunk = proc.stdout.read(4096)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except BrokenPipeError:
            pass
        finally:
            proc.kill()
            proc.wait()

    def log_message(self, format, *args):
        return


def find_monitor_source():
    try:
        info = subprocess.check_output(["pactl", "info"], text=True)
    except subprocess.CalledProcessError as exc:
        raise RuntimeError("PulseAudio is not running") from exc

    # Prefer octo-sink.monitor if available
    sources = subprocess.check_output(["pactl", "list", "short", "sources"], text=True).splitlines()
    monitor_candidates = [line.split("\t")[1] for line in sources if line.split("\t")[1].endswith(".monitor")]

    if "octo-sink.monitor" in monitor_candidates:
        return "octo-sink.monitor"

    sink = None
    for line in info.splitlines():
        if line.startswith("Default Sink:"):
            sink = line.split(":", 1)[1].strip()
            break

    if sink:
        exact = f"{sink}.monitor"
        if exact in monitor_candidates:
            return exact

    if monitor_candidates:
        return monitor_candidates[0]

    raise RuntimeError("No PulseAudio monitor source found")


def main():
    parser = argparse.ArgumentParser(description="Audio streamer for Octo VNC")
    parser.add_argument("--port", type=int, default=8000, help="HTTP port for audio stream")
    args = parser.parse_args()

    monitor_source = os.environ.get("PULSE_SOURCE")
    if not monitor_source:
        monitor_source = find_monitor_source()

    address = ("127.0.0.1", args.port)
    class CustomServer(ThreadingHTTPServer):
        pass

    server = CustomServer(address, AudioHandler)
    server.monitor_source = monitor_source

    print(f"Starting audio stream on http://127.0.0.1:{args.port}/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
