#!/bin/bash

# RPi WiFi Fallback Hotspot - Complete Uninstaller
# Author: darkdrago74
# GitHub: https://github.com/darkdrago74/rpi-wifi-fallback

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

log "Starting RPi WiFi Fallback UNINSTALLATION..."
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

# Remove main script
log "Removing main WiFi fallback script..."
if [ -f /usr/local/bin/wifi-fallback.sh ]; then
    sudo rm -f /usr/local/bin/wifi-fallback.sh
    success "✅ Main script removed"
else
    info "Main script not found (already removed)"
fi

# Remove hotspot control script
log "Removing hotspot control script..."
if [ -f /usr/local/bin/hotspot-control ]; then
    sudo rm -f /usr/local/bin/hotspot-control
    success "✅ Hotspot control script removed"
else
    info "Hotspot control script not found (already removed)"
fi

# Remove alias from bash.bashrc
log "Removing hotspot command alias..."
if grep -q "alias hotspot=" /etc/bash.bashrc 2>/dev/null; then
    sudo sed -i '/alias hotspot="sudo hotspot-control"/d' /etc/bash.bashrc
    success "✅ Hotspot alias removed"
else
    info "Hotspot alias not found (already removed)"
fi

# Remove configuration file
log "Removing configuration file..."
if [ -f /etc/wifi-fallback.conf ]; then
    # Backup before removing
    sudo cp /etc/wifi-fallback.conf /tmp/wifi-fallback.conf.backup
    sudo rm -f /etc/wifi-fallback.conf
    success "✅ Configuration file removed (backup at /tmp/wifi-fallback.conf.backup)"
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
if [ -f /etc/dnsmasq.conf.backup ]; then
    sudo mv /etc/dnsmasq.conf.backup /etc/dnsmasq.conf
    success "✅ Original dnsmasq configuration restored"
elif [ -f /etc/dnsmasq.conf ]; then
    # Check if it's our minimal config
    if grep -q "interface=wlan0" /etc/dnsmasq.conf && grep -q "dhcp-range=192.168.66.2" /etc/dnsmasq.conf; then
        sudo rm -f /etc/dnsmasq.conf
        # Create a basic default config
        sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
# Basic dnsmasq configuration
# Add your custom configurations here
EOF
        success "✅ Our dnsmasq configuration removed, basic config restored"
    else
        warning "⚠️ Dnsmasq config exists but doesn't appear to be ours - leaving it"
    fi
else
    info "Dnsmasq configuration not found"
fi

# Restore lighttpd configuration (remove CGI if we added it)
log "Checking lighttpd configuration..."
if [ -f /etc/lighttpd/lighttpd.conf ]; then
    # Remove our CGI configuration if present
    if grep -q 'cgi.assign = ( ".cgi" => "" )' /etc/lighttpd/lighttpd.conf; then
        sudo sed -i '/cgi.assign = ( ".cgi" => "" )/d' /etc/lighttpd/lighttpd.conf
        success "✅ CGI configuration removed from lighttpd"
    fi
    
    # Comment out mod_cgi if we uncommented it
    sudo sed -i 's/        "mod_cgi",/#       "mod_cgi",/' /etc/lighttpd/lighttpd.conf
    
    # Reset port to 80 if we changed it
    sudo sed -i 's/server.port = 8080/server.port = 80/' /etc/lighttpd/lighttpd.conf
    sudo sed -i 's/server.port.*= [0-9]*/server.port = 80/' /etc/lighttpd/lighttpd.conf
    
    success "✅ Lighttpd configuration cleaned up"
fi

# Stop any running hostapd/dnsmasq processes that might be from our script
log "Stopping hotspot services..."
sudo systemctl stop hostapd 2>/dev/null || true
sudo systemctl stop dnsmasq 2>/dev/null || true

# Reset services to their original state
sudo systemctl disable hostapd 2>/dev/null || true
sudo systemctl disable dnsmasq 2>/dev/null || true

# Restart lighttpd with clean config
sudo systemctl restart lighttpd 2>/dev/null || true

# Remove any static IP configuration we might have set
log "Cleaning up network configuration..."
sudo ip addr flush dev wlan0 2>/dev/null || true

# Restart networking to restore normal WiFi behavior
log "Restarting network services..."
sudo systemctl restart wpa_supplicant 2>/dev/null || true
sudo systemctl restart dhcpcd 2>/dev/null || true

# Remove log file
log "Removing log files..."
if [ -f /var/log/wifi-fallback.log ]; then
    sudo rm -f /var/log/wifi-fallback.log
    success "✅ Log file removed"
fi

# Clean up any temporary files
sudo rm -f /tmp/wpa_temp.conf 2>/dev/null || true

log "================================================"
success "🎉 WiFi Fallback system completely removed!"
log ""
info "📋 What was removed:"
info "• WiFi fallback service and all scripts"
info "• Web configuration interface"
info "• Hotspot configurations"
info "• Manual hotspot control commands"
info "• System logs and temporary files"
log ""
info "📋 What remains (if you want to remove manually):"
info "• Packages: hostapd, dnsmasq, lighttpd, git"
info "  Remove with: sudo apt remove hostapd dnsmasq lighttpd"
info "• Configuration backup: /tmp/wifi-fallback.conf.backup"
log ""
warning "⚠️  Reboot recommended to ensure all changes take effect"
info "   sudo reboot"
log ""
info "Your Raspberry Pi will now use standard WiFi behavior."
info "Thank you for trying the WiFi Fallback system! 👋"
