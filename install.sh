#!/bin/bash

# RPi WiFi Fallback Hotspot - Automatic Installer
# Author: darkdrago74
# GitHub: https://github.com/darkdrago74/rpi-wifi-fallback

set -e  # Exit on any error

# Auto-fix permissions if needed
if [[ ! -x "$0" ]]; then
    echo "Making install script executable..."
    chmod +x "$0"
    exec "$0" "$@"
fi

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
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check Debian/Raspberry Pi OS version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$VERSION_CODENAME" == "bookworm" ]] || [[ "$VERSION_CODENAME" == "bullseye" ]] || [[ "$VERSION_CODENAME" == "buster" ]]; then
        log "✅ Detected compatible OS: $PRETTY_NAME"
    else
        warning "Untested OS version: $PRETTY_NAME - continuing anyway"
    fi
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Use: ./install.sh"
fi

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    warning "This doesn't appear to be a Raspberry Pi. Continue anyway? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

log "Starting RPi WiFi Fallback Installation..."
log "================================================"

# Update system - assuming users do it by default
#log "Updating system packages..."
sudo apt update

# Install required packages
log "Installing required packages..."
sudo apt install -y hostapd dnsmasq lighttpd git

# Stop services (will be managed by our script)
log "Configuring services..."
sudo systemctl stop hostapd dnsmasq 2>/dev/null || true
sudo systemctl disable hostapd dnsmasq 2>/dev/null || true

# Create directories
log "Creating directories..."
sudo mkdir -p /usr/local/bin
sudo mkdir -p /var/log
sudo mkdir -p /usr/lib/cgi-bin

# Install main script
log "Installing WiFi fallback script..."
sudo cp scripts/wifi-fallback.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/wifi-fallback.sh

# Install configuration files
log "Installing configuration files..."
sudo cp config/hostapd.conf /etc/hostapd/
sudo cp config/dnsmasq.conf /etc/dnsmasq.conf
sudo cp config/wifi-fallback.service /etc/systemd/system/

# Install web interface
log "Installing web interface..."
sudo cp web/index.html /var/www/html/
sudo cp web/wifi-config.cgi /usr/lib/cgi-bin/
sudo chmod +x /usr/lib/cgi-bin/wifi-config.cgi

# Install hotspot control script
log "Installing hotspot control commands..."
sudo cp scripts/hotspot-control.sh /usr/local/bin/hotspot-control
sudo chmod +x /usr/local/bin/hotspot-control

# Create convenient alias
if ! grep -q "alias hotspot=" /etc/bash.bashrc; then
    echo 'alias hotspot="sudo hotspot-control"' | sudo tee -a /etc/bash.bashrc
fi
log "Manual hotspot control installed!"
log "Usage: hotspot on/off/status"

# Configure lighttpd for CGI
log "Configuring web server..."
sudo sed -i 's/#.*"mod_cgi"/        "mod_cgi",/' /etc/lighttpd/lighttpd.conf
if ! grep -q "cgi.assign" /etc/lighttpd/lighttpd.conf; then
    echo 'cgi.assign = ( ".cgi" => "" )' | sudo tee -a /etc/lighttpd/lighttpd.conf
fi

# Enable and start services
log "Enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable lighttpd
sudo systemctl enable wifi-fallback.service
sudo systemctl restart lighttpd
sudo systemctl start wifi-fallback.service

# Create initial config file if it doesn't exist
if [ ! -f /etc/wifi-fallback.conf ]; then
    log "Creating initial configuration..."
    sudo tee /etc/wifi-fallback.conf > /dev/null <<EOF
MAIN_SSID=""
MAIN_PASSWORD=""
BACKUP_SSID=""
BACKUP_PASSWORD=""
FORCE_HOTSPOT=false
EOF
fi

# Get hostname for hotspot name
HOSTNAME=$(hostname)

log "================================================"
log "✅ Installation completed successfully!"
log ""
info "📡 Hotspot will be named: ${HOSTNAME}-hotspot"
info "🔑 Hotspot password: raspberry"
info "🌐 Web interface: http://192.168.66.66:8080 (when in hotspot mode)"
log ""
info "🔧 How to configure:"
info "1. If you have Ethernet or wifi connected, configure via SSH now"
info "2. Or disconnect from current WiFi to trigger hotspot mode"
info "3. Connect to ${HOSTNAME}-hotspot and visit http://192.168.66.66:8080   Or the IP address given to your rooter"
log ""
info "📋 Useful commands:"
info "  Check status: sudo systemctl status wifi-fallback"
info "  View logs: sudo tail -f /var/log/wifi-fallback.log"
info "  Restart service: sudo systemctl restart wifi-fallback"
log ""
warning "⚠️  Reboot recommended to ensure all services start properly"
info "   sudo reboot"
