#!/bin/bash

# RPi WiFi Fallback - Safe Uninstaller v2.5
# Preserves active connections during removal

set +e  # Don't exit on errors (important for uninstall)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "Don't run as root. Use: ./uninstall.sh"
   exit 1
fi

log "WiFi Fallback SAFE Uninstaller v2.5"
log "===================================="

# CRITICAL: Check current connection
PRESERVE_CONNECTION=false
CURRENT_SSID=""
CURRENT_IP=""
CONNECTION_TYPE=""

# Check WiFi
if iwgetid wlan0 >/dev/null 2>&1; then
    CURRENT_SSID=$(iwgetid wlan0 -r)
    CURRENT_IP=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    
    if [ -n "$CURRENT_SSID" ] && [ -n "$CURRENT_IP" ]; then
        PRESERVE_CONNECTION=true
        CONNECTION_TYPE="wifi"
        warning "⚠️  Active WiFi connection detected!"
        info "   SSID: $CURRENT_SSID"
        info "   IP: $CURRENT_IP"
    fi
fi

# Check Ethernet
ETH_IP=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
if [ -n "$ETH_IP" ]; then
    info "Ethernet connected: $ETH_IP"
    CONNECTION_TYPE="ethernet"
fi

if [ "$PRESERVE_CONNECTION" = true ] && [ "$CONNECTION_TYPE" = "wifi" ]; then
    warning ""
    warning "⚡ IMPORTANT: You're connected via WiFi"
    warning "   The uninstaller will preserve your connection"
    warning "   Some cleanup will happen after reboot"
    echo ""
fi

read -p "Continue with uninstall? (y/N): " -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    info "Uninstall cancelled."
    exit 0
fi

echo ""
log "Starting safe removal..."

# Save current network config if on WiFi
if [ "$PRESERVE_CONNECTION" = true ]; then
    log "Backing up current network configuration..."
    
    # Save wpa_supplicant
    if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
        sudo cp /etc/wpa_supplicant/wpa_supplicant.conf /tmp/wpa_restore.conf
    fi
    
    # Save NetworkManager connection if exists
    if command -v nmcli >/dev/null 2>&1; then
        nmcli connection show "$CURRENT_SSID" > /tmp/nm_connection.txt 2>/dev/null || true
    fi
fi

# Stop service but DON'T kill network processes if on WiFi
log "Stopping WiFi fallback service..."
sudo systemctl stop wifi-fallback.service 2>/dev/null || true
sudo systemctl disable wifi-fallback.service 2>/dev/null || true

# Only stop network services if NOT on WiFi
if [ "$CONNECTION_TYPE" != "wifi" ]; then
    log "Stopping hotspot services..."
    sudo systemctl stop hostapd 2>/dev/null || true
    sudo systemctl stop dnsmasq 2>/dev/null || true
    sudo killall -9 hostapd 2>/dev/null || true
    sudo killall -9 dnsmasq 2>/dev/null || true
else
    warning "Skipping network service stops to preserve WiFi"
fi

# Remove service files
log "Removing service files..."
sudo rm -f /etc/systemd/system/wifi-fallback.service
sudo rm -f /etc/systemd/system/wifi-fallback-activate.service
sudo systemctl daemon-reload

# Remove scripts
log "Removing scripts..."
SCRIPTS=(
    "/usr/local/bin/wifi-fallback.sh"
    "/usr/local/bin/hotspot-control"
    "/usr/local/bin/hotspot"
    "/usr/local/bin/netdiag"
    "/usr/local/bin/network-reset"
    "/usr/local/bin/wifi-fallback-activate"
)

for script in "${SCRIPTS[@]}"; do
    [ -f "$script" ] && sudo rm -f "$script"
done

# Backup and remove config
if [ -f /etc/wifi-fallback.conf ]; then
    sudo cp /etc/wifi-fallback.conf /tmp/wifi-fallback.conf.final-backup
    sudo rm -f /etc/wifi-fallback.conf
    info "Config backed up to /tmp/wifi-fallback.conf.final-backup"
fi

# Remove web interface
log "Removing web interface..."
if [ -f /var/www/html/index.html ]; then
    if grep -q "WiFi Configuration" /var/www/html/index.html 2>/dev/null; then
        sudo rm -f /var/www/html/index.html
    fi
fi
sudo rm -f /usr/lib/cgi-bin/wifi-config.cgi

# Restore NetworkManager CAREFULLY
if [ "$CONNECTION_TYPE" = "wifi" ]; then
    log "Scheduling NetworkManager restoration for after reboot..."
    
    # Create restoration script
    sudo tee /usr/local/bin/restore-network-manager > /dev/null <<'EOF'
#!/bin/bash
# Restore NetworkManager to manage wlan0
rm -f /etc/NetworkManager/conf.d/99-unmanaged-devices.conf
rm -f /etc/NetworkManager/conf.d/99-unmanaged-devices.conf.pending
systemctl restart NetworkManager
rm -f /usr/local/bin/restore-network-manager
rm -f /etc/systemd/system/restore-network-manager.service
EOF
    sudo chmod +x /usr/local/bin/restore-network-manager
    
    # Create one-time service
    sudo tee /etc/systemd/system/restore-network-manager.service > /dev/null <<'EOF'
[Unit]
Description=Restore NetworkManager
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/restore-network-manager

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl enable restore-network-manager.service
    
    info "NetworkManager will be restored after reboot"
else
    # Safe to restore now
    log "Restoring NetworkManager configuration..."
    sudo rm -f /etc/NetworkManager/conf.d/99-unmanaged-devices.conf
    sudo rm -f /etc/NetworkManager/conf.d/99-unmanaged-devices.conf.pending
    sudo rm -f /etc/NetworkManager/system-connections/eth0-only.nmconnection
    
    if systemctl is-active --quiet NetworkManager; then
        sudo nmcli general reload 2>/dev/null || true
        sudo nmcli device set wlan0 managed yes 2>/dev/null || true
    fi
fi

# Restore dhcpcd
log "Restoring dhcpcd configuration..."
if [ -f /etc/dhcpcd.conf ]; then
    sudo sed -i '/# Added by wifi-fallback installer/,+1d' /etc/dhcpcd.conf
fi
[ -f /etc/dhcpcd.conf.pending ] && sudo rm -f /etc/dhcpcd.conf.pending

# Remove sudoers entries
if sudo grep -q "www-data.*wifi-fallback" /etc/sudoers; then
    sudo sed -i '/www-data.*wifi-fallback/d' /etc/sudoers
fi

# Clean hostapd/dnsmasq configs
if grep -q "$(hostname)-hotspot" /etc/hostapd/hostapd.conf 2>/dev/null; then
    sudo rm -f /etc/hostapd/hostapd.conf
fi

if grep -q "192.168.66.66" /etc/dnsmasq.conf 2>/dev/null; then
    sudo cp /etc/dnsmasq.conf /tmp/dnsmasq.conf.backup
    sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
# Default dnsmasq configuration
# Add your custom configurations here
EOF
fi

# Clean lighttpd
if grep -q 'cgi.assign = ( ".cgi" => "" )' /etc/lighttpd/lighttpd.conf; then
    sudo sed -i '/cgi.assign = ( ".cgi" => "" )/d' /etc/lighttpd/lighttpd.conf
fi
sudo sed -i 's/server.port = 8080/server.port = 80/' /etc/lighttpd/lighttpd.conf
sudo systemctl restart lighttpd 2>/dev/null || true

# Clean iptables rules
log "Removing iptables rules..."
sudo iptables -t nat -D POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE 2>/dev/null || true
sudo iptables -D FORWARD -i wlan0 -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -o wlan0 -j ACCEPT 2>/dev/null || true
sudo netfilter-persistent save 2>/dev/null || true

# Remove log file
sudo rm -f /var/log/wifi-fallback.log

# Final restoration based on connection
if [ "$PRESERVE_CONNECTION" = true ] && [ "$CONNECTION_TYPE" = "wifi" ]; then
    # Ensure WiFi stays connected
    warning ""
    warning "⚠️  IMPORTANT: Your WiFi connection has been preserved!"
    info "   You're still connected to: $CURRENT_SSID"
    info "   Final cleanup will occur after reboot"
    
    # Restore wpa_supplicant if needed
    if [ -f /tmp/wpa_restore.conf ] && [ ! -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
        sudo cp /tmp/wpa_restore.conf /etc/wpa_supplicant/wpa_supplicant.conf
    fi
else
    # Full cleanup possible
    log "Restarting network services..."
    
    if systemctl is-active --quiet NetworkManager; then
        sudo systemctl restart NetworkManager
    else
        sudo systemctl restart wpa_supplicant 2>/dev/null || true
        sudo systemctl restart dhcpcd 2>/dev/null || true
    fi
fi

log "================================================"
log "✅ WiFi Fallback system removed!"
log ""

if [ "$PRESERVE_CONNECTION" = true ]; then
    warning "Your current network connection was preserved"
    warning "Please reboot to complete the cleanup process"
else
    info "Network services have been restored to defaults"
fi

info ""
info "Remaining packages (remove manually if desired):"
info "  sudo apt remove hostapd dnsmasq lighttpd"
log ""
info "Thank you for using WiFi Fallback! 👋"
