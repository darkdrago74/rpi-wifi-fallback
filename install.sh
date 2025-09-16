#!/bin/bash

# RPi WiFi Fallback Hotspot - Installer v2.4 with Safe iptables
# Author: darkdrago74
# GitHub: https://github.com/darkdrago74/rpi-wifi-fallback
# Version: 2.4.0 - Safe iptables handling

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
if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null && ! grep -q "BCM" /proc/cpuinfo 2>/dev/null; then
    warning "This doesn't appear to be a Raspberry Pi. Continue anyway? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

log "Starting RPi WiFi Fallback Installation v2.4..."
log "=================================================================="

# Update system
log "Updating system packages..."
sudo apt update

# IMPORTANT: Clear any existing iptables rules that might interfere
log "Clearing any problematic iptables rules..."
sudo iptables -F 2>/dev/null || true
sudo iptables -t nat -F 2>/dev/null || true
sudo iptables -X 2>/dev/null || true
sudo iptables -t nat -X 2>/dev/null || true

# Set default policies to ACCEPT to ensure connectivity
sudo iptables -P INPUT ACCEPT 2>/dev/null || true
sudo iptables -P FORWARD ACCEPT 2>/dev/null || true
sudo iptables -P OUTPUT ACCEPT 2>/dev/null || true

# OPTION 1: Install iptables-persistent WITHOUT preconfiguration
# This will show the popup, but with clean rules
log "Installing required packages..."
log "NOTE: When asked about saving iptables rules, you can safely select YES or NO"

# Install packages without pre-configuration
sudo apt install -y \
    hostapd \
    dnsmasq \
    lighttpd \
    git \
    iptables \
    iw \
    wireless-tools \
    net-tools \
    curl \
    wget

# Install iptables-persistent separately with user choice
log "Installing iptables-persistent..."
log "➡️  If prompted about saving rules, select YES to save clean rules"
sudo apt install -y iptables-persistent netfilter-persistent

# Alternative OPTION 2 (commented out): Skip the popup entirely
# If you want to avoid the popup completely, uncomment these lines instead:
# log "Installing iptables-persistent without saving current rules..."
# echo iptables-persistent iptables-persistent/autosave_v4 boolean false | sudo debconf-set-selections
# echo iptables-persistent iptables-persistent/autosave_v6 boolean false | sudo debconf-set-selections
# DEBIAN_FRONTEND=noninteractive sudo apt install -y iptables-persistent netfilter-persistent

# Configure iptables persistence
log "Configuring iptables persistence..."
sudo systemctl enable netfilter-persistent 2>/dev/null || true
sudo systemctl start netfilter-persistent 2>/dev/null || true

# Enable IP forwarding permanently
log "Enabling IP forwarding for NAT..."
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Configure NetworkManager to not interfere with wlan0
log "Configuring NetworkManager compatibility..."
if command -v NetworkManager >/dev/null 2>&1 && systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
    log "NetworkManager detected - configuring to ignore wlan0..."
    
    sudo mkdir -p /etc/NetworkManager/conf.d/
    
    cat <<'EOF' | sudo tee /etc/NetworkManager/conf.d/99-unmanaged-devices.conf >/dev/null
[keyfile]
# Let wifi-fallback manage wlan0
unmanaged-devices=interface-name:wlan0
EOF
    
    if command -v nmcli >/dev/null 2>&1; then
        log "Reloading NetworkManager configuration..."
        sudo timeout 5 nmcli general reload 2>/dev/null || true
        sudo timeout 5 nmcli device set wlan0 managed no 2>/dev/null || true
    fi
    
    log "NetworkManager configured to ignore wlan0"
else
    log "NetworkManager not active - checking for dhcpcd..."
fi

# Handle dhcpcd if present
if systemctl is-enabled --quiet dhcpcd 2>/dev/null; then
    log "dhcpcd detected - configuring to ignore wlan0..."
    
    if ! grep -q "denyinterfaces wlan0" /etc/dhcpcd.conf 2>/dev/null; then
        echo "# Added by wifi-fallback installer" | sudo tee -a /etc/dhcpcd.conf
        echo "denyinterfaces wlan0" | sudo tee -a /etc/dhcpcd.conf
        log "dhcpcd configuration updated (will apply after reboot)"
    fi
fi

# Stop services (will be managed by our script)
log "Configuring services..."
sudo systemctl stop hostapd 2>/dev/null || true
sudo systemctl stop dnsmasq 2>/dev/null || true
sudo systemctl disable hostapd 2>/dev/null || true
sudo systemctl disable dnsmasq 2>/dev/null || true

# Kill any existing DHCP clients on wlan0
sudo killall dhclient 2>/dev/null || true
sudo pkill -f "dhclient.*wlan0" 2>/dev/null || true

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

# Install configuration files
log "Installing configuration files..."
if [ -f config/wifi-fallback.service ]; then
    sudo cp config/wifi-fallback.service /etc/systemd/system/
else
    error "config/wifi-fallback.service not found!"
fi

# Create dnsmasq configuration
log "Creating dnsmasq configuration..."
sudo tee /etc/dnsmasq.conf > /dev/null <<'EOF'
# WiFi Fallback DHCP Configuration
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
address=/printer.local/192.168.66.66
address=/mainsail.local/192.168.66.66
address=/fluidd.local/192.168.66.66
address=/octoprint.local/192.168.66.66
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

# NOW create proper iptables rules
log "Creating proper iptables NAT rules..."

# Clear again to be sure
sudo iptables -F 2>/dev/null || true
sudo iptables -t nat -F 2>/dev/null || true

# Add SSH rule FIRST to ensure access
sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Add our NAT rules for hotspot
sudo iptables -t nat -A POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE

# Add forwarding rules
sudo iptables -A FORWARD -i wlan0 -j ACCEPT
sudo iptables -A FORWARD -o wlan0 -j ACCEPT
sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

# Add other essential rules
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8080 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 67 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 68 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT

# Save the CORRECT rules
log "Saving correct iptables rules..."
sudo netfilter-persistent save

# Also create backup rules file
sudo iptables-save | sudo tee /etc/iptables/rules.v4.backup > /dev/null

log "✅ iptables rules configured and saved"

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

# Configure sudo permissions for www-data
log "Configuring web interface permissions..."
if ! sudo grep -q "www-data.*wifi-fallback" /etc/sudoers; then
    echo "www-data ALL=(ALL) NOPASSWD: /bin/bash -c *wifi-fallback.conf*, /bin/systemctl restart wifi-fallback.service, /usr/bin/tee -a /var/log/wifi-fallback.log" | sudo tee -a /etc/sudoers
fi

# Install hotspot control script
log "Installing hotspot control commands..."
if [ -f scripts/hotspot-control.sh ]; then
    sudo cp scripts/hotspot-control.sh /usr/local/bin/hotspot-control
    sudo chmod +x /usr/local/bin/hotspot-control
fi

# Create hotspot command
log "Creating hotspot command..."
sudo tee /usr/local/bin/hotspot > /dev/null <<'EOF'
#!/bin/bash
case "$1" in
    on|start|enable)
        sudo /usr/local/bin/hotspot-control on
        ;;
    off|stop|disable)
        sudo /usr/local/bin/hotspot-control off
        ;;
    status)
        sudo /usr/local/bin/hotspot-control status
        ;;
    restart)
        sudo /usr/local/bin/hotspot-control restart
        ;;
    *)
        echo "Usage: hotspot {on|off|status|restart}"
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/hotspot

# Create netdiag tool
log "Installing network diagnostics tool..."
sudo tee /usr/local/bin/netdiag > /dev/null <<'EOF'
#!/bin/bash
echo "=== Network Diagnostics ==="
echo "Date: $(date)"
echo ""
echo "--- Interface Status ---"
ip -br addr show
echo ""
echo "--- WiFi Status ---"
iwgetid wlan0 2>/dev/null || echo "WiFi not connected"
echo ""
echo "--- Default Routes ---"
ip route | grep default
echo ""
echo "--- iptables NAT rules ---"
sudo iptables -t nat -L POSTROUTING -n -v | head -5
echo ""
echo "--- Can reach gateway? ---"
gw=$(ip route | grep default | head -1 | awk '{print $3}')
if [ -n "$gw" ]; then
    ping -c 1 -W 2 "$gw" >/dev/null 2>&1 && echo "✓ Gateway $gw reachable" || echo "✗ Gateway $gw unreachable"
fi
echo ""
echo "--- Can reach internet? ---"
ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && echo "✓ Internet reachable" || echo "✗ Internet unreachable"
EOF
sudo chmod +x /usr/local/bin/netdiag

# Configure lighttpd
log "Configuring web server..."
sudo lighttpd-enable-mod cgi 2>/dev/null || true
if ! grep -q "cgi.assign" /etc/lighttpd/lighttpd.conf; then
    echo 'cgi.assign = ( ".cgi" => "" )' | sudo tee -a /etc/lighttpd/lighttpd.conf
fi

# Unmask hostapd
log "Configuring hostapd service..."
sudo systemctl unmask hostapd 2>/dev/null || true

# Enable services
log "Enabling services..."
sudo systemctl daemon-reload
sudo systemctl enable lighttpd 2>/dev/null || true
sudo systemctl enable wifi-fallback.service 2>/dev/null || true
sudo systemctl restart lighttpd 2>/dev/null || true

# Create initial config
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

# Create log file
sudo touch /var/log/wifi-fallback.log
sudo chmod 644 /var/log/wifi-fallback.log

# Start service
log "Starting WiFi fallback service..."
sudo systemctl start wifi-fallback.service 2>/dev/null || true

# Final check
log "Running final diagnostics..."
sleep 2
netdiag

# Get hostname
HOSTNAME=$(hostname)

log "=================================================================="
log "✅ Installation completed successfully!"
log ""
info "📡 Hotspot: ${HOSTNAME}-hotspot (password: raspberry)"
info "🌐 Config: http://192.168.66.66:8080 (in hotspot mode)"
log ""
warning "⚠️  IMPORTANT: Reboot required!"
info "   sudo reboot"
log ""
info "After reboot:"
info "• Check status: hotspot status"
info "• Force hotspot: hotspot on"
info "• Diagnostics: netdiag"
