#!/bin/bash

# VNC Setup Script - Start everything at once

echo "🚀 Starting VNC Desktop Setup..."
echo ""

# Kill any existing VNC servers
echo "Cleaning up old VNC sessions..."
vncserver -kill :1 2>/dev/null
sleep 1

# Start VNC server
echo "📺 Starting VNC server on port 5901..."
vncserver :1 -geometry 1280x720 -depth 24 -localhost no

# Wait for VNC to start
sleep 2

# Start desktop environment
echo "🖥️  Starting XFCE4 desktop..."
DISPLAY=:1 startxfce4 > /dev/null 2>&1 &

# Wait a moment for desktop to initialize
sleep 2

# Kill any existing websockify
pkill -f "websockify 6080" 2>/dev/null
sleep 1

# Start websockify for web access
echo "🌐 Starting websockify on port 6080..."
websockify 6080 localhost:5901 --web=/usr/share/novnc/ > /dev/null 2>&1 &

# Wait for websockify to start
sleep 2

# Start SSH tunnel
echo "🔗 Creating public tunnel via localhost.run..."
echo ""
ssh -o StrictHostKeyChecking=no -R 80:localhost:6080 nokey@localhost.run

echo ""
echo "✅ Setup complete!"
echo "Your VNC desktop is now accessible via the tunnel URL shown above"#!/bin/bash

# VNC Setup Script - Start everything at once

echo "🚀 Starting VNC Desktop Setup..."
echo ""

# Kill any existing VNC servers
echo "Cleaning up old VNC sessions..."
vncserver -kill :1 2>/dev/null
sleep 1

# Start VNC server
echo "📺 Starting VNC server on port 5901..."
vncserver :1 -geometry 1280x720 -depth 24 -localhost no

# Wait for VNC to start
sleep 2

# Start desktop environment
echo "🖥️  Starting XFCE4 desktop..."
DISPLAY=:1 startxfce4 > /dev/null 2>&1 &

# Wait a moment for desktop to initialize
sleep 2

# Kill any existing websockify
pkill -f "websockify 6080" 2>/dev/null
sleep 1

# Start websockify for web access
echo "🌐 Starting websockify on port 6080..."
websockify 6080 localhost:5901 --web=/usr/share/novnc/ > /dev/null 2>&1 &

# Wait for websockify to start
sleep 2

# Start SSH tunnel
echo "🔗 Creating public tunnel via localhost.run..."
echo ""
ssh -o StrictHostKeyChecking=no -R 80:localhost:6080 nokey@localhost.run

echo ""
echo "✅ Setup complete!"
echo "Your VNC desktop is now accessible via the tunnel URL shown above"
