#!/bin/bash
set -euo pipefail

# Minecraft Relay Bootstrap
# Usage:
#   sudo ./setup-minecraft-relay.sh <crafty-tailscale-ip>
#
# Example:
#   sudo ./setup-minecraft-relay.sh 100.92.46.10

if [[ $EUID -ne 0 ]]; then
    echo "Please run this script with sudo:"
    echo "  sudo ./setup-minecraft-relay.sh <crafty-tailscale-ip>"
    exit 1
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <crafty-tailscale-ip>"
    echo "Example: $0 100.92.46.10"
    exit 1
fi

CRAFTY_IP="$1"

echo "=== Minecraft Relay Setup ==="
echo "Crafty target: ${CRAFTY_IP}:25565"
echo

# --------------------------------------------------
# Check OS
# --------------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    echo "ERROR: Cannot determine operating system."
    exit 1
fi

source /etc/os-release

if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    echo "ERROR: This script supports Ubuntu and Debian only."
    echo "Detected: ${PRETTY_NAME:-unknown}"
    exit 1
fi

# --------------------------------------------------
# Update system and install packages
# --------------------------------------------------

echo "=== Updating system ==="

apt update
apt install -y haproxy curl netcat-openbsd

# --------------------------------------------------
# Install Tailscale
# --------------------------------------------------

echo
echo "=== Installing Tailscale ==="

if command -v tailscale >/dev/null 2>&1; then
    echo "Tailscale is already installed."
else
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# --------------------------------------------------
# Start Tailscale
# --------------------------------------------------

echo
echo "=== Starting Tailscale ==="

echo
echo "A Tailscale authentication page may appear."
echo "Authenticate this VM with your Tailscale account."
echo

tailscale up

# --------------------------------------------------
# Verify Tailscale
# --------------------------------------------------

echo
echo "=== Tailscale status ==="

tailscale status

# --------------------------------------------------
# Test Crafty
# --------------------------------------------------

echo
echo "=== Testing Crafty ==="
echo "Connecting to ${CRAFTY_IP}:25565..."

if nc -z -w 5 "$CRAFTY_IP" 25565; then
    echo "SUCCESS: Crafty is reachable at ${CRAFTY_IP}:25565"
else
    echo
    echo "ERROR: Crafty is not reachable at ${CRAFTY_IP}:25565."
    echo
    echo "Check:"
    echo "  1. Crafty is running."
    echo "  2. Crafty is connected to Tailscale."
    echo "  3. The Tailscale IP is correct."
    echo "  4. Minecraft is listening on port 25565."
    echo
    exit 1
fi

# --------------------------------------------------
# Back up existing HAProxy configuration
# --------------------------------------------------

echo
echo "=== Configuring HAProxy ==="

HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"
BACKUP_CONFIG="/etc/haproxy/haproxy.cfg.backup"

if [[ -f "$HAPROXY_CONFIG" ]]; then
    echo "Backing up existing HAProxy configuration..."

    cp "$HAPROXY_CONFIG" "$BACKUP_CONFIG"

    echo "Backup created at:"
    echo "  $BACKUP_CONFIG"
fi

# --------------------------------------------------
# Create HAProxy configuration
# --------------------------------------------------

cat > "$HAPROXY_CONFIG" <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    log global
    mode tcp
    option tcplog

    timeout connect 5s
    timeout client 30s
    timeout server 30s

frontend minecraft
    mode tcp
    bind *:25565
    default_backend minecraft_server

backend minecraft_server
    mode tcp
    server crafty ${CRAFTY_IP}:25565 check
EOF

# --------------------------------------------------
# Validate HAProxy
# --------------------------------------------------

echo
echo "=== Validating HAProxy configuration ==="

if ! haproxy -c -f "$HAPROXY_CONFIG"; then
    echo
    echo "ERROR: HAProxy configuration is invalid."

    if [[ -f "$BACKUP_CONFIG" ]]; then
        echo "Restoring previous configuration..."
        cp "$BACKUP_CONFIG" "$HAPROXY_CONFIG"
    fi

    exit 1
fi

echo "HAProxy configuration is valid."

# --------------------------------------------------
# Start HAProxy
# --------------------------------------------------

echo
echo "=== Starting HAProxy ==="

systemctl enable haproxy
systemctl restart haproxy

# --------------------------------------------------
# Verify HAProxy
# --------------------------------------------------

echo
echo "=== Checking HAProxy ==="

if systemctl is-active --quiet haproxy; then
    echo "HAProxy is running."
else
    echo "ERROR: HAProxy failed to start."
    systemctl status haproxy --no-pager
    exit 1
fi

# --------------------------------------------------
# Verify Minecraft port
# --------------------------------------------------

echo
echo "=== Checking Minecraft relay port ==="

if ss -lnt | grep -q ':25565 '; then
    echo "SUCCESS: HAProxy is listening on TCP port 25565."
else
    echo "WARNING: Port 25565 is not currently listening."
fi

# --------------------------------------------------
# Complete
# --------------------------------------------------

echo
echo "========================================"
echo " Minecraft relay setup complete!"
echo "========================================"
echo
echo "Crafty target:"
echo "  ${CRAFTY_IP}:25565"
echo
echo "Relay port:"
echo "  0.0.0.0:25565"
echo
echo "Next step:"
echo "  Allow TCP 25565 in the Azure NSG."
echo
