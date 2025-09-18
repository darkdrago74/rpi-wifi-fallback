#!/bin/bash

# RPi WiFi Fallback Hotspot - Installer v1.0 Stable
# Author: darkdrago74
# GitHub: https://github.com/darkdrago74/rpi-wifi-fallback
# Version: 1.0.0 - Production Ready

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
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

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Use: ./install.sh"
fi

log "Starting RPi WiFi Fallback Installation v1.0..."
log "=================================================================="

# Detect network connection type BEFORE making changes
INSTALL_VIA_WIFI=false
INSTALL_VIA_ETH=false
CURRENT_SSID=""

if iwgetid wlan0 >/dev/null 2>&1; then
    CURRENT_SSID=$(iwgetid wlan0 -r)
    if [ -n "$CURRENT_SSID" ]; then
        INSTALL_VIA_WIFI=true
        warning "⚠️  Installing via WiFi connection to: $CURRENT_SSID"
        warning "   SSH may briefly disconnect but will recover"
    fi
fi

if ip link show eth0 | grep -q "state UP"; then
    INSTALL_VIA_ETH=true
    info "✅ Ethernet connection detected - stable install"
fi

# Update system
log "Updating system packages..."
sudo apt update || error "Failed to update package list"

# Install all packages at once
log "Installing required packages..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    hostapd \
    dnsmasq \
    lighttpd \
    lighttpd-mod-cgi \
    iptables \
    iptables-persistent \
    netfilter-persistent \
    iw \
    wireless-tools \
    net-tools \
    git \
    curl \
    wget || error "Failed to install packages"

# CRITICAL: Set up iptables BEFORE any network changes
log "Configuring firewall (preserving SSH)..."
sudo iptables -F INPUT 2>/dev/null || true
sudo iptables -F FORWARD 2>/dev/null || true
sudo iptables -t nat -F 2>/dev/null || true

# Essential rules - SSH FIRST
sudo iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT
sudo iptables -I INPUT 2 -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -I INPUT 3 -i lo -j ACCEPT

# Hotspot rules
sudo iptables -t nat -A POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE
sudo iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o wlan0 -m state --state ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A FORWARD -i wlan0 -o wlan1 -j ACCEPT
sudo iptables -A FORWARD -i wlan1 -o wlan0 -m state --state ESTABLISHED,RELATED -j ACCEPT

# Web and DNS rules
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 67 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 68 -j ACCEPT

# Save immediately
sudo netfilter-persistent save 2>/dev/null || true

# Enable IP forwarding
log "Enabling IP forwarding..."
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Configure NetworkManager if present (DON'T RELOAD DURING INSTALL)
if command -v nmcli >/dev/null 2>&1 && systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
    log "Configuring NetworkManager for next boot..."
    sudo mkdir -p /etc/NetworkManager/conf.d/
    
    cat <<'EOF' | sudo tee /etc/NetworkManager/conf.d/99-unmanaged-devices.conf >/dev/null
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
    
    log "NetworkManager configured (will apply after reboot)"
fi

# Configure dhcpcd if present
if systemctl is-enabled --quiet dhcpcd 2>/dev/null; then
    log "Configuring dhcpcd to ignore wlan0..."
    if ! grep -q "denyinterfaces wlan0" /etc/dhcpcd.conf 2>/dev/null; then
        echo "# Added by wifi-fallback installer" | sudo tee -a /etc/dhcpcd.conf
        echo "denyinterfaces wlan0" | sudo tee -a /etc/dhcpcd.conf
    fi
fi

# Stop conflicting services
log "Stopping conflicting services..."
sudo systemctl stop hostapd 2>/dev/null || true
sudo systemctl stop dnsmasq 2>/dev/null || true
sudo systemctl disable hostapd 2>/dev/null || true
sudo systemctl disable dnsmasq 2>/dev/null || true

# Create directories
log "Creating directories..."
sudo mkdir -p /usr/local/bin
sudo mkdir -p /var/log
sudo mkdir -p /usr/lib/cgi-bin
sudo mkdir -p /etc/iptables

# Install main script
log "Installing WiFi fallback script..."
if [ -f scripts/wifi-fallback.sh ]; then
    sudo cp scripts/wifi-fallback.sh /usr/local/bin/
    sudo chmod +x /usr/local/bin/wifi-fallback.sh
else
    error "scripts/wifi-fallback.sh not found!"
fi

# Install service file
log "Installing systemd service..."
if [ -f config/wifi-fallback.service ]; then
    sudo cp config/wifi-fallback.service /etc/systemd/system/
else
    error "config/wifi-fallback.service not found!"
fi

# Create dnsmasq configuration
log "Creating dnsmasq configuration..."
if [ -f config/dnsmasq.conf ]; then
    sudo cp config/dnsmasq.conf /etc/dnsmasq.conf
else
    sudo tee /etc/dnsmasq.conf > /dev/null <<'EOF'
interface=wlan0
bind-interfaces
listen-address=192.168.66.66
dhcp-range=192.168.66.10,192.168.66.50,255.255.255.0,24h
dhcp-option=3,192.168.66.66
dhcp-option=6,8.8.8.8,8.8.4.4
server=8.8.8.8
server=8.8.4.4
no-resolv
log-queries
log-dhcp
address=/config.local/192.168.66.66
address=/hotspot.local/192.168.66.66
except-interface=eth0
except-interface=lo
cache-size=150
no-negcache
EOF
fi

# Create hostapd configuration
log "Creating hostapd configuration..."
if [ -f config/hostapd.conf ]; then
    sudo cp config/hostapd.conf /etc/hostapd/hostapd.conf
else
    HOSTNAME=$(hostname)
    sudo tee /etc/hostapd/hostapd.conf > /dev/null <<EOF
interface=wlan0
driver=nl80211
ssid=${HOSTNAME}-hotspot
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=raspberry
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF
fi

# Install web interface
log "Installing web interface..."
if [ -f web/index.html ]; then
    sudo cp web/index.html /var/www/html/
else
    error "web/index.html not found!"
fi

# Install CGI script
if [ -f web/wifi-config.cgi ]; then
    sudo cp web/wifi-config.cgi /usr/lib/cgi-bin/
    sudo chmod +x /usr/lib/cgi-bin/wifi-config.cgi
    sudo chown www-data:www-data /usr/lib/cgi-bin/wifi-config.cgi
else
    error "web/wifi-config.cgi not found!"
fi

# Configure sudo for www-data
log "Configuring web interface permissions..."
if ! sudo grep -q "www-data.*wifi-fallback" /etc/sudoers.d/wifi-fallback 2>/dev/null; then
    echo "www-data ALL=(ALL) NOPASSWD: /bin/bash -c *wifi-fallback.conf*, /bin/systemctl restart wifi-fallback.service, /usr/bin/tee -a /var/log/wifi-fallback.log" | sudo tee /etc/sudoers.d/wifi-fallback
fi

# Install control scripts
log "Installing control scripts..."
if [ -f scripts/hotspot-control.sh ]; then
    sudo cp scripts/hotspot-control.sh /usr/local/bin/hotspot-control
    sudo chmod +x /usr/local/bin/hotspot-control
else
    warning "scripts/hotspot-control.sh not found, skipping..."
fi

# Create hotspot command shortcut
sudo tee /usr/local/bin/hotspot > /dev/null <<'EOF'
#!/bin/bash
case "$1" in
    on) sudo /usr/local/bin/hotspot-control on ;;
    off) sudo /usr/local/bin/hotspot-control off ;;
    status) sudo /usr/local/bin/hotspot-control status ;;
    restart) sudo /usr/local/bin/hotspot-control restart ;;
    *) echo "Usage: hotspot {on|off|status|restart}" ;;
esac
EOF
sudo chmod +x /usr/local/bin/hotspot

# Configure lighttpd
log "Configuring web server..."
sudo lighty-enable-mod cgi 2>/dev/null || true
sudo systemctl restart lighttpd

# Unmask hostapd
sudo systemctl unmask hostapd 2>/dev/null || true

# Create initial configuration - FORCE HOTSPOT ON FIRST BOOT
log "Creating initial configuration (hotspot mode for first boot)..."
sudo tee /etc/wifi-fallback.conf > /dev/null <<EOF
MAIN_SSID=""
MAIN_PASSWORD=""
BACKUP_SSID=""
BACKUP_PASSWORD=""
FORCE_HOTSPOT=true
EOF

# Create log file
sudo touch /var/log/wifi-fallback.log
sudo chmod 666 /var/log/wifi-fallback.log

# Enable services
log "Enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable wifi-fallback.service
sudo systemctl enable lighttpd

# DON'T start service now - let it start on boot
log "Service will start automatically on next boot..."

HOSTNAME=$(hostname)

log "=================================================================="
log "✅ Installation completed successfully!"
log "=================================================================="
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                                ║${NC}"
echo -e "${CYAN}║  ${YELLOW}📡 WIFI FALLBACK INSTALLED - REBOOT REQUIRED${CYAN}                ║${NC}"
echo -e "${CYAN}║                                                                ║${NC}"
echo -e "${CYAN}║  ${GREEN}After reboot, connect to:${CYAN}                                   ║${NC}"
echo -e "${CYAN}║  ${WHITE}SSID: ${HOSTNAME}-hotspot${CYAN}                           ║${NC}"
echo -e "${CYAN}║  ${WHITE}Password: raspberry${CYAN}                                         ║${NC}"
echo -e "${CYAN}║  ${WHITE}Config: http://192.168.66.66:8080${CYAN}                          ║${NC}"
echo -e "${CYAN}║                                                                ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${RED}★ REBOOT NOW: ${GREEN}sudo reboot${NC}"
echo ""
