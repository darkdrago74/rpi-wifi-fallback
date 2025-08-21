#!/bin/bash
# Check if WiFi Fallback system is properly installed

echo "🔍 WiFi Fallback System Status Check"
echo "====================================="

# Check service status
if systemctl is-active --quiet wifi-fallback.service; then
    echo "✅ Service: Running"
else
    echo "❌ Service: Not running"
fi

if systemctl is-enabled --quiet wifi-fallback.service; then
    echo "✅ Service: Enabled (starts on boot)"
else
    echo "❌ Service: Not enabled"
fi

# Check files
FILES_TO_CHECK=(
    "/usr/local/bin/wifi-fallback.sh"
    "/usr/local/bin/hotspot-control"
    "/etc/systemd/system/wifi-fallback.service"
    "/etc/wifi-fallback.conf"
    "/var/www/html/index.html"
    "/usr/lib/cgi-bin/wifi-config.cgi"
    "/etc/hostapd/hostapd.conf"
)

echo ""
echo "📁 File Status:"
for file in "${FILES_TO_CHECK[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file"
    else
        echo "❌ $file"
    fi
done

# Check packages
echo ""
echo "📦 Package Status:"
PACKAGES=("hostapd" "dnsmasq" "lighttpd")
for pkg in "${PACKAGES[@]}"; do
    if dpkg -l | grep -q "^ii  $pkg "; then
        echo "✅ $pkg: Installed"
    else
        echo "❌ $pkg: Not installed"
    fi
done

# Check current network status
echo ""
echo "📶 Current Network Status:"
if iwgetid wlan0 >/dev/null 2>&1; then
    echo "📱 Connected to: $(iwgetid wlan0 -r)"
    IP=$(ip route get 1 | awk '{print $7}' | head -1)
    echo "🌐 IP address: $IP"
else
    echo "📡 Not connected (likely in hotspot mode)"
fi

# Show recent logs
echo ""
echo "📋 Recent Activity (last 5 lines):"
if [ -f /var/log/wifi-fallback.log ]; then
    sudo tail -5 /var/log/wifi-fallback.log
else
    echo "No log file found"
fi

echo ""
echo "🔧 Quick Commands:"
echo "  View full logs: sudo tail -f /var/log/wifi-fallback.log"
echo "  Restart service: sudo systemctl restart wifi-fallback"
echo "  Manual hotspot: hotspot on/off/status"
