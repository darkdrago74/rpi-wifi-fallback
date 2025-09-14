#!/bin/bash

# RPi WiFi Fallback Hotspot - Complete Uninstaller v2.2
# Author: darkdrago74
# GitHub: https://github.com/darkdrago74/rpi-wifi-fallback
# Compatible with version 0.6-alpha and later

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Use: ./uninstall.sh"
   exit 1
fi

log "Starting RPi WiFi Fallback UNINSTALLATION v2.2..."
log "================================================"

warning "⚠️  This will completely remove the WiFi Fallback system"
warning "   Your Pi will return to standard WiFi behavior"
echo ""
info "What will be removed:"
info "• WiFi fallback service and scripts"
info "• Configuration files" 
info "• Web interface files"
info "• Hotspot configurations"
info "• Manual hotspot control commands"
info "• Network diagnostic tools (netdiag, network-reset)"
info "• NetworkManager configurations for wlan0"
echo ""
warning "What will NOT be removed:"
warning "• Installed packages (hostapd, dnsmasq, lighttpd)"
warning "• System updates"
warning "• Other system configurations"
echo ""

read -p "Are you sure you want to uninstall? (y/N): " -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    info "Uninstall cancelled."
    exit 0
fi

echo ""
log "Starting removal process..."

# Stop and disable the WiFi fallback service
log "Stopping WiFi fallback service..."
sudo systemctl stop wifi-fallback.service 2>/dev/null || true
sudo systemctl disable wifi-fallback.service 2>/dev/null || true
success "✅ Service stopped and disabled"

# Remove service file
log "Removing service file..."
if [ -f /etc/systemd/system/wifi-fallback.service ]; then
    sudo rm -f /etc/systemd/system/wifi-fallback.service
    success "✅ Service file removed"
else
    info "Service file not found (already removed)"
fi

# Reload systemd
sudo systemctl daemon-reload

# Remove main scripts
log "Removing WiFi fallback scripts..."
SCRIPTS_TO_REMOVE=(
    "/usr/local/bin/wifi-fallback.sh"
    "/usr/local/bin/hotspot-control"
    "/usr/local/bin/hotspot"
    "/usr/local/bin/netdiag"
    "/usr/local/bin/network-reset"
)

for script in "${SCRIPTS_TO_REMOVE[@]}"; do
    if [ -f "$script" ]; then
        sudo rm -f "$script"
        success "✅ Removed: $(basename $script)"
    else
        info "$(basename $script) not found (already removed)"
    fi
done

# Remove configuration file
log "Removing configuration file..."
if [ -f /etc/wifi-fallback.conf ]; then
    # Backup before removing
    sudo cp /etc/wifi-fallback.conf /tmp/wifi-fallback.conf.backup.$(date +%Y%m%d_%H%M%S)
    sudo rm -f /etc/wifi-fallback.conf
    success "✅ Configuration file removed (backup saved in /tmp/)"
else
    info "Configuration file not found (already removed)"
fi

# Remove web interface files
log "Removing web interface..."
if [ -f /var/www/html/index.html ]; then
    # Check if it's our file (contains "WiFi Configuration")
    if grep -q "WiFi Configuration" /var/www/html/index.html 2>/dev/null; then
        sudo rm -f /var/www/html/index.html
        success "✅ Web interface HTML removed"
    else
        warning "⚠️ /var/www/html/index.html exists but doesn't appear to be ours - leaving it"
    fi
else
    info "Web interface HTML not found"
fi

if [ -f /usr/lib/cgi-bin/wifi-config.cgi ]; then
    sudo rm -f /usr/lib/cgi-bin/wifi-config.cgi
    success "✅ CGI script removed"
else
    info "CGI script not found"
fi

# Restore NetworkManager configuration
log "Restoring NetworkManager configuration..."
if [ -f /etc/NetworkManager/conf.d/99-unmanaged-devices.conf ]; then
    sudo rm -f /etc/NetworkManager/conf.d/99-unmanaged-devices.conf
    success "✅ NetworkManager configuration restored"
fi

if [ -f /etc/NetworkManager/system-connections/eth0-only.nmconnection ]; then
    sudo rm -f /etc/NetworkManager/system-connections/eth0-only.nmconnection
    success "✅ NetworkManager eth0 profile removed"
fi

# Restart NetworkManager if active
if systemctl is-active --quiet NetworkManager; then
    sudo systemctl restart NetworkManager
    success "✅ NetworkManager restarted"
fi

# Restore dhcpcd configuration if modified
log "Checking dhcpcd configuration..."
if [ -f /etc/dhcpcd.conf ]; then
    if grep -q "# Added by wifi-fallback installer" /etc/dhcpcd.conf; then
        # Remove our additions
        sudo sed -i '/# Added by wifi-fallback installer/,+1d' /etc/dhcpcd.conf
        success "✅ dhcpcd configuration restored"
        if systemctl is-enabled --quiet dhcpcd 2>/dev/null; then
            sudo systemctl restart dhcpcd
        fi
    fi
fi

# Remove sudoers entries for www-data
log "Removing sudoers entries..."
if sudo grep -q "www-data.*wifi-fallback" /etc/sudoers; then
    sudo sed -i '/www-data.*wifi-fallback/d' /etc/sudoers
    success "✅ Sudoers entries removed"
fi

# Restore original hostapd configuration
log "Restoring original hostapd configuration..."
if [ -f /etc/hostapd/hostapd.conf ]; then
    # Check if it's our configuration
    if grep -q "$(hostname)-hotspot" /etc/hostapd/hostapd.conf 2>/dev/null; then
        sudo rm -f /etc/hostapd/hostapd.conf
        success "✅ Hostapd configuration removed"
    else
        warning "⚠️ Hostapd config exists but doesn't appear to be ours - leaving it"
    fi
else
    info "Hostapd configuration not found"
fi

# Restore original dnsmasq configuration
log "Restoring original dnsmasq configuration..."
if [ -f /etc/dnsmasq.conf ]; then
    # Check if it's our config by looking for our specific settings
    if grep -q "interface=wlan0" /etc/dnsmasq.conf && grep -q "192.168.66.66" /etc/dnsmasq.conf; then
        # Save a backup just in case
        sudo cp /etc/dnsmasq.conf /tmp/dnsmasq.conf.backup.$(date +%Y%m%d_%H%M%S)
        # Create a minimal default config
        sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
# Default dnsmasq configuration
# Add your custom configurations here
EOF
        success "✅ Our dnsmasq configuration removed (backup in /tmp/)"
    else
        warning "⚠️ Dnsmasq config exists but doesn't appear to be ours - leaving it"
    fi
else
    info "Dnsmasq configuration not found"
fi

# Restore lighttpd configuration
log "Restoring lighttpd configuration..."
if [ -f /etc/lighttpd/lighttpd.conf ]; then
    # Remove our CGI configuration if present
    if grep -q 'cgi.assign = ( ".cgi" => "" )' /etc/lighttpd/lighttpd.conf; then
        sudo sed -i '/cgi.assign = ( ".cgi" => "" )/d' /etc/lighttpd/lighttpd.conf
        success "✅ CGI configuration removed from lighttpd"
    fi
    
    # Comment out mod_cgi if we uncommented it
    sudo sed -i 's/^    "mod_cgi",/#   "mod_cgi",/' /etc/lighttpd/lighttpd.conf
    
    # Reset port to 80 if we changed it
    sudo sed -i 's/server.port = 8080/server.port = 80/' /etc/lighttpd/lighttpd.conf
    sudo sed -i 's/server.port.*= [0-9]*/server.port = 80/' /etc/lighttpd/lighttpd.conf
    
    success "✅ Lighttpd configuration cleaned up"
    sudo systemctl restart lighttpd 2>/dev/null || true
fi

# Stop any running hotspot/dnsmasq processes that might be from our script
log "Stopping hotspot services..."
sudo systemctl stop hostapd 2>/dev/null || true
sudo systemctl stop dnsmasq 2>/dev/null || true

# Kill any remaining processes
sudo killall -9 wpa_supplicant 2>/dev/null || true
sudo killall -9 hostapd 2>/dev/null || true
sudo killall -9 dnsmasq 2>/dev/null || true
sudo killall -9 dhclient 2>/dev/null || true

# Reset services to their original state
sudo systemctl disable hostapd 2>/dev/null || true
sudo systemctl disable dnsmasq 2>/dev/null || true

# Remove any static IP configuration we might have set
log "Cleaning up network configuration..."
sudo ip addr flush dev wlan0 2>/dev/null || true

# Clear iptables rules we added
log "Removing iptables rules..."
sudo iptables -t nat -D POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE 2>/dev/null || true
sudo iptables -D FORWARD -i wlan0 -j ACCEPT 2>/dev/null || true
sudo iptables -D FORWARD -o wlan0 -j ACCEPT 2>/dev/null || true

# Save cleaned iptables
sudo netfilter-persistent save 2>/dev/null || true

# Restart networking to restore normal WiFi behavior
log "Restarting network services..."
if systemctl is-active --quiet NetworkManager; then
    sudo systemctl restart NetworkManager
else
    sudo systemctl restart wpa_supplicant 2>/dev/null || true
    sudo systemctl restart dhcpcd 2>/dev/null || true
fi

# Remove log file
log "Removing log files..."
if [ -f /var/log/wifi-fallback.log ]; then
    sudo rm -f /var/log/wifi-fallback.log
    success "✅ Log file removed"
fi

# Clean up any temporary files
sudo rm -f /tmp/wpa_temp.conf 2>/dev/null || true
sudo rm -f /tmp/wifi-fallback-dhcp-fix.patch 2>/dev/null || true

log "================================================"
success "🎉 WiFi Fallback system completely removed!"
log ""
info "📋 What was removed:"
info "• WiFi fallback service and all scripts"
info "• Web configuration interface"
info "• Hotspot configurations"
info "• Manual hotspot control commands"
info "• Network diagnostic tools"
info "• NetworkManager/dhcpcd configurations"
info "• System logs and temporary files"
log ""
info "📋 What remains (if you want to remove manually):"
info "• Packages: hostapd, dnsmasq, lighttpd, git"
info "  Remove with: sudo apt remove hostapd dnsmasq lighttpd"
info "• Configuration backups in /tmp/"
log ""
info "✅ Your network configuration has been restored to default"
info "• NetworkManager now manages wlan0 again"
info "• Standard WiFi behavior restored"
log ""
warning "⚠️  Reboot recommended to ensure all changes take effect"
info "   sudo reboot"
log ""
info "Your Raspberry Pi will now use standard WiFi behavior."
info "Thank you for trying the WiFi Fallback system v0.6-alpha! 👋"
