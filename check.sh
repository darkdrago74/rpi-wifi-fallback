#!/bin/bash

# WiFi Fallback System Check Script v2.2
# Compatible with version 0.6-alpha and later

echo "🔍 WiFi Fallback System Status Check v0.6-alpha"
echo "================================================"

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

# Check version
if [ -f VERSION ]; then
    echo "📌 Version: $(cat VERSION)"
else
    echo "📌 Version: Unknown (no VERSION file)"
fi

# Check files
FILES_TO_CHECK=(
    "/usr/local/bin/wifi-fallback.sh"
    "/usr/local/bin/hotspot-control"
    "/usr/local/bin/hotspot"
    "/usr/local/bin/netdiag"
    "/usr/local/bin/network-reset"
    "/etc/systemd/system/wifi-fallback.service"
    "/etc/wifi-fallback.conf"
    "/var/www/html/index.html"
    "/usr/lib/cgi-bin/wifi-config.cgi"
    "/etc/hostapd/hostapd.conf"
    "/etc/dnsmasq.conf"
)

echo ""
echo "📁 File Status:"
missing_files=0
for file in "${FILES_TO_CHECK[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file"
    else
        echo "❌ $file (missing)"
        missing_files=$((missing_files + 1))
    fi
done

if [ $missing_files -eq 0 ]; then
    echo "✅ All files present"
else
    echo "⚠️  $missing_files file(s) missing"
fi

# Check NetworkManager configuration
echo ""
echo "🔧 NetworkManager Configuration:"
if [ -f /etc/NetworkManager/conf.d/99-unmanaged-devices.conf ]; then
    echo "✅ NetworkManager configured to ignore wlan0"
else
    if systemctl is-active --quiet NetworkManager; then
        echo "⚠️  NetworkManager not configured (may interfere with wlan0)"
    else
        echo "ℹ️  NetworkManager not active"
    fi
fi

# Check packages
echo ""
echo "📦 Package Status:"
PACKAGES=("hostapd" "dnsmasq" "lighttpd" "iptables-persistent")
for pkg in "${PACKAGES[@]}"; do
    if dpkg -l | grep -q "^ii  $pkg "; then
        echo "✅ $pkg: Installed"
    else
        echo "❌ $pkg: Not installed"
    fi
done

# Check current configuration
echo ""
echo "⚙️ Current Configuration:"
if [ -f /etc/wifi-fallback.conf ]; then
    source /etc/wifi-fallback.conf
    echo "  Primary SSID: ${MAIN_SSID:-<not configured>}"
    echo "  Backup SSID: ${BACKUP_SSID:-<not configured>}"
    echo "  Force Hotspot: $FORCE_HOTSPOT"
else
    echo "❌ Configuration file not found"
fi

# Check current network status
echo ""
echo "📶 Current Network Status:"

# Check if in hotspot mode
if pgrep hostapd >/dev/null; then
    echo "📡 Mode: HOTSPOT ACTIVE"
    echo "  SSID: $(hostname)-hotspot"
    echo "  IP: 192.168.66.66"
    
    # Check NAT
    if sudo iptables -t nat -L POSTROUTING -n 2>/dev/null | grep -q "192.168.66.0/24"; then
        echo "  NAT: ✅ Configured"
    else
        echo "  NAT: ❌ Not configured"
    fi
    
    # Count connected clients
    clients=$(sudo arp -an | grep -c "192.168.66" || echo "0")
    echo "  Connected clients: $clients"
elif iwgetid wlan0 >/dev/null 2>&1; then
    echo "📱 Mode: WIFI CLIENT"
    ssid=$(iwgetid wlan0 -r)
    if [ -n "$ssid" ]; then
        echo "  Connected to: $ssid"
        ip=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        [ -n "$ip" ] && echo "  IP address: $ip"
    fi
else
    echo "🔌 Mode: DISCONNECTED or TRANSITIONING"
fi

# Check Ethernet
eth_ip=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
if [ -n "$eth_ip" ]; then
    echo "🔌 Ethernet: Connected ($eth_ip)"
else
    echo "🔌 Ethernet: Not connected"
fi

# Check web interface
echo ""
echo "🌐 Web Interface:"
if sudo systemctl is-active --quiet lighttpd; then
    port=$(grep "server.port" /etc/lighttpd/lighttpd.conf | grep -oE '[0-9]+' | head -1)
    echo "✅ Web server running on port ${port:-80}"
    
    # Check CGI
    if [ -x /usr/lib/cgi-bin/wifi-config.cgi ]; then
        echo "✅ CGI script executable"
    else
        echo "❌ CGI script not executable"
    fi
else
    echo "❌ Web server not running"
fi

# Show recent logs
echo ""
echo "📋 Recent Activity (last 5 lines):"
if [ -f /var/log/wifi-fallback.log ]; then
    sudo tail -5 /var/log/wifi-fallback.log | sed 's/^/  /'
else
    echo "  No log file found"
fi

# System health check
echo ""
echo "💚 System Health:"

# Check CPU usage
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
echo "  CPU Usage: ${cpu_usage:-N/A}%"

# Check memory
mem_total=$(free -m | awk 'NR==2{print $2}')
mem_used=$(free -m | awk 'NR==2{print $3}')
mem_percent=$((mem_used * 100 / mem_total))
echo "  Memory: ${mem_used}MB / ${mem_total}MB (${mem_percent}%)"

# Check disk space
disk_usage=$(df -h / | awk 'NR==2{print $5}')
echo "  Disk Usage: $disk_usage"

echo ""
echo "🔧 Quick Commands:"
echo "  View full logs: sudo tail -f /var/log/wifi-fallback.log"
echo "  Restart service: sudo systemctl restart wifi-fallback"
echo "  Manual hotspot: hotspot on/off/status"
echo "  Network diagnostics: netdiag"
echo "  Reset system: ./reset.sh"
echo "  Web config: http://192.168.66.66:8080 (hotspot mode)"

# Final summary
echo ""
echo "================================================"
if [ $missing_files -eq 0 ] && systemctl is-active --quiet wifi-fallback.service; then
    echo "✅ System Status: HEALTHY - v0.6-alpha"
else
    echo "⚠️  System Status: NEEDS ATTENTION"
    [ $missing_files -gt 0 ] && echo "   - Missing files detected"
    systemctl is-active --quiet wifi-fallback.service || echo "   - Service not running"
fi
