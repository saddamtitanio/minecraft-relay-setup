#!/bin/bash
set -e

CRAFTY_IP="${1:-100.92.46.10}"

echo "=== Updating system ==="
sudo apt update
sudo apt install -y haproxy curl netcat-openbsd

echo "=== Installing Tailscale ==="
curl -fsSL https://tailscale.com/install.sh | sh

echo "=== Starting Tailscale ==="
sudo tailscale up

echo "=== Testing Crafty ==="
if nc -z -w 5 "$CRAFTY_IP" 25565; then
    echo "Crafty is reachable at $CRAFTY_IP:25565"
else
    echo "WARNING: Crafty is not reachable yet."
    echo "Check Tailscale before continuing."
fi

echo "=== Configuring HAProxy ==="

sudo tee /etc/haproxy/haproxy.cfg > /dev/null <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon

defaults
    log global
    mode tcp
    option tcplog
    timeout connect 5s
    timeout client  30s
    timeout server  30s

frontend minecraft
    mode tcp
    bind *:25565
    default_backend minecraft_server

backend minecraft_server
    mode tcp
    server crafty ${CRAFTY_IP}:25565 check
EOF

echo "=== Validating HAProxy ==="
sudo haproxy -c -f /etc/haproxy/haproxy.cfg

echo "=== Starting HAProxy ==="
sudo systemctl enable --now haproxy

echo
echo "=== Relay status ==="
sudo systemctl status haproxy --no-pager
sudo ss -lntp | grep 25565 || true

echo
echo "Relay setup complete."
echo "Crafty target: ${CRAFTY_IP}:25565"
