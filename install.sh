#!/bin/bash

# RPi WiFi Fallback Hotspot - Complete Installer v2.2
# Author: darkdrago74
# GitHub: https://github.com/darkdrago74/rpi-wifi-fallback
# Version: 2.2.0 - With NetworkManager compatibility

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

log "Starting RPi WiFi Fallback Installation v2.2..."
log "=================================================================="

# Update system
log "Updating system packages..."
sudo apt update

# Pre-configure iptables-persistent to avoid prompts
log "Pre-configuring iptables-persistent to save current rules automatically..."
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

# Install required packages INCLUDING iptables and networking tools
log "Installing required packages (including iptables support)..."
DEBIAN_FRONTEND=noninteractive sudo apt install -y \
    hostapd \
    dnsmasq \
    lighttpd \
    git \
    iptables \
    iptables-persistent \
    netfilter-persistent \
    iw \
    wireless-tools \
    net-tools \
    curl \
    wget

# Configure iptables persistence
log "Configuring iptables persistence..."
sudo systemctl enable netfilter-persistent
sudo systemctl start netfilter-persistent

# Enable IP forwarding permanently
log "Enabling IP forwarding for NAT..."
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
fi
sudo sysctl -p

# Configure NetworkManager to not interfere with wlan0
log "Configuring NetworkManager compatibility..."
if systemctl is-active --quiet NetworkManager; then
    log "NetworkManager detected - configuring to ignore wlan0..."
    
    # Tell NetworkManager to ignore wlan0
    sudo mkdir -p /etc/NetworkManager/conf.d/
    sudo tee /etc/NetworkManager/conf.d/99-unmanaged-devices.conf > /dev/null <<EOF
[keyfile]
# Let wifi-fallback manage wlan0
unmanaged-devices=interface-name:wlan0
EOF
    
    # Create ethernet-only profile
    sudo tee /etc/NetworkManager/system-connections/eth0-only.nmconnection > /dev/null <<EOF
[connection]
id=eth0-managed
type=ethernet
interface-name=eth0
autoconnect=true

[ipv4]
method=auto

[ipv6]
method=auto
EOF
    sudo chmod 600 /etc/NetworkManager/system-connections/eth0-only.nmconnection
    
    # Restart NetworkManager to apply changes
    sudo systemctl restart NetworkManager
    log "NetworkManager configured to ignore wlan0"
else
    log "NetworkManager not active - checking for dhcpcd..."
fi

# Handle dhcpcd if present (older Raspberry Pi OS)
if systemctl is-enabled --quiet dhcpcd 2>/dev/null; then
    log "dhcpcd detected - configuring to ignore wlan0..."
    
    # Add denyinterfaces to dhcpcd.conf
    if ! grep -q "denyinterfaces wlan0" /etc/dhcpcd.conf 2>/dev/null; then
        echo "# Added by wifi-fallback installer" | sudo tee -a /etc/dhcpcd.conf
        echo "denyinterfaces wlan0" | sudo tee -a /etc/dhcpcd.conf
        sudo systemctl restart dhcpcd
    fi
    log "dhcpcd configured to ignore wlan0"
fi

# Stop services (will be managed by our script)
log "Configuring services..."
sudo systemctl stop hostapd dnsmasq 2>/dev/null || true
sudo systemctl disable hostapd dnsmasq 2>/dev/null || true

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
sudo cp scripts/wifi-fallback.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/wifi-fallback.sh

# Install configuration files
log "Installing configuration files..."
sudo cp config/wifi-fallback.service /etc/systemd/system/

# Create improved dnsmasq configuration
log "Creating dnsmasq configuration..."
sudo tee /etc/dnsmasq.conf > /dev/null <<'EOF'
# WiFi Fallback DHCP Configuration
# Only bind to wlan0 when in hotspot mode
interface=wlan0
bind-interfaces
listen-address=192.168.66.66

# DHCP range for hotspot clients
dhcp-range=192.168.66.10,192.168.66.50,255.255.255.0,24h

# Router and DNS options
dhcp-option=3,192.168.66.66
dhcp-option=6,8.8.8.8,8.8.4.4

# Upstream DNS servers
server=8.8.8.8
server=8.8.4.4

# Don't read /etc/resolv.conf
no-resolv

# Logging (comment out for production)
log-queries
log-dhcp

# Local domain resolution for convenience
address=/gw.local/192.168.66.66
address=/hotspot.local/192.168.66.66
address=/config.local/192.168.66.66
address=/printer.local/192.168.66.66
address=/mainsail.local/192.168.66.66
address=/fluidd.local/192.168.66.66
address=/octoprint.local/192.168.66.66

# Prevent dnsmasq from interfering with other interfaces
except-interface=eth0
except-interface=lo

# Cache settings
cache-size=150
no-negcache
EOF

# Create hostapd configuration dynamically
log "Creating hostapd configuration..."
HOSTNAME=$(hostname)
sudo tee /etc/hostapd/hostapd.conf > /dev/null <<EOF
# WiFi Fallback Hotspot Configuration
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

# Create iptables rules for hotspot NAT
log "Creating iptables NAT rules..."

# Ensure iptables directory exists with proper permissions
sudo mkdir -p /etc/iptables
sudo chmod 755 /etc/iptables

# Create the rules file with proper sudo permissions
sudo bash -c 'cat > /etc/iptables/rules.v4' <<'EOF'
# Generated by rpi-wifi-fallback installer v2.2
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]

# NAT for hotspot subnet - will route through any available interface
-A POSTROUTING -s 192.168.66.0/24 ! -d 192.168.66.0/24 -j MASQUERADE

COMMIT

*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

# Allow forwarding from/to hotspot subnet
-A FORWARD -i wlan0 -j ACCEPT
-A FORWARD -o wlan0 -j ACCEPT
-A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

# Allow loopback
-A INPUT -i lo -j ACCEPT

# Allow established connections
-A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT

# Allow SSH (important for remote access) - MUST be first
-I INPUT 1 -p tcp --dport 22 -j ACCEPT

# Allow HTTP and HTTPS
-A INPUT -p tcp --dport 80 -j ACCEPT
-A INPUT -p tcp --dport 443 -j ACCEPT

# Allow WiFi configuration interface
-A INPUT -p tcp --dport 8080 -j ACCEPT

# Allow DHCP
-A INPUT -p udp --dport 67 -j ACCEPT
-A INPUT -p udp --dport 68 -j ACCEPT

# Allow DNS
-A INPUT -p udp --dport 53 -j ACCEPT
-A INPUT -p tcp --dport 53 -j ACCEPT

COMMIT
EOF

# Verify the file was created successfully
if [ ! -f /etc/iptables/rules.v4 ]; then
    error "Failed to create iptables rules file"
fi

# Load iptables rules with better error handling
log "Loading iptables rules..."
if sudo iptables-restore < /etc/iptables/rules.v4; then
    log "✅ iptables rules loaded successfully"
else
    warning "Failed to load iptables rules - continuing anyway"
fi

# Save current iptables rules
if sudo netfilter-persistent save; then
    log "✅ iptables rules saved for persistence"
else
    warning "Failed to save persistent rules - manual save may be required"
fi

# Install web interface
log "Installing web interface..."
sudo cp web/index.html /var/www/html/
sudo cp web/wifi-config.cgi /usr/lib/cgi-bin/
sudo chmod +x /usr/lib/cgi-bin/wifi-config.cgi
sudo chown www-data:www-data /usr/lib/cgi-bin/wifi-config.cgi

# Configure sudo permissions for www-data
log "Configuring web interface permissions..."
if ! sudo grep -q "www-data.*wifi-fallback" /etc/sudoers; then
    echo "www-data ALL=(ALL) NOPASSWD: /bin/bash -c *wifi-fallback.conf*, /bin/systemctl restart wifi-fallback.service, /usr/bin/tee -a /var/log/wifi-fallback.log" | sudo tee -a /etc/sudoers
fi

# Install enhanced hotspot control script
log "Installing hotspot control commands..."
sudo cp scripts/hotspot-control.sh /usr/local/bin/hotspot-control
sudo chmod +x /usr/local/bin/hotspot-control

# Create convenient hotspot command
log "Creating hotspot command alias..."
sudo tee /usr/local/bin/hotspot > /dev/null <<'EOF'
#!/bin/bash
# Hotspot control command wrapper
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
        echo "  on/start   - Enable manual hotspot mode"
        echo "  off/stop   - Disable manual hotspot mode"
        echo "  status     - Show current hotspot status"
        echo "  restart    - Restart WiFi fallback service"
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/hotspot

# Create network diagnostics tool
log "Installing network diagnostics tool..."
sudo tee /usr/local/bin/netdiag > /dev/null <<'EOF'
#!/bin/bash
echo "=== Network Diagnostics ==="
echo "Date: $(date)"
echo ""

echo "--- Interface Status ---"
ip -br addr show

echo ""
echo "--- Default Routes ---"
ip route | grep default

echo ""
echo "--- WiFi Status ---"
if command -v iwgetid >/dev/null 2>&1; then
    iwgetid wlan0 2>/dev/null || echo "WiFi not connected"
fi

echo ""
echo "--- DHCP Clients Running ---"
ps aux | grep -E "dhclient|dhcpcd" | grep -v grep

echo ""
echo "--- Network Manager Status ---"
systemctl is-active NetworkManager 2>/dev/null || echo "inactive"

echo ""
echo "--- WiFi Fallback Status ---"
systemctl is-active wifi-fallback

echo ""
echo "--- Can reach gateway? ---"
gw=$(ip route | grep default | head -1 | awk '{print $3}')
if [ -n "$gw" ]; then
    ping -c 1 -W 2 "$gw" >/dev/null 2>&1 && echo "✓ Gateway $gw reachable" || echo "✗ Gateway $gw unreachable"
fi

echo ""
echo "--- Can reach internet? ---"
ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 && echo "✓ Internet reachable" || echo "✗ Internet unreachable"

echo ""
echo "--- SSH Status ---"
sudo netstat -tlnp | grep :22 | head -1

echo ""
echo "--- ARP Table (local network) ---"
arp -n | grep -v incomplete | head -5
EOF
sudo chmod +x /usr/local/bin/netdiag

# Create network reset utility
log "Installing network reset utility..."
sudo tee /usr/local/bin/network-reset > /dev/null <<'EOF'
#!/bin/bash
echo "Resetting all network interfaces..."

# Stop all network services
sudo systemctl stop NetworkManager 2>/dev/null || true
sudo systemctl stop wifi-fallback 2>/dev/null || true

# Kill all DHCP clients
sudo killall -9 dhclient dhcpcd wpa_supplicant hostapd dnsmasq 2>/dev/null || true

# Flush all interfaces
for iface in eth0 wlan0; do
    sudo ip addr flush dev $iface 2>/dev/null || true
    sudo ip link set $iface down
    sleep 1
    sudo ip link set $iface up
done

# Clear ARP cache
sudo ip neigh flush all

# Restart services
sudo systemctl start NetworkManager 2>/dev/null || true
sudo systemctl start wifi-fallback

echo "Network reset complete!"
EOF
sudo chmod +x /usr/local/bin/network-reset

# Add to system PATH if not already there
if ! grep -q "/usr/local/bin" /etc/environment 2>/dev/null; then
    echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' | sudo tee -a /etc/environment
fi

# Configure lighttpd for CGI
log "Configuring web server..."
sudo lighttpd-enable-mod cgi 2>/dev/null || true
sudo sed -i 's/#.*"mod_cgi"/    "mod_cgi",/' /etc/lighttpd/lighttpd.conf
if ! grep -q "cgi.assign" /etc/lighttpd/lighttpd.conf; then
    echo 'cgi.assign = ( ".cgi" => "" )' | sudo tee -a /etc/lighttpd/lighttpd.conf
fi

# Unmask and configure hostapd (Raspberry Pi OS masks it by default)
log "Configuring hostapd service..."
sudo systemctl unmask hostapd 2>/dev/null || true
sudo systemctl stop hostapd dnsmasq 2>/dev/null || true
sudo systemctl disable hostapd dnsmasq 2>/dev/null || true

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

# Create log file with proper permissions
sudo touch /var/log/wifi-fallback.log
sudo chmod 644 /var/log/wifi-fallback.log

# Get hostname for hotspot name
HOSTNAME=$(hostname)

log "=================================================================="
log "✅ Installation completed successfully!"
log ""
info "Version 2.2.0 - NetworkManager Compatible"
log ""
info "📡 Hotspot will be named: ${HOSTNAME}-hotspot"
info "🔑 Hotspot password: raspberry"
info "🌐 Web interface: http://192.168.66.66:8080 (when in hotspot mode)"
log ""
info "🔧 How to configure:"
info "1. If you have Ethernet connected, configure via SSH now"
info "2. Or wait for hotspot to activate (if no WiFi configured)"
info "3. Connect to ${HOSTNAME}-hotspot and visit http://192.168.66.66:8080"
log ""
info "📋 Commands:"
info "  Check status: hotspot status"
info "  Network diagnostics: netdiag"
info "  Force hotspot: hotspot on"
info "  Return to WiFi: hotspot off"
info "  Reset network: network-reset"
info "  View logs: sudo tail -f /var/log/wifi-fallback.log"
info "  Restart service: sudo systemctl restart wifi-fallback"
log ""
info "🔥 Features:"
info "• Automatic WiFi fallback to hotspot"
info "• Manual hotspot mode for coworker access"
info "• Internet sharing through NAT"
info "• Web configuration interface"
info "• Dual network support (primary + backup)"
info "• NetworkManager compatibility"
info "• Works with any router IP scheme"
log ""
warning "⚠️  Reboot recommended to ensure all services start properly"
info "   sudo reboot"
