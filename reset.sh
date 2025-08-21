#!/bin/bash
# Reset WiFi Fallback system to default state (troubleshooting)

echo "🔄 Resetting WiFi Fallback System..."

# Stop the service
sudo systemctl stop wifi-fallback.service

# Reset configuration to defaults
sudo tee /etc/wifi-fallback.conf > /dev/null <<EOF
MAIN_SSID=""
MAIN_PASSWORD=""
BACKUP_SSID=""
BACKUP_PASSWORD=""
FORCE_HOTSPOT=false
EOF

# Clear any stuck network states
sudo ip addr flush dev wlan0 2>/dev/null || true

# Stop hotspot services
sudo systemctl stop hostapd dnsmasq 2>/dev/null || true

# Restart network services
sudo systemctl restart wpa_supplicant dhcpcd

# Clear logs
sudo rm -f /var/log/wifi-fallback.log

# Start fresh
sudo systemctl start wifi-fallback.service

echo "✅ System reset complete!"
echo "Configure via web interface when hotspot activates"
