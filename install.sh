#!/bin/bash

# RPi WiFi Fallback Hotspot - Installer v0.7.2 Final Fix
# Author: darkdrago74
# GitHub: https://github.com/darkdrago74/rpi-wifi-fallback
# Version: 0.7.2 - Completely bypass NetworkManager reload during install

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

# Check Debian/Raspberry Pi OS version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    log "✅ Detected OS: $PRETTY_NAME"
fi

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   error "This script should not be run as root. Use: ./install.sh"
fi

log "Starting RPi WiFi Fallback Installation v0.7.2..."
log "=================================================================="

# Update system
log "Updating system packages..."
sudo apt update || error "Failed to update package list"

# Install all packages at once
log "Installing required packages..."
sudo apt install -y \
    hostapd \
    dnsmasq \
    lighttpd \
    iptables \
    iptables-persistent \
    netfilter-persistent \
    iw \
    wireless-tools \
    net-tools \
    git \
    curl \
    wget || error "Failed to install packages"

# Configure services
log "Configuring services..."
sudo systemctl enable netfilter-persistent 2>/dev/null || true
sudo systemctl start netfilter-persistent 2>/dev/null || true

# Enable IP forwarding
log "Enabling IP forwarding..."
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Stop and disable conflicting services
log "Stopping conflicting services..."
sudo systemctl stop hostapd 2>/dev/null || true
sudo systemctl stop dnsmasq 2>/dev/null || true
sudo systemctl disable hostapd 2>/dev/null || true
sudo systemctl disable dnsmasq 2>/dev/null || true

# Handle NetworkManager - DON'T RELOAD, just configure for next boot
if command -v NetworkManager >/dev/null 2>&1 && systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
    log "NetworkManager detected - configuring for next boot..."
    sudo mkdir -p /etc/NetworkManager/conf.d/
    
    # Write the config file
    cat <<'EOF' | sudo tee /etc/NetworkManager/conf.d/99-unmanaged-devices.conf >/dev/null
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
    
    log "NetworkManager configured (will apply after reboot)"
    # DON'T try to reload or use nmcli - it hangs!
else
    log "NetworkManager not active - skipping"
fi

# Handle dhcpcd if present
if systemctl is-enabled --quiet dhcpcd 2>/dev/null; then
    log "Configuring dhcpcd to ignore wlan0..."
    if ! grep -q "denyinterfaces wlan0" /etc/dhcpcd.conf 2>/dev/null; then
        echo "# Added by wifi-fallback installer" | sudo tee -a /etc/dhcpcd.conf
        echo "denyinterfaces wlan0" | sudo tee -a /etc/dhcpcd.conf
    fi
fi

# Create directories
log "Creating directories..."
sudo mkdir -p /usr/local/bin
sudo mkdir -p /var/log
sudo mkdir -p /usr/lib/cgi-bin

# Install scripts
log "Installing WiFi fallback script..."
if [ -f scripts/wifi-fallback.sh ]; then
    sudo cp scripts/wifi-fallback.sh /usr/local/bin/
    sudo chmod +x /usr/local/bin/wifi-fallback.sh
else
    error "scripts/wifi-fallback.sh not found!"
fi

if [ -f config/wifi-fallback.service ]; then
    sudo cp config/wifi-fallback.service /etc/systemd/system/
else
    error "config/wifi-fallback.service not found!"
fi

# Create dnsmasq configuration
log "Creating dnsmasq configuration..."
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
address=/gw.local/192.168.66.66
address=/hotspot.local/192.168.66.66
address=/config.local/192.168.66.66
except-interface=eth0
except-interface=lo
cache-size=150
no-negcache
EOF

# Create hostapd configuration
log "Creating hostapd configuration..."
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

# Configure iptables
log "Configuring firewall rules..."
sudo iptables -F 2>/dev/null || true
sudo iptables -t nat -F 2>/dev/null || true
sudo iptables -P INPUT ACCEPT
sudo iptables -P FORWARD ACCEPT
sudo iptables -P OUTPUT ACCEPT

# Add essential rules
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
sudo iptables -t nat -A POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE
sudo iptables -A FORWARD -i wlan0 -j ACCEPT
sudo iptables -A FORWARD -o wlan0 -j ACCEPT
sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

# Save rules
sudo netfilter-persistent save 2>/dev/null || true

# Install web interface
log "Installing web interface..."
if [ -f web/index.html ]; then
    sudo cp web/index.html /var/www/html/
fi

if [ -f web/wifi-config.cgi ]; then
    sudo cp web/wifi-config.cgi /usr/lib/cgi-bin/
    sudo chmod +x /usr/lib/cgi-bin/wifi-config.cgi
    sudo chown www-data:www-data /usr/lib/cgi-bin/wifi-config.cgi
fi

# Configure sudo for www-data
if ! sudo grep -q "www-data.*wifi-fallback" /etc/sudoers; then
    echo "www-data ALL=(ALL) NOPASSWD: /bin/bash -c *wifi-fallback.conf*, /bin/systemctl restart wifi-fallback.service, /usr/bin/tee -a /var/log/wifi-fallback.log" | sudo tee -a /etc/sudoers
fi

# Install control scripts
if [ -f scripts/hotspot-control.sh ]; then
    sudo cp scripts/hotspot-control.sh /usr/local/bin/hotspot-control
    sudo chmod +x /usr/local/bin/hotspot-control
fi

# Create hotspot command
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

# Create network-reset tool (was missing!)
log "Installing network-reset tool..."
sudo tee /usr/local/bin/network-reset > /dev/null <<'EOF'
#!/bin/bash
echo "Resetting network interfaces..."
sudo systemctl stop wifi-fallback 2>/dev/null || true
sudo killall -9 dhclient dhcpcd wpa_supplicant hostapd dnsmasq 2>/dev/null || true
for iface in eth0 wlan0; do
    sudo ip addr flush dev $iface 2>/dev/null || true
    sudo ip link set $iface down
    sleep 1
    sudo ip link set $iface up
done
sudo ip neigh flush all
sudo systemctl start wifi-fallback
echo "Network reset complete!"
EOF
sudo chmod +x /usr/local/bin/network-reset

# Create netdiag tool
log "Installing diagnostic tool..."
sudo tee /usr/local/bin/netdiag > /dev/null <<'EOF'
#!/bin/bash
echo "=== Network Diagnostics ==="
echo "Date: $(date)"
echo ""
echo "--- Interface Status ---"
ip -br addr show
echo ""
echo "--- WiFi Status ---"
if command -v iwgetid >/dev/null 2>&1; then
    iwgetid wlan0 2>/dev/null || echo "WiFi not connected"
fi
echo ""
echo "--- Services ---"
echo -n "wifi-fallback: "; systemctl is-active wifi-fallback 2>/dev/null || echo "inactive"
echo -n "hostapd: "; systemctl is-active hostapd 2>/dev/null || echo "inactive"
echo -n "dnsmasq: "; systemctl is-active dnsmasq 2>/dev/null || echo "inactive"
EOF
sudo chmod +x /usr/local/bin/netdiag

# Configure lighttpd
log "Configuring web server..."
sudo lighttpd-enable-mod cgi 2>/dev/null || true
if ! grep -q "cgi.assign" /etc/lighttpd/lighttpd.conf; then
    echo 'cgi.assign = ( ".cgi" => "" )' | sudo tee -a /etc/lighttpd/lighttpd.conf
fi

# Unmask hostapd
sudo systemctl unmask hostapd 2>/dev/null || true

# Enable services
log "Enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable lighttpd 2>/dev/null || true
sudo systemctl enable wifi-fallback.service 2>/dev/null || true
sudo systemctl restart lighttpd 2>/dev/null || true

# IMPORTANT: Create initial config with FORCE_HOTSPOT=true for first boot
log "Creating initial configuration with forced hotspot for first boot..."
sudo tee /etc/wifi-fallback.conf > /dev/null <<EOF
MAIN_SSID=""
MAIN_PASSWORD=""
BACKUP_SSID=""
BACKUP_PASSWORD=""
FORCE_HOTSPOT=true
EOF

# Create log file
sudo touch /var/log/wifi-fallback.log
sudo chmod 644 /var/log/wifi-fallback.log

# DON'T start the service now - let it start on boot
log "Service configured to start on boot..."

HOSTNAME=$(hostname)

log "=================================================================="
log "✅ Installation completed successfully!"
log "=================================================================="

# Big clear instructions
echo ""
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗"
echo -e "║                                                                ║"
echo -e "║  ${YELLOW}⚠️  IMPORTANT - FIRST BOOT INSTRUCTIONS ⚠️${CYAN}                  ║"
echo -e "║                                                                ║"
echo -e "║  ${NC}After reboot, device starts in ${RED}HOTSPOT MODE${NC}${CYAN}                 ║"
echo -e "║                                                                ║"
echo -e "║  ${GREEN}1. WiFi Network: ${HOSTNAME}-hotspot${CYAN}                  ║"
echo -e "║  ${GREEN}2. Password: raspberry${CYAN}                                        ║"
echo -e "║  ${GREEN}3. Configure at: http://192.168.66.66:8080${CYAN}                   ║"
echo -e "║                                                                ║"
echo -e "╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${RED}★ REBOOT REQUIRED: ${GREEN}sudo reboot${NC}"
echo ""
